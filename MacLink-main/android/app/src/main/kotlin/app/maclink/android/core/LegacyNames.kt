// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.core

/**
 * Legacy aliases, identifiers, and configuration names preserved for backwards-compatible migration.
 *
 * CRITICAL RULE: NEVER rename or remove these constants without a backwards-compatible migration fallback!
 * Android Keystore keys are permanently tied to their alias string and cannot be renamed or moved.
 * Renaming an alias causes the app to generate a fresh, unlinked key while leaving existing encrypted
 * files unreadable (throwing javax.crypto.AEADBadTagException).
 */
object LegacyNames {
    /**
     * Legacy Android Keystore alias used prior to the MacLink rebrand.
     * Protects the device identity key file (`identity.key`).
     */
    const val KEYSTORE_ALIAS_V0 = "nectarlink.identity.v1"

    /**
     * Current Android Keystore alias protecting the device identity key.
     */
    const val KEYSTORE_ALIAS_CURRENT = "maclink.identity.v1"

    /**
     * Legacy AAD (Additional Authenticated Data) values, if ever used in key derivation or cipher setup.
     * Note: KeystoreKeyProtector uses standard AES-256-GCM with a 12-byte IV and 128-bit tag without
     * custom AAD, but this constant is preserved to prevent accidental divergent AAD introduction.
     */
    const val LEGACY_AAD = ""
    const val CURRENT_AAD = ""
}

