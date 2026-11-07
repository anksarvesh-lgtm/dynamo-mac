import CoreGraphics

/// Which part of the resting island the cursor is over.
///
/// The ears are one hover surface but not one subject: while a duo rests —
/// music in the island, a level readout or a timer in the satellite seat —
/// the trailing side belongs to the satellite's own card and everywhere else
/// belongs to the resident's. The zones split at the hardware cutout's edges,
/// so the boundary the user perceives (art | notch | readout) is exactly the
/// boundary that decides.
public enum CompactZone: Equatable, Sendable {
    case leading
    case cutout
    case trailing
    /// The detached circle beyond the island's trailing edge. Its own zone
    /// rather than a kind of `trailing`: it is a separate shape with a gap in
    /// between, and what opens from it is decided by what is sitting in it.
    case satellite
}

/// What a resting island answers to: itself, and the satellite that may hang
/// outside it.
///
/// Two rectangles rather than one that covers both. A union would take in the
/// empty gap between them — the pointer would count as "on the notch" over
/// bare desktop — and it would move the island's own midpoint, which is what
/// the leading/cutout/trailing split is measured from. The satellite can sit
/// 200pt out, so that shift is not small: the zones would think the cutout had
/// moved half that distance.
public struct CompactRegions: Equatable, Sendable {

    /// The compact shape itself, in screen coordinates.
    public let island: CGRect

    /// The satellite's own rectangle, when one is out. The same rectangle the
    /// view draws from.
    public let satellite: CGRect?

    public init(island: CGRect, satellite: CGRect? = nil) {
        self.island = island
        self.satellite = satellite
    }

    /// Every rectangle that should answer the pointer, in test order — never
    /// the space between them.
    public var rects: [CGRect] { [island] + (satellite.map { [$0] } ?? []) }

    public func contains(_ point: CGPoint) -> Bool {
        rects.contains { $0.contains(point) }
    }

    /// Which part of the resting island the pointer is over, or nil when it is
    /// over neither shape.
    ///
    /// The satellite is tested first and on its own rectangle; the island's
    /// three zones are measured from the island, whatever the satellite is
    /// doing.
    public func zone(at point: CGPoint, cutoutWidth: CGFloat) -> CompactZone? {
        if let satellite, satellite.contains(point) { return .satellite }
        guard island.contains(point) else { return nil }
        return NotchLayout.compactZone(
            x: point.x, restingRect: island, cutoutWidth: cutoutWidth
        )
    }
}

extension NotchLayout {

    /// Zones a pointer x-position against a resting island rect.
    ///
    /// The cutout is centred in the rect (the resting shape grows symmetric
    /// ears around the hardware notch). Non-finite input answers `.cutout` —
    /// the neutral zone that opens the main card — and a cutout wider than
    /// the rect degenerates to the same answer for every point inside it.
    public static func compactZone(
        x: CGFloat,
        restingRect: CGRect,
        cutoutWidth: CGFloat
    ) -> CompactZone {
        guard x.isFinite, restingRect.width.isFinite, cutoutWidth.isFinite else { return .cutout }
        let half = max(0, cutoutWidth) / 2
        if x < restingRect.midX - half { return .leading }
        if x > restingRect.midX + half { return .trailing }
        return .cutout
    }
}
