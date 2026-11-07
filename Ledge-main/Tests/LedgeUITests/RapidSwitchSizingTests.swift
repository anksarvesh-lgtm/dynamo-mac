import AppKit
import CoreGraphics
import Foundation
import LedgeCore
import SwiftUI
import Testing

@testable import LedgeUI

/// Card heights while the cards are actually changing hands.
///
/// The simple cards measure themselves, and a card on its way out goes on
/// reporting for a frame or two after its replacement has arrived. Sizing-time
/// checks cannot see that: by the time the wrong value is spent, the right one
/// has already been overwritten. So this hosts the real overlay, switches cards
/// at the speed a hand does, and asks what the shell ended up believing.
@Suite("Sizing through rapid card switches", .serialized)
@MainActor
struct RapidSwitchSizingTests {

    private static let geometry = NotchGeometry(
        screenSize: CGSize(width: 1470, height: 956),
        notchSize: CGSize(width: 179, height: 32),
        notchCenterX: 735,
        isHardwareNotch: true
    )

    private func activity(_ name: String) -> Activity {
        let kind: ActivityKind
        let payload: ActivityPayload
        switch name {
        case "focus":
            kind = .focus
            payload = .focus(FocusPayload(name: "Deep Work", symbolName: "moon.fill"))
        case "shelf":
            kind = .shelf
            payload = .shelf(ShelfPayload(items: (1...3).map {
                ShelfItem(path: "/tmp/switch-\($0)", name: "Example \($0)")
            }))
        default:
            kind = .device
            payload = .device(DevicePayload(
                name: "Sample Earbuds",
                batteryLevels: ["Left": 0.9, "Right": 0.8, "Case": 0.7]
            ))
        }
        return Activity(id: ActivityID(kind: kind, source: name), createdAt: 0, payload: payload)
    }

    /// The overlay, in a window, laid out for real. Borderless and ordered
    /// front regardless: the geometry callbacks these tests are about only run
    /// for a view that is actually in a window.
    private func host(_ presentation: NotchPresentation) -> NSWindow {
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let size = NotchLayout.panelSize(for: Self.geometry)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        let view = NSHostingView(rootView: NotchOverlayView(
            geometry: Self.geometry,
            preferences: Preferences(store: MemoryPreferenceStore()),
            presentation: presentation
        ).frame(width: size.width, height: size.height))
        view.sizingOptions = []
        window.contentView = view
        window.setContentSize(size)
        window.orderFrontRegardless()
        return window
    }

    /// Lets SwiftUI lay out and report. A cooperative sleep is not enough —
    /// these callbacks arrive on the main run loop.
    private func settle(_ seconds: TimeInterval = 0.25) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func height(_ presentation: NotchPresentation) -> CGFloat {
        presentation.cardSize(
            preferences: Preferences(store: MemoryPreferenceStore()),
            geometry: Self.geometry,
            phase: .expanded
        ).height
    }

    /// The failure this exists for: the Shelf had measured itself correctly,
    /// the outgoing Device card reported a frame later, and the Shelf spent the
    /// rest of its time on screen at the fallback height with its tiles
    /// clipped.
    @Test("A late report from the card that just left is ignored")
    func lateReportFromOutgoingCard() {
        let presentation = NotchPresentation()
        presentation.phase = .expanded
        presentation.count = 3
        presentation.selected = activity("focus")
        let window = host(presentation)
        defer { window.orderOut(nil) }
        settle()

        // What the Shelf is worth when nothing is racing it.
        presentation.selected = activity("shelf")
        settle()
        let settledShelf = height(presentation)
        #expect(presentation.measuredCards.contains(where: { $0.kind == .shelf }),
            "the Shelf measured itself")

        // Now the same switch at speed, with a device card in between.
        for name in ["device", "shelf", "device", "shelf"] {
            presentation.selected = activity(name)
            settle(0.06)
        }
        settle(0.4)

        #expect(presentation.cardContentHeight(for: presentation.selected?.id) > 0,
            "the card on show is sized by a measurement of its own")
        #expect(abs(height(presentation) - settledShelf) < 0.5,
            "the Shelf is the height it measured, not the fallback")
    }

    @Test("Every card in a fast sequence ends at its own settled height")
    func eachCardKeepsItsOwnHeight() {
        let presentation = NotchPresentation()
        presentation.phase = .expanded
        presentation.count = 3
        presentation.selected = activity("focus")
        let window = host(presentation)
        defer { window.orderOut(nil) }
        settle()

        var alone: [String: CGFloat] = [:]
        for name in ["focus", "shelf", "device"] {
            presentation.selected = activity(name)
            settle()
            alone[name] = height(presentation)
        }

        for name in ["shelf", "device", "focus", "device", "shelf", "focus"] {
            presentation.selected = activity(name)
            settle(0.05)
        }
        for name in ["shelf", "device", "focus"] {
            presentation.selected = activity(name)
            settle(0.4)
            #expect(abs(height(presentation) - (alone[name] ?? 0)) < 0.5,
                "\(name) after fast switching is not the height it settles at alone")
        }
    }
}
