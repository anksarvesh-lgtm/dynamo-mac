// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.core

import android.content.Context
import android.util.Log

/**
 * Gives the core the app's [Context], so its network code reads the phone's own DNS servers
 * instead of falling back to public ones (which some networks block). Once, before the core
 * starts.
 */
object AndroidContext {
    @Volatile private var installed = false

    fun install(context: Context) {
        if (installed) return
        installed = true
        runCatching {
            // The core's library, as JNA loads it for everything else: the same copy.
            try {
                System.loadLibrary("maclink_ffi")
            } catch (e: Throwable) {
                System.loadLibrary("maclink_ffi")
            }
            nativeInstall(context.applicationContext)
        }.onFailure { Log.w(TAG, "the core can't read the phone's DNS servers", it) }
    }

    @JvmStatic private external fun nativeInstall(context: Context)

    private const val TAG = "AndroidContext"
}
