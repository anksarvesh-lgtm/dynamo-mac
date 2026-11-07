import Foundation
import Testing

@testable import LedgeCore

@Suite("Notch geometry and layout")
struct NotchGeometryTests {

    private let air = NotchGeometry(
        screenSize: CGSize(width: 1470, height: 956),
        notchSize: CGSize(width: 180, height: 32),
        notchCenterX: 735,
        isHardwareNotch: true
    )

    @Test("Closed layout matches the physical cutout exactly")
    func closedMatchesCutout() {
        let layout = NotchLayout.closed(air, bottomRadius: 14, gutterRadius: 10)
        #expect(layout.bodySize == air.notchSize)
    }

    @Test("Bounding size accounts for both gutters")
    func boundingIncludesGutters() {
        let layout = NotchLayout.closed(air, bottomRadius: 14, gutterRadius: 10)
        #expect(layout.boundingSize.width == air.notchSize.width + 20)
        #expect(layout.boundingSize.height == air.notchSize.height)
    }

    @Test("Expanded layout never runs off the screen edge")
    func expandedClampsToScreen() {
        let layout = NotchLayout.expanded(
            air,
            size: CGSize(width: 5000, height: 200),
            bottomRadius: 14,
            gutterRadius: 10
        )
        #expect(layout.boundingSize.width <= air.screenSize.width)
    }

    @Test("Expanded layout never shrinks below the cutout")
    func expandedNeverSmallerThanCutout() {
        let layout = NotchLayout.expanded(
            air,
            size: CGSize(width: 10, height: 5),
            bottomRadius: 14,
            gutterRadius: 10
        )
        #expect(layout.bodySize.width >= air.notchSize.width)
        #expect(layout.bodySize.height >= air.notchSize.height)
    }

    @Test("A display with no cutout gets a simulated pill centred on screen")
    func simulatedFallback() {
        let geometry = NotchGeometry.simulated(screenSize: CGSize(width: 2560, height: 1440))
        #expect(geometry.isHardwareNotch == false)
        #expect(geometry.notchCenterX == 1280)
        #expect(geometry.notchSize.height > 0)
    }
}

/// NaN radii from a corrupted defaults database must degrade to the cutout,
/// never poison the layout — min/max keep their first argument when a
/// comparison fails, so nothing downstream can repair it.
@Suite("Layout NaN hardening")
struct LayoutNaNTests {

    private let geometry = NotchGeometry(
        screenSize: CGSize(width: 1470, height: 956),
        notchSize: CGSize(width: 180, height: 32),
        notchCenterX: 735,
        isHardwareNotch: true
    )

    @Test("NaN radii yield a finite, non-degenerate layout in every phase")
    func nanRadiiDegrade() {
        for phase in [NotchPhase.idle, .peek, .hud, .companion, .hover, .expanded] {
            let layout = NotchLayout.layout(
                for: phase,
                geometry: geometry,
                expandedSize: CGSize(width: 420, height: 180),
                bottomRadius: .nan,
                closedBottomRadius: .nan,
                gutterRadius: .nan
            )
            #expect(layout.bodySize.width.isFinite && layout.bodySize.width >= geometry.notchSize.width)
            #expect(layout.bodySize.height.isFinite && layout.bodySize.height >= geometry.notchSize.height)
            #expect(layout.bottomRadius.isFinite && layout.bottomRadius >= 0)
            #expect(layout.gutterRadius.isFinite && layout.gutterRadius >= 0)
        }
    }
}


/// The adjustable ear width.
///
/// The clamp is tested through `sanitizedEarWidth` and the discipline through
/// an explicit `earWidth:`, so neither writes to the shared static. One test
/// still does — `setEarWidth` has to be exercised somewhere — and it is the
/// only writer left in the suite, restoring the default before it returns.
/// This matters because tests run in parallel: while the old version held the
/// static at 90, a width test in another suite read it and saw a 375pt card
/// where it expected 283.
@Suite("Ear width", .serialized)
struct EarWidthTests {

    @Test("Clamped, capped, and NaN-proof")
    func clampRule() {
        #expect(NotchLayout.sanitizedEarWidth(70) == 70)
        #expect(NotchLayout.sanitizedEarWidth(10) == 36, "floored")
        #expect(NotchLayout.sanitizedEarWidth(500) == 90, "capped")
        #expect(NotchLayout.sanitizedEarWidth(.nan) == NotchLayout.defaultEarWidth, "NaN degrades")
    }

