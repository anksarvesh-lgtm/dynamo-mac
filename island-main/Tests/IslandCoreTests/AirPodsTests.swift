import Foundation
@testable import IslandCore

@MainActor
func registerAirPodsTests() {
    let S = "AirPods"

    test(S, "state machine runs the full sequence in order") {
        var m = AirPodsConnectionStateMachine()
        let steps: [(AirPodsConnectionEvent, AirPodsConnectionPhase)] = [
            (.deviceConnected, .detecting), (.detailsReady, .expanding), (.islandOpened, .revealingDevice),
            (.revealFinished, .connected), (.holdElapsed, .dismissing), (.islandClosed, .idle),
        ]
        for (e, want) in steps { expectEqual(m.handle(e), want) }
    }

    test(S, "state machine never skips or repeats a phase") {
        var m = AirPodsConnectionStateMachine()
        expectEqual(m.handle(.islandOpened), .idle)           // out of order: ignored
        m.handle(.deviceConnected)
        expectEqual(m.handle(.deviceConnected), .detecting)   // duplicate connect: ignored
        expectEqual(m.handle(.revealFinished), .detecting)    // can't reveal before the Island opens
        m.handle(.detailsReady)
        expectEqual(m.handle(.islandClosed), .expanding)
    }

    test(S, "disconnect mid-sequence dismisses; while detecting it returns to idle") {
        var a = AirPodsConnectionStateMachine()
        a.handle(.deviceConnected)
        expectEqual(a.handle(.deviceDisconnected), .idle)
        var b = AirPodsConnectionStateMachine()
        b.handle(.deviceConnected); b.handle(.detailsReady); b.handle(.islandOpened)
        expectEqual(b.handle(.deviceDisconnected), .dismissing)
        expectEqual(b.handle(.islandClosed), .idle)
    }

    test(S, "user dismiss during reveal goes straight to dismissing") {
        var m = AirPodsConnectionStateMachine()
        m.handle(.deviceConnected); m.handle(.detailsReady); m.handle(.islandOpened)
        expectEqual(m.handle(.holdElapsed), .dismissing)
        expect(!m.phase.isPresenting)
    }

    test(S, "parses system_profiler output: connected AirPods with battery") {
        let json = """
        {"SPBluetoothDataType":[{"device_connected":[{"Poshak’s AirPods Pro":{"device_address":"AA:BB","device_productID":"0x2024",
          "device_vendorID":"0x004C","device_batteryLevelLeft":"82%","device_batteryLevelRight":"79%","device_batteryLevelCase":"61%"}}],
          "device_not_connected":[{"WH-CH720N":{"device_productID":"0x0EAF","device_vendorID":"0x054C"}}]}]}
        """
        let r = SystemProfilerBluetoothParser.parse(Data(json.utf8))
        expectEqual(r.count, 2)
        let pods = r.first { $0.connected }
        expectEqual(pods?.productID, 0x2024)
        expectEqual(pods?.vendorID, 0x004C)
        expectEqual(pods?.battery, AirPodsBattery(left: 82, right: 79, caseLevel: 61))
        expect(r.first { !$0.connected }?.battery.isEmpty == true)
    }

    test(S, "parser tolerates garbage and missing sections") {
        expect(SystemProfilerBluetoothParser.parse(Data("nope".utf8)).isEmpty)
        expect(SystemProfilerBluetoothParser.parse(Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)).isEmpty)
    }

    test(S, "name matching handles apostrophe and spacing variants") {
        let reports = [BluetoothDeviceReport(name: "Poshak ’s AirPods Pro", connected: false),
                       BluetoothDeviceReport(name: "Poshak’s AirPods Pro", productID: 0x2024, connected: true)]
        expectEqual(SystemProfilerBluetoothParser.match("Poshak's AirPods Pro", in: reports)?.productID, 0x2024)
        expect(SystemProfilerBluetoothParser.match("Unrelated Speaker", in: reports) == nil)
    }

    test(S, "model resolution: product ID first, then name") {
        expectEqual(AirPodsModel.resolve(productID: 0x2024, name: "x"), .airPodsPro2USBC)
        expectEqual(AirPodsModel.resolve(productID: 0x200A, name: "x"), .airPodsMax)
        expectEqual(AirPodsModel.resolve(productID: nil, name: "My AirPods Pro"), .airPodsPro2)
        expectEqual(AirPodsModel.resolve(productID: nil, name: "Kitchen AirPods Max"), .airPodsMax)
        expect(AirPodsModel.resolve(productID: nil, name: "WH-1000XM5") == nil)
        expectEqual(AirPodsModel.resolve(productID: 0x2024, name: "x")?.displayName, "AirPods Pro")
        expectEqual(AirPodsModel.deviceModelCode(productID: 0x2024), "Device1,8228")
    }

    test(S, "battery headline is the lower bud; clamped; empty when unreported") {
        expectEqual(AirPodsBattery(left: 82, right: 79, caseLevel: 61).headline, 79)
        expectEqual(AirPodsBattery(single: 64).headline, 64)
        expectEqual(AirPodsBattery(left: 150).left, 100)
        expect(AirPodsBattery().isEmpty && AirPodsBattery().headline == nil)
    }
}
