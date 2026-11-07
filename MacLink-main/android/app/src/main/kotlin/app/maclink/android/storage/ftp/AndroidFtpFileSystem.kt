// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.storage.ftp

import android.content.Context
import app.maclink.android.storage.PhoneStorage
import com.guichaguri.minimalftp.impl.NativeFileSystem
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

/**
 * Sandboxed NativeFileSystem for MinimalFTP on Android.
 * Enforces MacLink security boundaries:
 * - Restricts browsing to the shared storage root.
 * - Blocks access to /data, Android/data, Android/obb, and app private directories.
 * - Rejects hidden .maclink token files and directory traversal attempts.
 */
class AndroidFtpFileSystem(
    private val context: Context,
    root: File = PhoneStorage.sharedRoot(),
) : NativeFileSystem(root) {

    private val blockedDirs = PhoneStorage.blockedDirs(context, root)
    private val canonRoot = runCatching { root.canonicalFile }.getOrElse { root }

    private fun isPathPermitted(file: File): Boolean {
        val canon = runCatching { file.canonicalFile }.getOrNull() ?: return false
        val canonPath = canon.path
        val rootPath = canonRoot.path

        // Must be within root
        if (!canonPath.startsWith(rootPath)) return false

        // Must not start with .maclink
        if (canon.name.startsWith(".maclink")) return false

        // Must not be in any blocked directory
        for (blocked in blockedDirs) {
            val bPath = runCatching { blocked.canonicalPath }.getOrNull() ?: blocked.path
            if (canonPath == bPath || canonPath.startsWith("$bPath/")) {
                return false
            }
        }
        return true
    }

    override fun exists(file: File): Boolean {
        if (!isPathPermitted(file)) return false
        return super.exists(file)
    }

    override fun findFile(path: String): File {
        val f = super.findFile(path)
        if (!isPathPermitted(f)) {
            throw FileNotFoundException("Access denied: $path")
        }
        return f
    }

    override fun findFile(cwd: File, path: String): File {
        val f = super.findFile(cwd, path)
        if (!isPathPermitted(f)) {
            throw FileNotFoundException("Access denied: $path")
        }
        return f
    }

    override fun listFiles(dir: File): Array<File> {
        if (!isPathPermitted(dir)) return emptyArray()
        val all = super.listFiles(dir) ?: return emptyArray()
        return all.filter { isPathPermitted(it) }.toTypedArray()
    }

    override fun delete(file: File) {
        if (!isPathPermitted(file)) throw IOException("Permission denied")
        super.delete(file)
    }

    override fun mkdirs(file: File) {
        if (!isPathPermitted(file)) throw IOException("Permission denied")
        super.mkdirs(file)
    }

    override fun rename(from: File, to: File) {
        if (!isPathPermitted(from) || !isPathPermitted(to)) throw IOException("Permission denied")
        super.rename(from, to)
    }
}

