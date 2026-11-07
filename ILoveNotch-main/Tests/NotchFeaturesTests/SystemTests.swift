// SPDX-License-Identifier: MIT
import AppKit
import IOKit.ps
import NotchCore
import Testing

@testable import NotchFeatures

struct VolumeTests {
    @Test func theKeysStepInSixteenthsOrQuarterStepsAndStopAtTheEnds() {
        #expect(VolumeMonitor.stepped(0.5, up: true, fine: false) == 9.0 / 16)
        #expect(VolumeMonitor.stepped(0.5, up: false, fine: true) == 31.0 / 64)
        #expect(VolumeMonitor.stepped(1, up: true, fine: false) == 1)
        #expect(VolumeMonitor.stepped(0.02, up: false, fine: false) == 0)
        #expect(VolumeMonitor.stepped(0.53, up: true, fine: false) == 9.0 / 16, "snaps to the nearest notch first")
    }

    @Test func theNotchShowsTheLevelAsWavesAPercentageAndAMeter() {
        let half = VolumeMonitor.activity(for: VolumeState(level: 0.5, muted: false))
        #expect(half.symbol == "speaker.wave.2.fill" && half.title == "50%" && half.level == 0.5)
        #expect(half.feature == nil, "volume belongs to no tab")
        let muted = VolumeMonitor.activity(for: VolumeState(level: 0.8, muted: true))
        #expect(muted.symbol == "speaker.slash.fill" && muted.title == "Muted" && muted.level == 0)
        #expect(VolumeMonitor.activity(for: VolumeState(level: 1, muted: false)).symbol == "speaker.wave.3.fill")
    }

    @Test func onlyTheVolumeKeysAreRecognized() throws {
        let up = try #require(VolumeKeyTap.volumeKey(data1: 0 << 16 | 0xA00))
        #expect(up.key == .up && up.isDown)
        let released = try #require(VolumeKeyTap.volumeKey(data1: 1 << 16 | 0xB00))
        #expect(released.key == .down && !released.isDown)
        #expect(VolumeKeyTap.volumeKey(data1: 7 << 16 | 0xA01)?.key == .mute, "a repeat still counts")
        #expect(VolumeKeyTap.volumeKey(data1: 2 << 16 | 0xA00) == nil, "brightness isn't ours")
        #expect(VolumeKeyTap.volumeKey(data1: 16 << 16 | 0xA00) == nil, "neither is play/pause")
    }
}

struct BatteryTests {
    private func battery(_ percent: Int, onAC: Bool = false, charged: Bool = false) -> BatteryState {
        BatteryState(percent: percent, onAC: onAC, charged: charged)
    }

    @Test func aPowerSourceDescriptionIsReadAsTheInternalBattery() throws {
        let description: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType, kIOPSCurrentCapacityKey: 54, kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue, kIOPSIsChargedKey: false,
        ]
        #expect(BatteryState(description) == battery(54, onAC: true))
        #expect(BatteryState([kIOPSTypeKey: "UPS", kIOPSCurrentCapacityKey: 1, kIOPSMaxCapacityKey: 1]) == nil)
    }

    @Test func pluggingInUnpluggingRunningLowAndFillingUpAreAnnounced() throws {
        let plugged = try #require(BatteryMonitor.activity(from: battery(54), to: battery(54, onAC: true)))
        #expect(plugged.symbol == "battery.100percent.bolt" && plugged.title == "54%" && plugged.level == 0.54)
        #expect(BatteryMonitor.activity(from: battery(54, onAC: true), to: battery(54))?.symbol == "battery.50percent")
        #expect(BatteryMonitor.activity(from: battery(21), to: battery(20))?.symbol == "battery.25percent")
        #expect(BatteryMonitor.activity(from: battery(11), to: battery(10))?.symbol == "battery.0percent")
        #expect(
            BatteryMonitor.activity(from: battery(99, onAC: true), to: battery(100, onAC: true, charged: true))?.title
                == "Full")
    }

    @Test func ordinaryChangesAreNot() {
        #expect(BatteryMonitor.activity(from: battery(60), to: battery(59)) == nil)
        #expect(BatteryMonitor.activity(from: battery(20), to: battery(19)) == nil, "20% was already announced")
        #expect(BatteryMonitor.activity(from: battery(15, onAC: true), to: battery(16, onAC: true)) == nil)
    }
}

struct SystemActivitySymbolTests {
    @Test func accessoriesAreShownByKind() {
        #expect(AccessoryMonitor.activity(product: "Magic Mouse", percent: 80).symbol == "magicmouse.fill")
        let keyboard = AccessoryMonitor.activity(product: "Magic Keyboard with Touch ID", percent: 5)
        #expect(keyboard.symbol == "keyboard.fill")
        #expect(AccessoryMonitor.activity(product: "Magic Trackpad", percent: 150).title == "100%")
    }

