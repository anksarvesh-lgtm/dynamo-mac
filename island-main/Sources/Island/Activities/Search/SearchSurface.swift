import AppKit
import IslandCore
import SwiftUI

struct SearchSurface: View {
    let model: SearchViewModel
    let metrics: IslandMetrics
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: metrics.compactHeight)
            field
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1).padding(.horizontal, 14)
            switch model.answer {
            case .idle: results
            case .running(let q): ResearchRunningView(question: q)
            case .done(let a): ResearchAnswerView(answer: a)
            case .failed(let m): ResearchFailedView(message: m)
            }
        }
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { _, _ in focused = true }
    }

    private var field: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15, weight: .semibold)).foregroundStyle(IslandPalette.secondaryText)
            TextField("Search apps, files, web, actions…", text: Binding(get: { model.query }, set: { model.query = $0 }))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white)
                .focused($focused)
                .accessibilityLabel("Search")
            if model.isSearching {
                ProgressView().controlSize(.small).tint(.white)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 50)
    }

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                    ForEach(model.sections) { section in
                        Text(section.category.title.uppercased())
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 22)
                            .frame(height: 24, alignment: .bottomLeading)
                        if let error = section.error, section.results.isEmpty {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.5))
                                .padding(.horizontal, 22).frame(height: 40)
                        }
                        ForEach(section.results) { r in
                            SearchRow(result: r, selected: r.id == model.selected?.id)
                                .id(r.id)
                                .onTapGesture { model.execute(r) }
                                .onHover { if $0 { model.select(r.id) } }
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .onChange(of: model.selectedID) { _, id in
                if let id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } }
            }
        }
    }
}

struct SearchRow: View {
    let result: SearchResult
    let selected: Bool

    var body: some View {
        HStack(spacing: 11) {
            icon.frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                if let sub = subtitle {
                    Text(sub).font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if selected {
                Image(systemName: "return").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(selected ? 0.14 : 0)))
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    private var subtitle: String? {
        let parts = [result.domain, result.snippet ?? result.subtitle].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " — ")
    }

    @ViewBuilder private var icon: some View {
        if let url = result.iconFileURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else if let fav = result.faviconURL {
            AsyncImage(url: fav) { img in img.resizable().clipShape(RoundedRectangle(cornerRadius: 4)) } placeholder: {
                Image(systemName: result.symbol ?? "globe").foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 18, height: 18)
        } else {
            Image(systemName: result.symbol ?? "circle").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
        }
    }
}

struct ResearchRunningView: View {
    let question: String
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(.white)
            Text("Researching “\(question)”…").font(.system(size: 13)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
            Spacer()
        }
        .padding(20)
    }
}

struct ResearchFailedView: View {
    let message: String
    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
    }
}

struct ResearchAnswerView: View {
    let answer: ResearchAnswer
    @Environment(\.islandCommands) private var send
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text(answer.text).font(.system(size: 13)).foregroundStyle(.white).textSelection(.enabled)
                if !answer.citations.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(answer.citations) { c in
                            Button { send(.openURL(c.url)) } label: {
                                HStack(spacing: 6) {
                                    Text("[\(c.index)]").font(.system(size: 11, weight: .bold).monospacedDigit())
                                    Text(c.title).lineLimit(1)
                                    Text(c.url.host ?? "").foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                                }
                                .font(.system(size: 11.5))
                                .foregroundStyle(.white.opacity(0.75))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } else if answer.usedWeb == false {
                    Text("Answered without web sources.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }
}
