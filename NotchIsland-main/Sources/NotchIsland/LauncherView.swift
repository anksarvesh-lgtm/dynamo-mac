import SwiftUI

/// Spotlight-style launcher drawn on the island's black surface: apps (fuzzy, recent/frequent
/// first), calculator, unit conversion, quick actions, and file search.
struct LauncherView: View {
    @ObservedObject var state: IslandState
    @ObservedObject var engine: LauncherEngine
    @FocusState private var focused: Bool
    @State private var selection = 0

    private var results: [LauncherItem] { state.results }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.secondary)
                ZStack(alignment: .leading) {
                    if state.query.isEmpty {
                        Text("Search apps, files, or type 12*3, 5 km to mi, timer 25…")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.38))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $state.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white)
                        .focused($focused)
                        .onSubmit { performSelected() }
                        .onExitCommand { state.closeLauncher() }
                        .onChange(of: state.query) { _ in selection = 0 }
                }
                KeyCap(text: AppSettings.shared.hotkeyDescription)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 12)

            HairlineDivider().padding(.horizontal, 10)

            if results.isEmpty {
                VStack(spacing: 8) {
                    IconBadge(symbol: "magnifyingglass", size: 40)
                    Text("No results").font(UI.title(12.5))
                    Text("Try an app name, 12*3, 5 km to mi or timer 25")
                        .font(UI.body(10.5)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                        row(item, selected: index == selection)
                            .onTapGesture { state.perform(item) }
                            .onHover { if $0 { selection = index } }
                    }
                }
                .padding(10)
            }
        }
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .onAppear { focused = true; selection = 0 }
        .onMoveCommand { direction in
            let count = results.count
            guard count > 0 else { return }
            switch direction {
            case .down: selection = (selection + 1) % count
            case .up: selection = (selection - 1 + count) % count
            default: break
            }
        }
    }

    private func row(_ item: LauncherItem, selected: Bool) -> some View {
        HStack(spacing: 12) {
            if let image = item.image {
                Image(nsImage: image).resizable().frame(width: 30, height: 30)
            } else {
                IconBadge(symbol: item.symbol ?? "circle", tint: Theme.accent, size: 30)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(item.subtitle).font(UI.body(10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if selected { KeyCap(text: "↩") }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(selected ? Theme.accent.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
    }

    private func performSelected() {
        let items = results
        guard !items.isEmpty else { return }
        state.perform(items[min(selection, items.count - 1)])
    }
}
