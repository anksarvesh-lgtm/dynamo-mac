// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.core

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import app.maclink.android.BuildConfig
import app.maclink.core.KeyProtector
import app.maclink.core.MacLinkException
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Encrypts the device's identity key with an AES-GCM key that lives in the
 * Android Keystore and can't be exported. Format: 12-byte IV, then the
 * ciphertext with its 128-bit authentication tag.
 *
 * Supports transparent backwards-compatible migration from legacy Keystore
 * aliases (e.g. `nectarlink.identity.v1`) to the current alias (`maclink.identity.v1`).
 */
class KeystoreKeyProtector(
    private val keyFile: File? = null,
    private val backend: KeyStoreBackend = AndroidKeyStoreBackend,
) : KeyProtector {

    private fun logI(msg: String) {
        runCatching { Log.i(TAG, msg) }.onFailure { println("[$TAG] $msg") }
    }

    private fun logW(msg: String) {
        runCatching { Log.w(TAG, msg) }.onFailure { println("[$TAG] WARN: $msg") }
    }

    private fun logE(msg: String, tr: Throwable? = null) {
        runCatching { Log.e(TAG, msg, tr) }.onFailure {
            println("[$TAG] ERROR: $msg")
            tr?.printStackTrace()
        }
    }

    override fun protect(plaintext: ByteArray): ByteArray = guard {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, backend.getOrCreateKey(LegacyNames.KEYSTORE_ALIAS_CURRENT))
        cipher.iv + cipher.doFinal(plaintext)
    }

    override fun unprotect(ciphertext: ByteArray): ByteArray = guard {
        require(ciphertext.size > IV_LENGTH) { "protected key is too short (${ciphertext.size} bytes <= $IV_LENGTH)" }

        var currentError: Throwable? = null
        var legacyError: Throwable? = null

        // 1. First, attempt decryption with current Keystore alias
        val currentKey = backend.getKey(LegacyNames.KEYSTORE_ALIAS_CURRENT)
        if (currentKey != null) {
            try {
                return@guard decryptWith(currentKey, ciphertext)
            } catch (e: Exception) {
                currentError = e
                logW("Decryption with current alias '${LegacyNames.KEYSTORE_ALIAS_CURRENT}' failed: ${e.javaClass.simpleName}: ${e.message}")
            }
        }

        // 2. Fall back to legacy Keystore alias
        val legacyKey = backend.getKey(LegacyNames.KEYSTORE_ALIAS_V0)
        if (legacyKey != null) {
            try {
                val plaintext = decryptWith(legacyKey, ciphertext)
                logI("Decrypted identity key using legacy alias '${LegacyNames.KEYSTORE_ALIAS_V0}'. Starting migration...")
                migrateKey(plaintext)
                return@guard plaintext
            } catch (e: Exception) {
                legacyError = e
                logW("Decryption with legacy alias '${LegacyNames.KEYSTORE_ALIAS_V0}' failed: ${e.javaClass.simpleName}: ${e.message}")
            }
        }

        // 3. Both failed or keys missing: report full failure cause chain
        val message = buildString {
            append("Keystore decryption failed for all aliases.")
            if (currentError != null) append(" [current: ${currentError.javaClass.simpleName}: ${currentError.message}]")
            if (legacyError != null) append(" [legacy: ${legacyError.javaClass.simpleName}: ${legacyError.message}]")
            if (currentKey == null && legacyKey == null) append(" Neither current nor legacy alias exists in Keystore.")
        }
        val failure = IllegalStateException(message)
        currentError?.let { failure.initCause(it) } ?: legacyError?.let { failure.initCause(it) }
        throw failure
    }

    private fun decryptWith(key: SecretKey, ciphertext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(TAG_BITS, ciphertext, 0, IV_LENGTH))
        return cipher.doFinal(ciphertext, IV_LENGTH, ciphertext.size - IV_LENGTH)
    }

    private fun encryptWith(key: SecretKey, plaintext: ByteArray): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key)
        return cipher.iv + cipher.doFinal(plaintext)
    }

    /**
     * Re-encrypts the legacy plaintext with the current Keystore alias,
     * writes it to an atomic temporary file, validates decryption, replaces the
     * key file, and deletes the legacy Keystore entry.
     */
    private fun migrateKey(plaintext: ByteArray) {
        runCatching {
            val curKey = backend.getOrCreateKey(LegacyNames.KEYSTORE_ALIAS_CURRENT)
            val newSealed = encryptWith(curKey, plaintext)

            if (keyFile != null && keyFile.exists()) {
                val parentDir = keyFile.parentFile ?: keyFile.canonicalFile.parentFile
                val tmpFile = File(parentDir, "${keyFile.name}.tmp")
                val fullPayload = MAGIC_NLK1 + byteArrayOf(METHOD_ANDROID_KEYSTORE) + newSealed

                FileOutputStream(tmpFile).use { fos ->
                    fos.write(fullPayload)
                    fos.flush()
                    fos.fd.sync()
                }

                // Verify decryption before replacing the file
                val verifyDecrypted = decryptWith(curKey, newSealed)
                check(verifyDecrypted.contentEquals(plaintext)) {
                    "Verification of re-encrypted device key failed"
                }

                // Atomic rename over the existing file
                Files.move(
                    tmpFile.toPath(),
                    keyFile.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING,
                )

                // Delete the legacy Keystore key
                backend.deleteKey(LegacyNames.KEYSTORE_ALIAS_V0)
                logI("device key migrated")
            } else {
                logI("device key migrated (in-memory; on-disk file will be saved by core)")
            }
        }.onFailure { e ->
            logE("failed to migrate legacy device key to current alias", e)
        }
    }

    /** Reports Keystore failures with full cause chain details to core instead of crashing. */
    private inline fun guard(block: () -> ByteArray): ByteArray = try {
        block()
    } catch (e: Exception) {
        val chain = formatCauseChain(e)
        logE("keystore: $chain", e)
        throw MacLinkException.Internal("keystore: $chain")
    }

    companion object {
        const val TAG = "KeystoreProtector"
        const val KEYSTORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val IV_LENGTH = 12
        const val TAG_BITS = 128

        val MAGIC_NLK1 = byteArrayOf('N'.code.toByte(), 'L'.code.toByte(), 'K'.code.toByte(), '1'.code.toByte())
        const val METHOD_ANDROID_KEYSTORE: Byte = 2

        fun formatCauseChain(t: Throwable): String = buildString {
            var cur: Throwable? = t
            var depth = 0
            while (cur != null && depth < 10) {
                if (depth > 0) append(" -> caused by ")
                append(cur.javaClass.simpleName)
                val msg = cur.message
                if (!msg.isNullOrBlank()) {
                    append(": ").append(msg)
                }
                cur = cur.cause
                depth++
            }
        }
    }
}

