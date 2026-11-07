// SPDX-License-Identifier: MIT
import AppKit
import NotchCore
import SwiftUI

/// A tab on the move in edit mode.
struct TabDrag: Equatable {
    var feature: FeatureID
    /// It was picked up in the row; otherwise it came from the drawer's grid.
    var fromRow: Bool
    /// Its index in the row if it were dropped now; nil while it's off the row.
    var slot: Int?
}

/// Editing the tab row right in the app drawer, like iOS's jiggling Home Screen: nothing moves to
/// another screen. The row's tabs wiggle, each with a minus that keeps it in the drawer only; the
/// drawer's apps off the row (those turned off dimmed) wiggle with a plus that adds them. Tabs drag
/// into a new order, down into the grid, or up from it into the row. Every change applies at once,
/// so the row is always what the notch will show. The header's row (`EditingRow`) and the grid's
/// tiles (`EditingTile`) share this, so a tab travels between them; NotchView draws the lifted tab
/// (`LiftedTab`) over both, and Done ends editing.
@MainActor
@Observable
final class TabEditor {
    /// A place in the row: a tab, or the gap an app from the grid would drop into.
    enum Place: Hashable {
        case tab(FeatureID)
        case gap
    }

    let preferences: NotchPreferences
    /// The width the tabs share, as outside edit mode, so they keep their size.
    let room: CGFloat
    private(set) var drag: TabDrag?
    /// Where the pointer is while dragging, which the lifted tab follows without animation.
    private(set) var pointer = CGPoint.zero
    // Where things are in the editor's coordinates, for dropping tabs on them.
    @ObservationIgnored var headerFrame = CGRect.zero
    @ObservationIgnored var rowFrame = CGRect.zero
    @ObservationIgnored var gridFrame = CGRect.zero

    nonisolated static let space = "TabEditor"

    init(preferences: NotchPreferences, room: CGFloat) {
        self.preferences = preferences
        self.room = room
    }

    /// A tab from the row is over the grid, where dropping it keeps it in the drawer only.
    var hiding: Bool { drag?.fromRow == true && gridFrame.contains(pointer) }

    func dragging(_ feature: FeatureID, fromRow: Bool) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { [self] value in
                pointer = value.location
                // An app from the grid over the row opens a gap, so the row has one more place.
                let count = preferences.rowTabs.count + (fromRow ? 0 : 1)
                let overRow = headerFrame.insetBy(dx: 0, dy: -14).contains(value.location)
                let slot =
                    overRow
                    ? Self.slot(
                        at: value.location.x, from: rowFrame.minX, width: NotchView.tabWidth(count: count, room: room),
                        count: count) : nil
                let moved = TabDrag(feature: feature, fromRow: fromRow, slot: slot)
                guard moved != drag else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.72)) { drag = moved }
            }
            .onEnded { [self] value in drop(at: value.location) }
    }

    private func drop(at location: CGPoint) {
        guard let drag else { return }
        withAnimation(motion) {
            if let slot = drag.slot {
                preferences.place(drag.feature, at: slot)
            } else if drag.fromRow, gridFrame.contains(location), preferences.rowTabs.count > 1 {
                preferences.moveToDrawer(drag.feature)
            }
            self.drag = nil
        }
    }

    /// Off the row, still on, into the drawer.
    func hide(_ feature: FeatureID) {
        guard preferences.rowTabs.count > 1 else { return }
        withAnimation(motion) { preferences.moveToDrawer(feature) }
    }

    func show(_ feature: FeatureID) {
        withAnimation(motion) { preferences.place(feature, at: preferences.rowTabs.count) }
    }

    func move(_ feature: FeatureID, by offset: Int) {
        guard let index = preferences.rowTabs.firstIndex(of: feature) else { return }
        withAnimation(motion) { preferences.place(feature, at: index + offset) }
    }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private var motion: Animation? { reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78) }

    /// The row as it would be if the drag ended now: the dragged tab in its slot, or a gap where an
    /// app from the grid would join; a tab dragged off the row leaves it.
    static func places(_ tabs: [FeatureID], during drag: TabDrag?) -> [Place] {
        var places = tabs.map(Place.tab)
        guard let drag else { return places }
        places.removeAll { $0 == .tab(drag.feature) }
        if let slot = drag.slot {
            places.insert(drag.fromRow ? .tab(drag.feature) : .gap, at: min(max(slot, 0), places.count))
        }
        return places
    }

    /// The place under the pointer, in a row of `count` places of `width` starting at `start`.
    static func slot(at x: CGFloat, from start: CGFloat, width: CGFloat, count: Int) -> Int {
        guard count > 0, width > 0 else { return 0 }
        let place = Int(((x - start) / (width + NotchView.tabSpacing)).rounded(.down))
        return min(max(place, 0), count - 1)
    }
}

