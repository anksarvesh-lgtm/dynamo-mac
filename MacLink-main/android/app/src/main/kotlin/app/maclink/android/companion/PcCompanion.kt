// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android.companion

import android.app.Activity
import android.bluetooth.le.ScanFilter
import android.companion.AssociationInfo
import android.companion.AssociationRequest
import android.companion.BluetoothLeDeviceFilter
import android.companion.CompanionDeviceManager
import android.content.Context
import android.content.IntentSender
import android.os.Build
import java.util.concurrent.Executor

/**
 * Companion Device Manager (CDM) integration for waking MacLink when a
 * paired PC's BLE proximity beacon (`NCTR\x01` + 8-byte device ID prefix) is
 * nearby, and granting OS-level background execution / foreground-service start
 * exemptions while associated.
 */
object PcCompanion {
    const val MANUFACTURER_ID: Int = 0xFFFF

    val BEACON_MAGIC: ByteArray = byteArrayOf(
        'N'.code.toByte(),
        'C'.code.toByte(),
        'T'.code.toByte(),
        'R'.code.toByte(),
        1,
    )

    /**
     * Builds the manufacturer-specific BLE beacon payload:
     * 5-byte `NCTR\x01` magic followed by the first 8 bytes of the decoded
     * hex device ID (13 bytes total), or just the 5-byte magic if [deviceIdHex]
     * does not contain at least 8 valid hex bytes.
     */
    fun buildBeaconPayload(deviceIdHex: String?): ByteArray {
        val clean = deviceIdHex
            ?.filter { it in '0'..'9' || it in 'a'..'f' || it in 'A'..'F' }
            .orEmpty()
        if (clean.length < 16) {
            return BEACON_MAGIC.copyOf()
        }
        val out = ByteArray(BEACON_MAGIC.size + 8)
        BEACON_MAGIC.copyInto(out, 0)
        for (i in 0 until 8) {
            val hi = Character.digit(clean[i * 2], 16)
            val lo = Character.digit(clean[i * 2 + 1], 16)
            if (hi < 0 || lo < 0) return BEACON_MAGIC.copyOf()
            out[BEACON_MAGIC.size + i] = ((hi shl 4) or lo).toByte()
        }
        return out
    }

    /**
     * Builds the scan filter mask matching [buildBeaconPayload]: 13 `0xFF`
     * bytes when a specific 8-byte device ID prefix is present, or 5 `0xFF`
     * bytes to match any MacLink PC beacon.
     */
    fun buildBeaconMask(hasDeviceId: Boolean): ByteArray =
        ByteArray(if (hasDeviceId) 13 else 5) { 0xFF.toByte() }

    fun isAssociated(context: Context): Boolean = runCatching {
        val cdm = context.getSystemService(CompanionDeviceManager::class.java) ?: return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            cdm.myAssociations.isNotEmpty()
        } else {
            @Suppress("DEPRECATION")
            cdm.associations.isNotEmpty()
        }
    }.getOrDefault(false)

    fun startObservingPresence(context: Context) {
        runCatching {
            val cdm = context.getSystemService(CompanionDeviceManager::class.java) ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                for (info in cdm.myAssociations) {
                    runCatching {
                        val addr = info.deviceMacAddress?.toString()
                        if (!addr.isNullOrBlank()) {
                            @Suppress("DEPRECATION")
                            cdm.startObservingDevicePresence(addr)
                        }
                    }
                }
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                @Suppress("DEPRECATION")
                for (addr in cdm.associations) {
                    runCatching {
                        cdm.startObservingDevicePresence(addr)
                    }
                }
            }
        }
    }

    fun requestAssociation(
        activity: Activity,
        pcName: String,
        pcDeviceIdHex: String? = null,
        onResult: (Boolean) -> Unit = {},
        onLauncherFallback: (IntentSender) -> Unit,
    ) {
        runCatching {
            val cdm = activity.getSystemService(CompanionDeviceManager::class.java) ?: run {
                onResult(false)
                return
            }
            val payload = buildBeaconPayload(pcDeviceIdHex)
            val mask = buildBeaconMask(payload.size == 13)
            val scanFilter = ScanFilter.Builder()
                .setManufacturerData(MANUFACTURER_ID, payload, mask)
                .build()
            val leFilter = BluetoothLeDeviceFilter.Builder()
                .setScanFilter(scanFilter)
                .build()
            val requestBuilder = AssociationRequest.Builder()
                .addDeviceFilter(leFilter)
                .setSingleDevice(false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && pcName.isNotBlank()) {
                runCatching { requestBuilder.setDisplayName(pcName) }
            }
            val request = requestBuilder.build()
            val mainExecutor = Executor { runnable -> activity.runOnUiThread(runnable) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                cdm.associate(
                    request,
                    mainExecutor,
                    object : CompanionDeviceManager.Callback() {
                        override fun onAssociationPending(intentSender: IntentSender) {
                            onLauncherFallback(intentSender)
                        }

                        override fun onAssociationCreated(associationInfo: AssociationInfo) {
                            startObservingPresence(activity)
                            onResult(true)
                        }

                        override fun onFailure(error: CharSequence?) {
                            onResult(false)
                        }
                    },
                )
            } else {
                cdm.associate(
                    request,
                    object : CompanionDeviceManager.Callback() {
                        @Deprecated("Deprecated in Java")
                        override fun onDeviceFound(chooserLauncher: IntentSender) {
                            onLauncherFallback(chooserLauncher)
                        }

                        override fun onFailure(error: CharSequence?) {
                            onResult(false)
                        }
                    },
                    null,
                )
            }
        }.onFailure {
            onResult(false)
        }
    }
}
