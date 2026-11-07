// SPDX-License-Identifier: MIT
import SwiftUI

/// The shortcuts tab: a grid of shortcuts; click one to run it.
struct ShortcutsView: View {
    let shortcuts: ShortcutsFeature

    var body: some View {
        switch shortcuts.status {
        case .loading:
            ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .unavailable:
            FeatureUnavailableView(
                symbol: "square.stack.3d.up.slash",
                title: "Shortcuts unavailable",
                message: "The shortcuts command didn't respond on this Mac.")
        case .ready where shortcuts.visible.isEmpty:
            FeatureUnavailableView(
                symbol: "square.stack.3d.up",
                title: "No shortcuts to show",
                message: "Shortcuts you make in the Shortcuts app show up here.",
                action: (label: "Open Shortcuts", perform: shortcuts.openShortcutsApp))
        case .ready:
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(shortcuts.visible, id: \.self) { name in
                        tile(name)
                    }
                }
                .padding(.vertical, 6)
            }
            .fadingEdges()
        }
    }

    private func tile(_ name: String) -> some View {
        let running = shortcuts.running.contains(name)
        return Button {
            shortcuts.run(name)
        } label: {
            HStack(spacing: 6) {
                if running {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "play.fill").font(.system(size: 10))
                }
                Text(name).font(.caption.weight(.medium)).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(.white.opacity(running ? 0.18 : 0.1), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .disabled(running)
        .accessibilityLabel(running ? "\(name), running" : "Run \(name)")
    }
}
