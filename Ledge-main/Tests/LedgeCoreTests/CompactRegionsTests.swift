import CoreGraphics
import Foundation
import LedgeCore
import Testing

/// What the resting island answers to, and where each answer routes.
///
/// Written against the two failures a single bounding rectangle produced: the
/// gap between the island and an offset satellite answered the pointer even
/// though nothing is drawn there, and the island's own thirds were measured
/// from a midpoint the satellite had dragged sideways.
@Suite("Compact regions")
struct CompactRegionsTests {

    /// A 275pt island centred on a 1470pt screen, its top at the screen's top.
    private let island = CGRect(x: 597.5, y: 924, width: 275, height: 32.5)
    private let cutout: CGFloat = 179

    private func satellite(offsetBy gap: CGFloat) -> CGRect {
        CGRect(x: island.maxX + gap, y: island.minY, width: 33, height: 33)
    }

    private func point(_ x: CGFloat) -> CGPoint { CGPoint(x: x, y: island.midY) }

    // MARK: - The gap

    /// The failure: a union of the two rectangles takes in the desktop between
    /// them, so the pointer read as "on the notch" over bare wallpaper — and
    /// the card opened from nothing.
    @Test("The space between the island and the satellite belongs to nobody")
    func gapIsNotTheNotch() {
        let regions = CompactRegions(island: island, satellite: satellite(offsetBy: 60))
        let inTheGap = point(island.maxX + 30)
        #expect(!regions.contains(inTheGap))
        #expect(regions.zone(at: inTheGap, cutoutWidth: cutout) == nil)
        // Both shapes still answer for themselves.
        #expect(regions.contains(point(island.midX)))
        #expect(regions.contains(point(island.maxX + 60 + 16)))
    }

    @Test("With no satellite out, only the island answers")
    func islandAlone() {
        let regions = CompactRegions(island: island)
        #expect(regions.rects.count == 1)
        #expect(!regions.contains(point(island.maxX + 20)))
    }

    // MARK: - Zones stay the island's

    /// The other failure: the union's midpoint sat half the gap to the right,
    /// so the cutout was assumed to be somewhere it is not and the island's
    /// trailing ear read as the cutout.
    @Test("The island's thirds do not move when the satellite does")
    func zonesAreAnchoredToTheIsland() {
        let near = CompactRegions(island: island, satellite: satellite(offsetBy: 5))
        let far = CompactRegions(island: island, satellite: satellite(offsetBy: 200))
        for x in [island.minX + 10, island.midX, island.maxX - 10] {
            #expect(near.zone(at: point(x), cutoutWidth: cutout)
                == far.zone(at: point(x), cutoutWidth: cutout),
                "the zone at \(x) must not depend on where the satellite sits")
        }
        // And they are the zones the island's own geometry gives.
        #expect(near.zone(at: point(island.minX + 10), cutoutWidth: cutout) == .leading)
        #expect(near.zone(at: point(island.midX), cutoutWidth: cutout) == .cutout)
        #expect(near.zone(at: point(island.maxX - 10), cutoutWidth: cutout) == .trailing)
    }

    @Test("A point on the satellite routes to the satellite, not to trailing")
    func satelliteRoutesToItself() {
        let regions = CompactRegions(island: island, satellite: satellite(offsetBy: 40))
        let onIt = point(island.maxX + 40 + 16)
        #expect(regions.zone(at: onIt, cutoutWidth: cutout) == .satellite)
    }

    // MARK: - Negative offsets

    /// A negative nudge pulls the satellite back over the island. It is still
    /// its own tenant, so it wins the point it is drawn on — otherwise the
    /// circle on top would open whatever is underneath it.
    @Test("A satellite tucked back over the island still owns its own circle")
    func negativeOffsetOverlaps() {
        let tucked = CGRect(x: island.maxX - 30, y: island.minY, width: 33, height: 33)
        let regions = CompactRegions(island: island, satellite: tucked)
        #expect(regions.zone(at: point(tucked.midX), cutoutWidth: cutout) == .satellite)
        // The island keeps everything the circle is not covering.
        #expect(regions.zone(at: point(island.minX + 10), cutoutWidth: cutout) == .leading)
        #expect(regions.zone(at: point(island.midX), cutoutWidth: cutout) == .cutout)
    }

    @Test("An overlapping satellite adds no reach of its own")
    func negativeOffsetDoesNotExtend() {
        let tucked = CGRect(x: island.maxX - 30, y: island.minY, width: 33, height: 33)
        let regions = CompactRegions(island: island, satellite: tucked)
        #expect(regions.contains(point(tucked.maxX - 1)))
        #expect(!regions.contains(point(tucked.maxX + 4)), "and nothing past it")
    }

    // MARK: - Nonsense

    @Test("A point nowhere near either shape is nowhere")
    func outside() {
        let regions = CompactRegions(island: island, satellite: satellite(offsetBy: 5))
        #expect(regions.zone(at: CGPoint(x: 100, y: 500), cutoutWidth: cutout) == nil)
        #expect(!regions.contains(CGPoint(x: CGFloat.infinity, y: 0)))
    }
}
