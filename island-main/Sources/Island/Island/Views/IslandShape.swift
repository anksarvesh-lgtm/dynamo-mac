import SwiftUI

/// The Island silhouette, drawn at the top-centre of a fixed canvas: flush with the screen's top edge,
/// small concave "ears" that blend into the bezel like the hardware notch, and rounded bottom corners.
///
/// Width, height, horizontal offset and both radii are *animatable shape data*, so the morph is a pure
/// path interpolation — SwiftUI never re-lays-out the Island's content while it springs open or shut.
struct IslandShape: Shape {
    var earRadius: CGFloat
    var bottomRadius: CGFloat
    /// Body width including ears, and height.
    var width: CGFloat
    var height: CGFloat
    /// Horizontal shift of the body's centre from the canvas centre.
    var offsetX: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>> {
        get { AnimatablePair(AnimatablePair(earRadius, bottomRadius), AnimatablePair(AnimatablePair(width, height), offsetX)) }
        set {
            earRadius = newValue.first.first
            bottomRadius = newValue.first.second
            width = newValue.second.first.first
            height = newValue.second.first.second
            offsetX = newValue.second.second
        }
    }

    func path(in canvas: CGRect) -> Path {
        let w = max(0, min(width, canvas.width)), h = max(0, min(height, canvas.height))
        guard w > 0, h > 0 else { return Path() }
        let rect = CGRect(x: canvas.midX - w / 2 + offsetX, y: canvas.minY, width: w, height: h)
        let ear = min(earRadius, h / 2, w / 4)
        let body = w - 2 * ear
        let br = max(0, min(bottomRadius, h - ear, body / 2))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + ear, y: rect.minY + ear), control: CGPoint(x: rect.minX + ear, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + ear, y: rect.maxY - br))
        p.addQuadCurve(to: CGPoint(x: rect.minX + ear + br, y: rect.maxY), control: CGPoint(x: rect.minX + ear, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - ear - br, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - ear, y: rect.maxY - br), control: CGPoint(x: rect.maxX - ear, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - ear, y: rect.minY + ear))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - ear, y: rect.minY))
        p.closeSubpath()
        return p
    }

    /// The body without the ears (content clip).
    var withoutEars: IslandShape {
        IslandShape(earRadius: 0, bottomRadius: bottomRadius, width: max(0, width - 2 * earRadius), height: height, offsetX: offsetX)
    }
}