    /// A misspelled symbol draws nothing, so every symbol a system activity can show must exist.
    @Test func everySymbolExists() {
        let volumes = [0, 0.2, 0.5, 0.9].map { VolumeMonitor.activity(for: VolumeState(level: $0, muted: false)) }
        let batteries = stride(from: 0, through: 100, by: 5).map { BatteryMonitor.symbol(for: $0) }
        let accessories = ["Magic Mouse", "Magic Trackpad", "Magic Keyboard", "Headphones"].map {
            AccessoryMonitor.activity(product: $0, percent: 50).symbol
        }
        let symbols =
            volumes.map(\.symbol) + batteries + accessories
            + ["speaker.slash.fill", "battery.100percent.bolt", FeatureID.mirror.symbol, "video.slash"]
        for symbol in Set(symbols) {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "\(symbol)")
        }
    }
}

@MainActor
struct HotKeyTests {
    private func press(_ characters: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)
    }

    private func shortcut(_ characters: String, keyCode: UInt16, _ flags: NSEvent.ModifierFlags) throws
        -> KeyShortcut?
    {
        KeyShortcut(event: try #require(press(characters, keyCode: keyCode, flags)))
    }

    @Test func aKeyPressWithCommandOptionOrControlBecomesAShortcut() throws {
        #expect(try shortcut("o", keyCode: 31, [.control, .option]) == NotchPreferences.defaultNotchShortcut)
        #expect(try shortcut("n", keyCode: 45, [.control, .option]) == .newNote)
        #expect(try shortcut(" ", keyCode: 49, [.command, .shift])?.display == "⇧⌘Space")
        let f5 = String(UnicodeScalar(UInt32(NSF5FunctionKey))!)
        #expect(try shortcut(f5, keyCode: 96, [.command])?.display == "⌘F5")
    }

    @Test func plainTypingIsNotAShortcut() throws {
        #expect(try shortcut("a", keyCode: 0, []) == nil)
        #expect(try shortcut("A", keyCode: 0, [.shift]) == nil, "Shift alone types")
    }
}

struct ShowInNotchTests {
    @Test func aLinkShowsItsMessageForAWhile() throws {
        let url = try #require(URL(string: "ilovenotch://show?title=Build%20done&symbol=hammer.fill&seconds=6"))
        let message = try #require(ShowInNotch.activity(from: url))
        #expect(message.title == "Build done" && message.symbol == "hammer.fill" && message.duration == .seconds(6))
        #expect(message.feature == nil, "it belongs to no tab, so it shows whatever tabs are on")
    }

    @Test func textFromOutsideIsCleanedUpAndKeptShort() throws {
        let messy = try #require(
            ShowInNotch.activity(
                title: "  Deploy\n\tfinished \u{202E}now\u{0} ", symbol: "no.such.symbol", seconds: 999))
        #expect(messy.title == "Deploy finished now", "line breaks, controls, and bidi overrides are gone")
        #expect(messy.symbol == ShowInNotch.defaultSymbol && messy.duration == .seconds(30))
        let long = try #require(
            ShowInNotch.activity(title: String(repeating: "a", count: 500), symbol: nil, seconds: nil))
        #expect(long.title.count == 80 && long.duration == .seconds(4))
        let family = ShowInNotch.activity(title: "👨‍👩‍👧 home", symbol: nil, seconds: .nan)
        #expect(family?.title == "👨‍👩‍👧 home" && family?.duration == .seconds(4), "emoji stay whole; NaN isn't a time")
        #expect(ShowInNotch.activity(title: " \n ", symbol: nil, seconds: nil) == nil, "nothing to show")
    }

    @Test(arguments: [
        "ilovenotch://open?tab=media", "https://show?title=Hi", "ilovenotch://show", "ilovenotch://show?title=",
    ])
    func otherLinksAreIgnored(link: String) throws {
        #expect(ShowInNotch.activity(from: try #require(URL(string: link))) == nil)
    }
}

@MainActor
struct MirrorTests {
    @Test func theCameraRunsOnlyWhileTheMirrorCanBeSeen() {
        #expect(MirrorFeature.runsCamera(phase: .foreground, access: .granted))
        #expect(!MirrorFeature.runsCamera(phase: .background, access: .granted))
        #expect(!MirrorFeature.runsCamera(phase: .foreground, access: .notDetermined))
        #expect(!MirrorFeature.runsCamera(phase: .foreground, access: .denied))
    }
}