/// The header's tab row in edit mode: the tabs keep their size and wiggle, each with a minus, and
/// drag into a new order or down into the grid.
struct EditingRow: View {
    let editor: TabEditor

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let places = TabEditor.places(editor.preferences.rowTabs, during: editor.drag)
        let width = NotchView.tabWidth(count: places.count, room: editor.room)
        let removable = editor.preferences.rowTabs.count > 1  // the row keeps at least one tab
        HStack(spacing: NotchView.tabSpacing) {
            ForEach(places, id: \.self) { place in
                switch place {
                case .gap:
                    Capsule()
                        .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                        .padding(2)
                        .frame(width: width, height: 26)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                case .tab(let feature):
                    tab(feature, width: width, removable: removable)
                }
            }
        }
        .reportsFrame { editor.rowFrame = $0 }
    }

    private func tab(_ feature: FeatureID, width: CGFloat, removable: Bool) -> some View {
        let lifted = editor.drag?.feature == feature
        return TablerIcon(name: feature.icon)
            .frame(width: width, height: 26)
            .background(.white.opacity(0.12), in: Capsule().inset(by: 2))
            .overlay(alignment: .topLeading) {
                if removable, !lifted {
                    EditBadge(symbol: "minus", tint: Color(white: 0.32), label: "Keep \(feature.title) in the drawer") {
                        editor.hide(feature)
                    }
                    .offset(x: -5, y: -5)
                }
            }
            .modifier(Wiggle(still: reduceMotion || editor.drag != nil, pace: feature))
            .opacity(lifted ? 0 : 1)  // it keeps its place while the lifted one follows the pointer
            .contentShape(Rectangle())
            .gesture(editor.dragging(feature, fromRow: true))
            .transition(.scale(scale: 0.6).combined(with: .opacity))
            .help(feature.title)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(feature.title)
            .accessibilityHint("Drag to move it, or down to keep it in the drawer.")
            .accessibilityAction(named: "Move Left") { editor.move(feature, by: -1) }
            .accessibilityAction(named: "Move Right") { editor.move(feature, by: 1) }
            .accessibilityAction(named: "Keep in the Drawer") { editor.hide(feature) }
    }
}

/// An app in the drawer's grid, in edit mode, that isn't in the row: it wiggles with a plus, and a
/// click or a drag up into the row adds it there, turning it on if it was off.
struct EditingTile: View {
    let editor: TabEditor
    let feature: FeatureID
    let compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let off = !editor.preferences.isEnabled(feature)
        TileLabel(title: feature.title, compact: compact) {
            AppIcon(feature: feature, compact: compact)
                .overlay(alignment: .topTrailing) {
                    EditBadge(symbol: "plus", tint: .green, label: "Add \(feature.title) to the row") {
                        editor.show(feature)
                    }
                    .offset(x: 5, y: -5)
                }
                .modifier(Wiggle(still: reduceMotion || editor.drag != nil, pace: feature))
        }
        .opacity(editor.drag?.feature == feature ? 0.25 : off ? 0.45 : 1)
        .contentShape(Rectangle())
        .onTapGesture { editor.show(feature) }
        .gesture(editor.dragging(feature, fromRow: false))
        .help(off ? "Turn \(feature.title) on and add it to the row" : "Add \(feature.title) to the row")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(off ? "\(feature.title), off" : feature.title)
        .accessibilityHint("Adds it to the tab row.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { editor.show(feature) }
    }
}

/// The tab under the pointer while dragging, a little larger and lifted off the notch.
struct LiftedTab: View {
    let editor: TabEditor

    var body: some View {
        if let drag = editor.drag {
            TablerIcon(name: drag.feature.icon, size: 18)
                .frame(width: 42, height: 34)
                .background(.white.opacity(0.24), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(
                        .white.opacity(0.4), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.55), radius: 10, y: 5)
                .position(editor.pointer)
                .allowsHitTesting(false)
                .transition(.scale(scale: 0.7).combined(with: .opacity))
        }
    }
}

/// Ends editing: white, as iOS's Done is the one bright thing on a jiggling Home Screen.
struct DoneButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Done")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12)
                .frame(height: 22)
                .background(.white, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Done editing tabs")
    }
}

/// A small round button on a tab's corner: minus to keep it in the drawer, plus to add it to the row.
private struct EditBadge: View {
    let symbol: String
    let tint: Color
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 7, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(tint, in: Circle())
                .overlay(Circle().strokeBorder(.black.opacity(0.6), lineWidth: 1))
                .contentShape(Circle().inset(by: -3))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

extension View {
    /// Reports the view's frame in the editor's coordinates as it changes, for dropping tabs on it.
    fileprivate func reportsFrame(_ action: @escaping (CGRect) -> Void) -> some View {
        onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(TabEditor.space))
        } action: {
            action($0)
        }
    }

    /// While editing, reports the view's frame to the editor. The reporter comes and goes with edit
    /// mode, so a new editor hears the frame at once even though the view itself hasn't moved.
    func reportsFrame(to editor: TabEditor?, _ frame: ReferenceWritableKeyPath<TabEditor, CGRect>) -> some View {
        background {
            if let editor {
                Color.clear.reportsFrame { editor[keyPath: frame] = $0 }
            }
        }
    }
}

/// The rock of a tab waiting to be moved, each at its own pace so the row doesn't move in step.
private struct Wiggle: ViewModifier {
    /// While dragging, and with Reduce Motion, the tabs hold still.
    let still: Bool
    let pace: FeatureID

    func body(content: Content) -> some View {
        let beat = 0.12 + 0.011 * Double((FeatureID.allCases.firstIndex(of: pace) ?? 0) % 5)
        content.phaseAnimator([-1.0, 1.0]) { view, side in
            view.rotationEffect(.degrees(still ? 0 : side * 1.8))
        } animation: { _ in
            .easeInOut(duration: beat)
        }
    }
}
