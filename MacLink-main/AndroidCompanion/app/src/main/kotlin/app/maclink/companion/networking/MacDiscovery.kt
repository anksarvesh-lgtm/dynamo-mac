// SPDX-License-Identifier: MIT
package app.maclink.companion.networking

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper

data class DiscoveredMac(
    val name: String,
    val host: String,
    val port: Int
)

class MacDiscovery(context: Context) {
    private val nsdManager = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private val mainHandler = Handler(Looper.getMainLooper())

    private val serviceType = "_maclink-touchpad._tcp."
    private var discoveryListener: NsdManager.DiscoveryListener? = null
    val discoveredDevices = mutableMapOf<String, DiscoveredMac>()

    var onDevicesUpdated: ((List<DiscoveredMac>) -> Unit)? = null

    fun startDiscovery() {
        stopDiscovery()
        discoveredDevices.clear()

        discoveryListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(regType: String) {}

            override fun onServiceFound(service: NsdServiceInfo) {
                if (service.serviceType.contains("maclink-touchpad")) {
                    resolveService(service)
                }
            }

            override fun onServiceLost(service: NsdServiceInfo) {
                discoveredDevices.remove(service.serviceName)
                notifyUpdate()
            }

            override fun onDiscoveryStopped(serviceType: String) {}

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                stopDiscovery()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {
                stopDiscovery()
            }
        }

        try {
            nsdManager?.discoverServices(serviceType, NsdManager.PROTOCOL_DNS_SD, discoveryListener)
        } catch (_: Exception) {}
    }

    private fun resolveService(serviceInfo: NsdServiceInfo) {
        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(serviceInfo: NsdServiceInfo, errorCode: Int) {}

            override fun onServiceResolved(resolved: NsdServiceInfo) {
                val host = resolved.host?.hostAddress ?: return
                val mac = DiscoveredMac(
                    name = resolved.serviceName,
                    host = host,
                    port = resolved.port
                )
                discoveredDevices[mac.name] = mac
                notifyUpdate()
            }
        }

        try {
            nsdManager?.resolveService(serviceInfo, resolveListener)
        } catch (_: Exception) {}
    }

    private fun notifyUpdate() {
        val list = discoveredDevices.values.toList()
        mainHandler.post { onDevicesUpdated?.invoke(list) }
    }

    fun stopDiscovery() {
        discoveryListener?.let {
            try {
                nsdManager?.stopServiceDiscovery(it)
            } catch (_: Exception) {}
        }
        discoveryListener = null
    }
}

