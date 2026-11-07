import CoreGraphics
import Foundation
import LedgeCore
import Testing

@testable import LedgeUI

/// Sizing a card that has just replaced another one.
///
/// The simple cards measure themselves, and a measurement outlives the card
/// that made it: the shell keeps the last one and would otherwise spend it on
/// whatever arrives next. Focus reports 66pt; the Shelf, which is taller and
/// (until this was found) never reported at all, was being sized from it.
///
/// Screenshots cannot catch this — each one renders a single card from a fresh
/// presentation, and the bug lives in the *sequence*.
@Suite("Sizing across a card switch")
@MainActor
struct CardSwitchSizingTests {

    private let geometry = NotchGeometry(
        screenSize: CGSize(width: 1470, height: 956),
        notchSize: CGSize(width: 179, height: 32),
        notchCenterX: 735,
        isHardwareNotch: true
    )

    private func activity(_ kind: ActivityKind) -> Activity {
        let payload: ActivityPayload = switch kind {
        case .shelf: .shelf(ShelfPayload(items: []))
        case .focus: .focus(FocusPayload(name: "Deep Work", symbolName: "moon.fill", isActive: true))
        default: .message(MessagePayload(title: "Something", body: ""))
        }
        return Activity(id: ActivityID(kind: kind, source: "test"), createdAt: 0, payload: payload)
    }

    private func height(showing kind: ActivityKind, measured: (ActivityKind, CGFloat)?) -> CGFloat {
        let presentation = NotchPresentation()
        presentation.phase = .expanded
        presentation.selected = activity(kind)
        if let measured {
            // Filed under the card that made it, which is the only way in.
            presentation.reportCardContent(height: measured.1, from: activity(measured.0).id)
        }
        return presentation.cardSize(
            preferences: Preferences(store: MemoryPreferenceStore()),
            geometry: geometry,
            phase: .expanded
        ).height
    }

    @Test("A card is sized from its own measurement")
    func ownMeasurementIsUsed() {
        let sized = height(showing: .focus, measured: (.focus, 66))
        let unmeasured = height(showing: .focus, measured: nil)
        #expect(sized < unmeasured, "measuring it made it shorter than the fixed height")
    }

    /// The bug: the Shelf arrives, the last measurement is the Focus card's,
    /// and the Shelf is drawn 36pt shorter than its own contents need.
    @Test("The card before this one cannot size this one")
    func staleMeasurementIsIgnored() {
        let stale = height(showing: .shelf, measured: (.focus, 66))
        let unmeasured = height(showing: .shelf, measured: nil)
        #expect(stale == unmeasured, "a measurement from another card counts for nothing")
    }

    @Test("Falling back is falling back to the taller height, never the shorter")
    func fallbackIsSafe() {
        let unmeasured = height(showing: .shelf, measured: nil)
        let short = height(showing: .focus, measured: (.focus, 40))
        #expect(unmeasured > short, "the fallback cannot clip what it has not measured")
    }

    @Test("Every simple kind reports before it is trusted")
    func eachKindIsIndependent() {
        for kind in [ActivityKind.focus, .shelf, .privacy, .keyboard, .power, .message, .device] {
            let own = height(showing: kind, measured: (kind, 70))
            let other = height(showing: kind, measured: (.weather, 70))
            #expect(own != other || own == height(showing: kind, measured: nil),
                "\(kind) must be sized by its own measurement or by the fallback")
        }
    }
}