    /// The one writer. Both compact phases share a width, so setting it must
    /// reach both statics rather than the one the caller happened to mean.
    @Test("Applying a width reaches both compact phases")
    func appliesToBothPhases() {
        defer { NotchLayout.setEarWidth(NotchLayout.defaultEarWidth) }
        NotchLayout.setEarWidth(70)
        #expect(NotchLayout.hudEarWidth == 70)
        #expect(NotchLayout.peekEarWidth == 70)
        NotchLayout.setEarWidth(500)
        #expect(NotchLayout.hudEarWidth == 90, "sanitised on the way in")
    }

    @Test("The width discipline follows the ear width")
    func disciplineFollows() {
        let geometry = NotchGeometry(
            screenSize: CGSize(width: 1470, height: 956),
            notchSize: CGSize(width: 180, height: 32),
            notchCenterX: 735,
            isHardwareNotch: true
        )
        let size = NotchLayout.cardSize(
            kind: .nowPlaying, phase: .hover,
            base: CGSize(width: 420, height: 160),
            geometry: geometry, routePickerRows: 0, hasSelection: true,
            earWidth: 60
        )
        #expect(abs(size.width - (300 + NotchLayout.openCardGrowth)) < 0.001)
    }
}

@Suite("Layout boundary regressions")
struct LayoutBoundaryTests {
    private func geometry(scale: CGFloat, height: CGFloat = 956) -> NotchGeometry {
        NotchGeometry(
            screenSize: CGSize(width: 1470, height: height),
            notchSize: CGSize(width: 180, height: 38),
            notchCenterX: 735, isHardwareNotch: true, displayScale: scale
        )
    }

    /// The drafted width is in reference points, and this Mac's scale applies
    /// to it exactly as it applies to a card: the island and the card it opens
    /// into are one width, so the ear cannot be the one thing that ignores the
    /// panel.
    @Test("Draft compact ears retain their usable width after gutter insets", arguments: [CGFloat(36), 53, 90])
    func compactPreviewWidth(ear: CGFloat) {
        let scale: CGFloat = 1.2
        let geometry = geometry(scale: scale)
        for gutter: CGFloat in [0, 10, 30] {
            let layout = NotchLayout.peek(
                geometry, bottomRadius: 14, gutterRadius: gutter, earWidth: ear
            )
            let usableEar = (layout.boundingSize.width - geometry.notchSize.width) / 2 - gutter
            #expect(abs(usableEar - ear * scale) < 0.001)
            #expect(layout.boundingSize.height == geometry.notchSize.height + 0.5)
        }
    }

    @Test("Route picker reserves three full rows at every display scale", arguments: [CGFloat(1), 1.1, 1.2])
    func routeViewport(scale: CGFloat) {
        let geometry = geometry(scale: scale)
        for rows in [1, 3, 8] {
            let card = NotchLayout.cardSize(
                kind: .nowPlaying, phase: .expanded, base: CGSize(width: 420, height: 440),
                geometry: geometry, routePickerRows: rows, hasSelection: true
            )
            // Convert back to the coordinate space used by expandedContent,
            // then remove its notch inset and the menu's header and padding.
            let viewport = card.height / scale - 38 - 30 - 44 - 12
            let visibleRows = min(rows, 3)
            let needed = CGFloat(visibleRows * 42 + (visibleRows - 1) * 8)
            #expect(abs(viewport - needed) < 0.001)
        }
    }

    @Test("Panel contains maximum-height cards with animation headroom", arguments: [CGFloat(1), 1.1, 1.2])
    func panelCapacity(scale: CGFloat) {
        let geometry = geometry(scale: scale)
        let panel = NotchLayout.panelSize(for: geometry)
        for kind in ActivityKind.allCases {
            for rows in [0, 1, 3, 8] {
                let card = NotchLayout.cardSize(
                    kind: kind, phase: .expanded, base: CGSize(width: 420, height: 440),
                    payload: kind == .weather ? .weather(WeatherPayload(
                        temperatureCelsius: 20, rainSoonMinutes: 15
                    )) : nil,
                    calendarWeekRows: 6, timerContentHeight: 400,
                    geometry: geometry, routePickerRows: rows, hasSelection: true
                )
                #expect(panel.height >= card.height + 31.99)
            }
        }
        #expect(panel.width == geometry.screenSize.width)
        #expect(panel.height <= geometry.screenSize.height)
        #expect(NotchLayout.panelSize(for: self.geometry(scale: scale, height: 500)).height == 500)
    }
}
