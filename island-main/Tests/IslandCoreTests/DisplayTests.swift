import CoreGraphics
import Foundation
@testable import IslandCore

private let notched = ScreenDescriptor(
    id: 1, name: "Built-in Retina Display",
    frame: CGRect(x: 0, y: 0, width: 1470, height: 956), visibleFrame: CGRect(x: 0, y: 0, width: 1470, height: 923),
    safeAreaTop: 32, auxiliaryTopLeft: CGRect(x: 0, y: 924, width: 645.5, height: 32),
    auxiliaryTopRight: CGRect(x: 824.5, y: 924, width: 645.5, height: 32), isBuiltIn: true, isMain: false)

private let external = ScreenDescriptor(
    id: 2, name: "LG UltraFine", frame: CGRect(x: 1470, y: 0, width: 2560, height: 1440),
    visibleFrame: CGRect(x: 1470, y: 0, width: 2560, height: 1415), isMain: true)

@MainActor
func registerDisplayTests() {
    let S = "Display"

    test(S, "detects notch from auxiliary areas") {
        let g = DisplayResolver.geometry(for: notched)
        expect(g.hasNotch)
        expectEqual(g.notchRect, CGRect(x: 645.5, y: 924, width: 179, height: 32))
        expectEqual(g.anchor, CGPoint(x: 735, y: 956))
    }

    test(S, "non-notched display uses centred virtual notch") {
        let g = DisplayResolver.geometry(for: external)
        expect(!g.hasNotch)
        expectEqual(g.notchRect.midX, external.frame.midX)
        expectEqual(g.menuBarHeight, 25)
        expectEqual(g.anchor.y, external.frame.maxY)
    }

    test(S, "auto-hidden menu bar falls back to default height") {
        var s = external
        s.visibleFrame = s.frame
        expectEqual(DisplayResolver.geometry(for: s).menuBarHeight, DisplayResolver.fallbackMenuBarHeight)
    }

    test(S, "automatic prefers the notched display even when external is main") {
        expectEqual(DisplayResolver.choose(from: [external, notched], selection: .automatic)?.id, 1)
    }

    test(S, "automatic falls back to main without notch") {
        var other = external
        other.id = 3; other.isMain = false; other.name = "Other"
        expectEqual(DisplayResolver.choose(from: [other, external], selection: .automatic)?.id, 2)
    }

    test(S, "main and specific selection") {
        expectEqual(DisplayResolver.choose(from: [notched, external], selection: .main)?.id, 2)
        expectEqual(DisplayResolver.choose(from: [notched, external], selection: .specific(name: "LG UltraFine"))?.id, 2)
    }

    test(S, "disconnected specific display falls back to automatic") {
        expectEqual(DisplayResolver.choose(from: [notched], selection: .specific(name: "LG UltraFine"))?.id, 1)
    }

    test(S, "no screens resolves to nil") {
        expect(DisplayResolver.choose(from: [], selection: .automatic) == nil)
    }

    test(S, "scaled resolution changes geometry") {
        var s = notched
        s.frame = CGRect(x: 0, y: 0, width: 1710, height: 1112)
        s.auxiliaryTopLeft = CGRect(x: 0, y: 1074, width: 765, height: 38)
        s.auxiliaryTopRight = CGRect(x: 945, y: 1074, width: 765, height: 38)
        s.safeAreaTop = 38
        let g = DisplayResolver.geometry(for: s)
        expectEqual(g.notchSize, CGSize(width: 180, height: 38))
        expectEqual(g.anchor.x, 855)
    }

    test(S, "secondary display to the left has negative origin") {
        var s = external
        s.frame.origin.x = -2560
        s.visibleFrame.origin.x = -2560
        expectEqual(DisplayResolver.geometry(for: s).anchor.x, -1280)
    }
}
