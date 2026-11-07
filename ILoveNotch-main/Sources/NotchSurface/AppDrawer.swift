// SPDX-License-Identifier: MIT
import NotchCore
import SwiftUI

/// Every app in the notch as a grid, like Launchpad: the ones in the tab row, the ones kept in the
/// drawer only, and those turned off, dimmed. A click opens one, turning it on first if it was off,
/// and the grid button in the header comes back here. The last tile edits the tab row in place
/// (`TabEditor`) and turns into Done; a right-click puts an app on the row or keeps it in the drawer.
/// A small notch gets smaller tiles, so every app fits without scrolling; they scroll only if even
/// those don't fit.
struct AppDrawer: View {
    let preferences: NotchPreferences
    /// The app open under the drawer, lit.
    let current: FeatureID
    /// Editing the tab row; nil outside edit mode.
    var editor: TabEditor?
    let open: (FeatureID) -> Void
    /// Starts editing, or ends it.
    let edit: () -> Void

    var body: some View {
        ViewThatFits(in: .vertical) {
            grid(compact: false)
            grid(compact: true)
            ScrollView(.vertical) { grid(compact: true) }
                .scrollIndicators(.never)
        }
    }

    private func grid(compact: Bool) -> some View {
        let apps = preferences.tabOrder
        let width: CGFloat = compact ? 48 : 60
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: width, maximum: width), spacing: compact ? 2 : 6)],
            spacing: compact ? 6 : 10
        ) {
            ForEach(Array(apps.enumerated()), id: \.element) { index, feature in
                Group {
                    if let editor, !preferences.rowTabs.contains(feature) {
                        EditingTile(editor: editor, feature: feature, compact: compact)
                    } else {
                        tile(feature, compact: compact)
                    }
                }
                .modifier(Entrance(order: index))
            }
            editTile(compact: compact).modifier(Entrance(order: apps.count))
        }
        .padding(.vertical, 2)
        // A tab dragged down from the row lights the grid it would drop into.
        .background(.white.opacity(editor?.hiding == true ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 14))
        .animation(.easeOut(duration: 0.15), value: editor?.hiding)
    }

    private func tile(_ feature: FeatureID, compact: Bool) -> some View {
        let off = !preferences.isEnabled(feature)
        let inRow = preferences.rowTabs.contains(feature)
        return DrawerTile(title: feature.title, compact: compact, dimmed: off) { hovering in
            AppIcon(feature: feature, lit: feature == current, hovering: hovering, compact: compact)
        } action: {
            open(feature)
        }
        .allowsHitTesting(editor == nil)  // while editing, the row's own tabs move it
        .help(off ? "Turn \(feature.title) on and open it" : "Open \(feature.title)")
        .accessibilityLabel(off ? "\(feature.title), off" : feature.title)
        .accessibilityAddTraits(feature == current ? .isSelected : [])
        .contextMenu {
            if inRow {
                Button("Keep in the Drawer Only") { preferences.moveToDrawer(feature) }
                    .disabled(preferences.rowTabs.count <= 1)  // the row keeps at least one tab
            } else {
                Button(off ? "Turn On and Add to the Row" : "Add to the Row") {
                    preferences.place(feature, at: preferences.rowTabs.count)
                }
            }
        }
    }

    /// Edit, or Done while editing, solid then: the tile clicked to start is the one that ends it.
    private func editTile(compact: Bool) -> some View {
        let editing = editor != nil
        return DrawerTile(title: editing ? "Done" : "Edit", compact: compact, dimmed: false) { hovering in
            let shape = RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
            TablerIcon(name: editing ? "check" : "pencil", size: compact ? 17 : 19)
                .frame(width: compact ? 38 : 46, height: compact ? 30 : 38)
                .background(.white.opacity(editing ? 0.24 : hovering ? 0.1 : 0), in: shape)
                .overlay(
                    shape.strokeBorder(
                        .white.opacity(editing ? 0.55 : 0.35),
                        style: StrokeStyle(lineWidth: 1, dash: editing ? [] : [3, 2.5])))
        } action: {
            edit()
        }
        .help(editing ? "Done editing tabs" : "Arrange the tab row")
        .accessibilityLabel(editing ? "Done editing tabs" : "Edit the tab row")
    }
}

/// An app's symbol on a rounded plate, as the drawer and the editor's tray show it: lit for the
/// open app, a little brighter under the pointer.
struct AppIcon: View {
    let feature: FeatureID
    var lit = false
    var hovering = false
    var compact = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: compact ? 9 : 11, style: .continuous)
        TablerIcon(name: feature.icon, size: compact ? 17 : 19)
            .frame(width: compact ? 38 : 46, height: compact ? 30 : 38)
            .background(.white.opacity(lit ? 0.24 : hovering ? 0.16 : 0.1), in: shape)
            .overlay(shape.strokeBorder(.white.opacity(lit ? 0.55 : 0.12), lineWidth: lit ? 1 : 0.5))
    }
}

/// A drawer tile: an icon over its name, which springs down a little when pressed.
private struct DrawerTile<Icon: View>: View {
    let title: String
    let compact: Bool
    let dimmed: Bool
    @ViewBuilder let icon: (_ hovering: Bool) -> Icon
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            TileLabel(title: title, compact: compact, hovering: hovering) { icon(hovering) }
                .opacity(dimmed ? 0.45 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(TilePress())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// A tile's face, in the drawer and while editing there: an icon over its name.
struct TileLabel<Icon: View>: View {
    let title: String
    let compact: Bool
    var hovering = false
    @ViewBuilder let icon: Icon

    var body: some View {
        VStack(spacing: compact ? 3 : 4) {
            icon
            Text(title)
                .font(.system(size: compact ? 8.5 : 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(hovering ? 0.9 : 0.65))
                .lineLimit(1)
        }
        .frame(width: compact ? 48 : 60)
    }
}

private struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Tiles pop in one after another when the drawer opens, the way Launchpad's icons arrive.
private struct Entrance: ViewModifier {
    let order: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown ? 1 : 0.82)
            .opacity(shown ? 1 : 0)
            .onAppear {
                let pop: Animation? =
                    reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.72).delay(Double(order) * 0.014)
                withAnimation(pop) { shown = true }
            }
    }
}
