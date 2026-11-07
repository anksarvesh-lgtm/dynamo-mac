// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.storage.ftp

import android.content.Context
import android.net.wifi.WifiManager
import android.util.Log
import app.maclink.android.storage.PhoneStorage
import com.guichaguri.minimalftp.FTPServer
import com.guichaguri.minimalftp.api.IUserAuthenticator
import com.guichaguri.minimalftp.impl.NoOpAuthenticator
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import java.net.Inet4Address
import java.net.NetworkInterface
import java.util.Collections

/**
 * State of the embedded FTP server.
 */
data class FtpServerState(
    val isRunning: Boolean = false,
    val port: Int = 0,
    val ipAddress: String = "",
    val url: String = "",
    val username: String? = null,
    val error: String? = null,
)

/**
 * Manages the embedded MinimalFTP server for fast, zero-dependency file browsing on Android.
 */
class FtpServerManager private constructor(private val context: Context) {

    private val _state = MutableStateFlow(FtpServerState())
    val state: StateFlow<FtpServerState> = _state.asStateFlow()

    private var server: FTPServer? = null

    @Synchronized
    fun start(
        port: Int = DEFAULT_PORT,
        username: String? = null,
        password: String? = null,
        rootOverride: File? = null,
    ): Result<Int> {
        if (_state.value.isRunning) {
            return Result.success(_state.value.port)
        }

        try {
            val root = rootOverride ?: PhoneStorage.sharedRoot()
            val fs = AndroidFtpFileSystem(context, root)

            val ftpServer = FTPServer()
            
            if (!username.isNullOrEmpty() && password != null) {
                ftpServer.authenticator = object : IUserAuthenticator {
                    override fun needsUsername(con: com.guichaguri.minimalftp.FTPConnection?): Boolean = true
                    override fun needsPassword(con: com.guichaguri.minimalftp.FTPConnection?, user: String?, address: java.net.InetAddress?): Boolean = true
                    override fun authenticate(con: com.guichaguri.minimalftp.FTPConnection?, host: java.net.InetAddress?, user: String?, pass: String?): com.guichaguri.minimalftp.api.IFileSystem<*>? {
                        return if (user == username && pass == password) fs else null
                    }
                }
            } else {
                ftpServer.authenticator = NoOpAuthenticator(fs)
            }

            ftpServer.listen(port)
            val actualPort = ftpServer.port
            val ip = getLocalIpAddress()
            val url = "ftp://$ip:$actualPort"

            server = ftpServer
            _state.value = FtpServerState(
                isRunning = true,
                port = actualPort,
                ipAddress = ip,
                url = url,
                username = username,
                error = null,
            )

            Log.i(TAG, "MinimalFTP server started at $url serving ${root.absolutePath}")
            return Result.success(actualPort)
        } catch (e: Exception) {
            val err = "Failed to start FTP server: ${e.message}"
            Log.e(TAG, err, e)
            _state.value = FtpServerState(isRunning = false, error = err)
            return Result.failure(e)
        }
    }

    @Synchronized
    fun stop() {
        try {
            server?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Error closing FTP server", e)
        } finally {
            server = null
            _state.value = FtpServerState(isRunning = false)
            Log.i(TAG, "MinimalFTP server stopped")
        }
    }

    fun getLocalIpAddress(): String {
        try {
            val interfaces = Collections.list(NetworkInterface.getNetworkInterfaces())
            for (intf in interfaces) {
                if (intf.isLoopback || !intf.isUp) continue
                val addrs = Collections.list(intf.inetAddresses)
                for (addr in addrs) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        val host = addr.hostAddress
                        if (!host.isNullOrEmpty() && !host.startsWith("127.")) {
                            return host
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Could not determine local IP", e)
        }
        return "127.0.0.1"
    }

    companion object {
        private const val TAG = "MacLinkFtp"
        const val DEFAULT_PORT = 2121

        @Volatile
        private var instance: FtpServerManager? = null

        fun getInstance(context: Context): FtpServerManager =
            instance ?: synchronized(this) {
                instance ?: FtpServerManager(context.applicationContext).also { instance = it }
            }
    }
}