/**
 * Abstraction over KeyStore for testability on standard JVM without hardware Keystore.
 */
interface KeyStoreBackend {
    fun getKey(alias: String): SecretKey?
    fun getOrCreateKey(alias: String): SecretKey
    fun deleteKey(alias: String)
    fun listAliases(): List<String>
    fun containsAlias(alias: String): Boolean
}

/**
 * Standard hardware-backed AndroidKeyStore implementation.
 */
object AndroidKeyStoreBackend : KeyStoreBackend {
    init {
        if (BuildConfig.DEBUG) {
            runCatching {
                val store = KeyStore.getInstance(KeystoreKeyProtector.KEYSTORE).apply { load(null) }
                val aliases = store.aliases().asSequence().map { alias ->
                    val creation = runCatching { store.getCreationDate(alias) }.getOrNull()
                    "$alias (created=$creation)"
                }.toList()
                Log.d(KeystoreKeyProtector.TAG, "AndroidKeyStore aliases on startup: $aliases")
            }
        }
    }

    override fun getKey(alias: String): SecretKey? {
        val store = KeyStore.getInstance(KeystoreKeyProtector.KEYSTORE).apply { load(null) }
        return store.getKey(alias, null) as? SecretKey
    }

    override fun getOrCreateKey(alias: String): SecretKey {
        val existing = getKey(alias)
        if (existing != null) return existing
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KeystoreKeyProtector.KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    override fun deleteKey(alias: String) {
        runCatching {
            val store = KeyStore.getInstance(KeystoreKeyProtector.KEYSTORE).apply { load(null) }
            if (store.containsAlias(alias)) {
                store.deleteEntry(alias)
            }
        }
    }

    override fun listAliases(): List<String> {
        return runCatching {
            val store = KeyStore.getInstance(KeystoreKeyProtector.KEYSTORE).apply { load(null) }
            store.aliases().toList()
        }.getOrDefault(emptyList())
    }

    override fun containsAlias(alias: String): Boolean {
        return runCatching {
            val store = KeyStore.getInstance(KeystoreKeyProtector.KEYSTORE).apply { load(null) }
            store.containsAlias(alias)
        }.getOrDefault(false)
    }
}
