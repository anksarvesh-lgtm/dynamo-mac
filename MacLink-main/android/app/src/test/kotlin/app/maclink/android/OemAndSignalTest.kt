// SPDX-License-Identifier: GPL-3.0-or-later
package app.maclink.android

import android.telephony.TelephonyDisplayInfo
import android.telephony.TelephonyManager
import app.maclink.android.core.BackgroundAccess
import app.maclink.android.core.OemBrand
import app.maclink.android.core.SignalSnapshot
import app.maclink.android.core.modelName
import app.maclink.android.core.networkTypeLabel
import app.maclink.android.core.rssiToWifiBars
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class OemAndSignalTest {
    @Test
    fun modelNameAddsTheMakerOnlyOnce() {
        assertEquals("Samsung SM-X100", modelName("samsung", "SM-X100"))
        assertEquals("Google Pixel 9", modelName("Google", "Pixel 9"))
        assertEquals("Google Pixel 9", modelName("Google", "Google Pixel 9"))
        assertEquals("ONEPLUS 12", modelName("OnePlus", "ONEPLUS 12"))
        assertEquals("Pixel 9", modelName("", "Pixel 9"))
    }

    @Test
    fun detectOemRecognizesAllSupportedBrandsAndFallback() {
        assertEquals(OemBrand.SAMSUNG, BackgroundAccess.detectOem("Samsung", "samsung"))
        assertEquals(OemBrand.SAMSUNG, BackgroundAccess.detectOem("SAMSUNG", "Galaxy"))

        assertEquals(OemBrand.XIAOMI, BackgroundAccess.detectOem("Xiaomi", "Xiaomi"))
        assertEquals(OemBrand.XIAOMI, BackgroundAccess.detectOem("Xiaomi", "Redmi"))
        assertEquals(OemBrand.XIAOMI, BackgroundAccess.detectOem("Xiaomi", "POCO"))
        assertEquals(OemBrand.XIAOMI, BackgroundAccess.detectOem("POCO", "poco"))

        assertEquals(OemBrand.ONEPLUS, BackgroundAccess.detectOem("OnePlus", "OnePlus"))

        assertEquals(OemBrand.OPPO_REALME, BackgroundAccess.detectOem("OPPO", "OPPO"))
        assertEquals(OemBrand.OPPO_REALME, BackgroundAccess.detectOem("realme", "realme"))

        assertEquals(OemBrand.VIVO, BackgroundAccess.detectOem("vivo", "vivo"))
        assertEquals(OemBrand.VIVO, BackgroundAccess.detectOem("vivo", "iQOO"))

        assertEquals(OemBrand.HUAWEI, BackgroundAccess.detectOem("HUAWEI", "HUAWEI"))
        assertEquals(OemBrand.HUAWEI, BackgroundAccess.detectOem("HONOR", "HONOR"))

        assertEquals(OemBrand.PIXEL, BackgroundAccess.detectOem("Google", "google"))
        assertEquals(OemBrand.PIXEL, BackgroundAccess.detectOem("Google", "Pixel"))

        assertEquals(OemBrand.OTHER, BackgroundAccess.detectOem("Motorola", "motorola"))
        assertEquals(OemBrand.OTHER, BackgroundAccess.detectOem("Sony", "Sony"))
        assertEquals(OemBrand.OTHER, BackgroundAccess.detectOem("", ""))
    }

    @Test
    fun oemGuideResIdMapsOnlyCurrentManufacturer() {
        assertEquals(R.string.battery_guide_samsung, BackgroundAccess.oemGuideResId(OemBrand.SAMSUNG))
        assertEquals(R.string.battery_guide_xiaomi, BackgroundAccess.oemGuideResId(OemBrand.XIAOMI))
        assertEquals(R.string.battery_guide_oneplus, BackgroundAccess.oemGuideResId(OemBrand.ONEPLUS))
        assertEquals(R.string.battery_guide_oppo_realme, BackgroundAccess.oemGuideResId(OemBrand.OPPO_REALME))
        assertEquals(R.string.battery_guide_vivo, BackgroundAccess.oemGuideResId(OemBrand.VIVO))
        assertEquals(R.string.battery_guide_huawei, BackgroundAccess.oemGuideResId(OemBrand.HUAWEI))
        assertEquals(R.string.battery_guide_pixel, BackgroundAccess.oemGuideResId(OemBrand.PIXEL))
        assertNull(BackgroundAccess.oemGuideResId(OemBrand.OTHER))
    }

    @Test
    fun rssiToWifiBarsMapsRssiBucketsAndRejectsInvalidValues() {
        assertEquals(4.toUByte(), rssiToWifiBars(-50))
        assertEquals(3.toUByte(), rssiToWifiBars(-60))
        assertEquals(2.toUByte(), rssiToWifiBars(-72))
        assertEquals(1.toUByte(), rssiToWifiBars(-84))
        assertEquals(0.toUByte(), rssiToWifiBars(-95))
        assertNull(rssiToWifiBars(-127))
        assertNull(rssiToWifiBars(-130))
        assertNull(rssiToWifiBars(0))
    }

    @Test
    fun networkTypeLabelMapsGenerationsAndOverrides() {
        assertEquals("5G", networkTypeLabel(TelephonyManager.NETWORK_TYPE_NR))
        assertEquals("LTE", networkTypeLabel(TelephonyManager.NETWORK_TYPE_LTE))
        assertEquals("LTE", networkTypeLabel(TelephonyManager.NETWORK_TYPE_IWLAN))
        assertEquals("3G", networkTypeLabel(TelephonyManager.NETWORK_TYPE_HSPAP))
        assertEquals("3G", networkTypeLabel(TelephonyManager.NETWORK_TYPE_HSPA))
        assertEquals("3G", networkTypeLabel(TelephonyManager.NETWORK_TYPE_UMTS))
        assertEquals("2G", networkTypeLabel(TelephonyManager.NETWORK_TYPE_EDGE))
        assertEquals("2G", networkTypeLabel(TelephonyManager.NETWORK_TYPE_GPRS))
        assertNull(networkTypeLabel(TelephonyManager.NETWORK_TYPE_UNKNOWN))

        // 5G NSA and 5G+ overrides on an LTE anchor report 5G
        assertEquals(
            "5G",
            networkTypeLabel(
                TelephonyManager.NETWORK_TYPE_LTE,
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_NSA,
            ),
        )
        assertEquals(
            "5G",
            networkTypeLabel(
                TelephonyManager.NETWORK_TYPE_LTE,
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_NR_ADVANCED,
            ),
        )
        assertEquals(
            "LTE",
            networkTypeLabel(
                TelephonyManager.NETWORK_TYPE_LTE,
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_CA,
            ),
        )
        assertEquals(
            "LTE",
            networkTypeLabel(
                TelephonyManager.NETWORK_TYPE_LTE,
                TelephonyDisplayInfo.OVERRIDE_NETWORK_TYPE_LTE_ADVANCED_PRO,
            ),
        )

        val snapshot = SignalSnapshot(cellBars = 4u, cellType = "5G", wifiBars = 3u)
        assertNotNull(snapshot)
        assertEquals(4.toUByte(), snapshot.cellBars)
        assertEquals("5G", snapshot.cellType)
        assertEquals(3.toUByte(), snapshot.wifiBars)
    }
}
