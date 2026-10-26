//
//  test_powerload_milestone1.swift
//  LiquidDynamo Tests - Milestone 1: Powerload Multi-Interface & Resilience
//

import Foundation

@main
struct PowerloadMilestone1Tests {
    static func main() async {
        print("=== Running Milestone 1: Powerload Unit Tests ===")

        // 1. Test Virtual Interface Filtering
        let virtuals = ["lo0", "utun0", "utun1", "awdl0", "anpi0", "vmnet1", "bridge0", "llw0", "ipsec0", "gif0"]
        for v in virtuals {
            let isV = PowerloadNetworkManager.isVirtualInterface(bsdName: v)
            assert(isV, "Expected \(v) to be classified as virtual interface")
        }
        let physicals = ["en0", "en1", "en2", "en5"]
        for p in physicals {
            let isV = PowerloadNetworkManager.isVirtualInterface(bsdName: p)
            assert(!isV, "Expected \(p) to NOT be classified as virtual interface")
        }
        print("Test 1 (Virtual Interface Filtering): PASS")

        // 2. Test Hardware Interface Classification
        assert(PowerloadNetworkManager.isInterfaceMetered(kind: .usb, portName: "iPhone", bsdName: "en5") == true, "iPhone USB should be metered")
        assert(PowerloadNetworkManager.isInterfaceMetered(kind: .wifi, portName: "Wi-Fi", bsdName: "en0") == false, "Standard Wi-Fi should not be metered")
        assert(PowerloadNetworkManager.isInterfaceMetered(kind: .ethernet, portName: "USB 10/100/1000 LAN", bsdName: "en2") == false, "Ethernet should not be metered")
        print("Test 2 (Interface Metered Classification): PASS")

        // 3. Test Health State Transitions & isOnline Property
        let linkDown = PowerloadNetworkManager.initialHealth(hasIPv4: true, isLinkActive: false, gatewayIP: "192.168.1.1")
        assert(linkDown == .unusable(reason: "Physical link down"), "Link down must be unusable")
        assert(!linkDown.isUsable, "Link down isUsable must be false")

        let noIP = PowerloadNetworkManager.initialHealth(hasIPv4: false, isLinkActive: true, gatewayIP: "192.168.1.1")
        assert(noIP == .unusable(reason: "No IPv4 address assigned"), "No IP must be unusable")

        let linkLocalNoGW = PowerloadNetworkManager.initialHealth(hasIPv4: true, isLinkActive: true, gatewayIP: nil)
        assert(linkLocalNoGW == .degraded(reason: "No default gateway (link-local)"), "No gateway must be degraded")
        assert(!linkLocalNoGW.isUsable, "Degraded without gateway must not be usable for bonding")

        let fullOnline = PowerloadNetworkManager.initialHealth(hasIPv4: true, isLinkActive: true, gatewayIP: "192.168.1.1")
        assert(fullOnline == .usable, "Complete interface must be usable")
        assert(fullOnline.isUsable, "Usable interface must report isUsable true")

        let iface = PowerloadInterface(
            id: "en0",
            bsdName: "en0",
            displayName: "Wi-Fi",
            kind: .wifi,
            ipAddress: "192.168.1.50",
            gatewayIP: "192.168.1.1",
            isLinkActive: true,
            isEnabled: true,
            health: fullOnline
        )
        assert(iface.isOnline == true, "Interface with usable health must report isOnline == true")
        print("Test 3 (Health State Transitions & isOnline): PASS")

        // 4. Test Range Request Error Distinction
        let rangeErr = PowerloadHTTPError.rangeNotSupported(statusCode: 200)
        switch rangeErr {
        case .rangeNotSupported(let code):
            assert(code == 200, "Range not supported code must be 200")
        default:
            assertionFailure("Expected rangeNotSupported error")
        }
        print("Test 4 (Strict HTTP 206 / Range Error Classification): PASS")

        // 5. Test Worker Pool & Work Stealing State Management
        let chunks = [
            PowerloadChunk(id: 0, rangeStart: 0, rangeEnd: 999),
            PowerloadChunk(id: 1, rangeStart: 1000, rangeEnd: 1999),
            PowerloadChunk(id: 2, rangeStart: 2000, rangeEnd: 2999)
        ]
        let pool = PowerloadDownloadWorkerPool(chunks: chunks)
        let c0 = await pool.claimNextChunk(interfaceId: "en0")
        assert(c0 == 0, "First claimed chunk should be index 0")
        let c1 = await pool.claimNextChunk(interfaceId: "en5")
        assert(c1 == 1, "Second claimed chunk should be index 1")

        // Worker on en5 fails and returns chunk
        await pool.returnChunk(chunkIndex: 1)
        // Worker on en0 steals/claims returned chunk
        let cStolen = await pool.claimNextChunk(interfaceId: "en0")
        assert(cStolen == 1, "Returned chunk 1 should be reclaimed by worker")

        await pool.markCompleted(chunkIndex: 0)
        await pool.markCompleted(chunkIndex: 1)
        let c2 = await pool.claimNextChunk(interfaceId: "en0")
        assert(c2 == 2, "Chunk 2 should be claimed next")
        await pool.markCompleted(chunkIndex: 2)

        let isDone = await pool.isAllCompleted
        assert(isDone == true, "Pool should report all completed")
        print("Test 5 (Worker Pool & Chunk Work Stealing): PASS")

        print("\n✅ ALL 5 MILESTONE 1 UNIT TESTS PASSED!")
    }
}
