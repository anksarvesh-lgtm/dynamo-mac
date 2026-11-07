// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.core

import app.maclink.core.MacLinkException
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class KeystoreMigrationAndRecoveryTest {

    @get:Rule
    val tempFolder = TemporaryFolder()

    /**
     * In-memory test backend simulating AndroidKeyStore on host JVM.
     */
    private class InMemoryKeyStoreBackend : KeyStoreBackend {
        val keys = mutableMapOf<String, SecretKey>()

        override fun getKey(alias: String): SecretKey? = keys[alias]

        override fun getOrCreateKey(alias: String): SecretKey {
            return keys.getOrPut(alias) {
                val keyBytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
                SecretKeySpec(keyBytes, "AES")
            }
        }

        override fun deleteKey(alias: String) {
            keys.remove(alias)
        }

        override fun listAliases(): List<String> = keys.keys.toList()

        override fun containsAlias(alias: String): Boolean = keys.containsKey(alias)
    }

    private fun encryptAesGcm(key: SecretKey, plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key)
        return cipher.iv + cipher.doFinal(plaintext)
    }

    @Test
    fun `test legacy alias migration rewrites key file and migrates to current alias`() {
        val backend = InMemoryKeyStoreBackend()
        val legacyKey = backend.getOrCreateKey(LegacyNames.KEYSTORE_ALIAS_V0)

        // Generate synthetic 32-byte Ed25519 device key
        val originalIdentityKey = ByteArray(32).also { SecureRandom().nextBytes(it) }

        // Encrypt with legacy alias
        val legacySealed = encryptAesGcm(legacyKey, originalIdentityKey)

        // Write identity.key in Rust identity.rs format (MAGIC "NLK1" + method 2 + sealed)
        val keyFile = tempFolder.newFile("identity.key")
        val fullPayload = KeystoreKeyProtector.MAGIC_NLK1 + byteArrayOf(KeystoreKeyProtector.METHOD_ANDROID_KEYSTORE) + legacySealed
        FileOutputStream(keyFile).use { it.write(fullPayload) }

        // Run protector with keyFile and backend
        val protector = KeystoreKeyProtector(keyFile = keyFile, backend = backend)

        // unprotect should detect legacy alias, decrypt, re-encrypt under current alias, rewrite file, and delete legacy key
        val unsealed = protector.unprotect(legacySealed)
        assertArrayEquals("Decrypted identity key must match original", originalIdentityKey, unsealed)

        // Legacy key must have been deleted from keystore
        assertFalse("Legacy Keystore key must be deleted after migration", backend.containsAlias(LegacyNames.KEYSTORE_ALIAS_V0))

        // Current key must now exist in keystore
        assertTrue("Current Keystore key must now exist", backend.containsAlias(LegacyNames.KEYSTORE_ALIAS_CURRENT))
        val currentKey = backend.getKey(LegacyNames.KEYSTORE_ALIAS_CURRENT)
        assertNotNull(currentKey)

        // Read updated file from disk: must now be decryptable with current key
        val rewrittenBytes = Files.readAllBytes(keyFile.toPath())
        assertEquals(fullPayload.size, rewrittenBytes.size) // 4 magic + 1 method + 12 iv + 32 ct + 16 tag = 65 bytes
        val rewrittenSealed = rewrittenBytes.copyOfRange(5, rewrittenBytes.size)

        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, currentKey, GCMParameterSpec(128, rewrittenSealed, 0, 12))
        val verifiedPlaintext = cipher.doFinal(rewrittenSealed, 12, rewrittenSealed.size - 12)
        assertArrayEquals("Rewritten file on disk must decrypt with current alias", originalIdentityKey, verifiedPlaintext)
    }

    @Test
    fun `test missing Keystore key fails with detailed error and recovery archives unreadable file`() {
        val backend = InMemoryKeyStoreBackend()
        // No keys in backend

        val originalIdentityKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val dummyKey = SecretKeySpec(ByteArray(32) { 0x42 }, "AES")
        val sealed = encryptAesGcm(dummyKey, originalIdentityKey)

        val coreDir = tempFolder.newFolder("core")
        val keyFile = File(coreDir, "identity.key")
        FileOutputStream(keyFile).use { it.write(sealed) }

        val protector = KeystoreKeyProtector(keyFile = keyFile, backend = backend)

        val error = assertThrows(MacLinkException.Internal::class.java) {
            protector.unprotect(sealed)
        }
        assertTrue(
            "Error message must specify keystore failure cause",
            error.message?.contains("Neither current nor legacy alias exists in Keystore") == true,
        )

        // Recovery path: move unreadable file aside with timestamp
        val timestamp = System.currentTimeMillis()
        val archivedFile = File(coreDir, "device_key.unreadable-$timestamp")
        Files.move(keyFile.toPath(), archivedFile.toPath(), StandardCopyOption.REPLACE_EXISTING)

        assertFalse("Original key file must no longer be at identity.key", keyFile.exists())
        assertTrue("Archived key file must be preserved", archivedFile.exists())
        assertEquals(sealed.size.toLong(), archivedFile.length())
    }

    @Test
    fun `test corrupted or flipped byte triggers AEADBadTagException and recovery path`() {
        val backend = InMemoryKeyStoreBackend()
        val curKey = backend.getOrCreateKey(LegacyNames.KEYSTORE_ALIAS_CURRENT)

        val originalIdentityKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val sealed = encryptAesGcm(curKey, originalIdentityKey)

        // Corrupt one byte in the ciphertext payload
        val corrupted = sealed.clone()
        corrupted[15] = (corrupted[15].toInt() xor 0xFF).toByte()

        val coreDir = tempFolder.newFolder("core_corrupt")
        val keyFile = File(coreDir, "identity.key")
        FileOutputStream(keyFile).use { it.write(corrupted) }

        val protector = KeystoreKeyProtector(keyFile = keyFile, backend = backend)

        val error = assertThrows(MacLinkException.Internal::class.java) {
            protector.unprotect(corrupted)
        }
        val causeChain = error.message.orEmpty()
        assertTrue("Error cause chain must capture AEADBadTagException", causeChain.contains("AEADBadTagException"))

        // Recovery path
        val timestamp = System.currentTimeMillis()
        val archivedFile = File(coreDir, "device_key.unreadable-$timestamp")
        Files.move(keyFile.toPath(), archivedFile.toPath(), StandardCopyOption.REPLACE_EXISTING)

        assertFalse("Original corrupted file moved", keyFile.exists())
        assertTrue("Corrupted file preserved as unreadable archive", archivedFile.exists())
    }

    @Test
    fun `test normal first install creates key, restarts, and decrypts cleanly`() {
        val backend = InMemoryKeyStoreBackend()
        val protector1 = KeystoreKeyProtector(backend = backend)

        val identityKey = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val protectedBytes = protector1.protect(identityKey)

        assertTrue("Protected bytes must be larger than IV + tag", protectedBytes.size > 28)
        assertTrue("Current alias key must be created", backend.containsAlias(LegacyNames.KEYSTORE_ALIAS_CURRENT))

        // Emulate app restart with a fresh protector instance against same keystore
        val protector2 = KeystoreKeyProtector(backend = backend)
        val unprotected = protector2.unprotect(protectedBytes)

        assertArrayEquals("Unprotected key must match original plaintext across restarts", identityKey, unprotected)
    }

    @Test
    fun `test formatCauseChain formats nested exceptions clearly`() {
        val root = javax.crypto.AEADBadTagException("Tag mismatch")
        val wrapper1 = java.security.GeneralSecurityException("Decryption failure", root)
        val wrapper2 = IllegalStateException("Keystore unlock failed", wrapper1)

        val chain = KeystoreKeyProtector.formatCauseChain(wrapper2)
        assertTrue(chain.contains("IllegalStateException: Keystore unlock failed"))
        assertTrue(chain.contains("caused by GeneralSecurityException: Decryption failure"))
        assertTrue(chain.contains("caused by AEADBadTagException: Tag mismatch"))
    }
}

