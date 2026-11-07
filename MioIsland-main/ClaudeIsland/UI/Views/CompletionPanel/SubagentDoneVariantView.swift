//
//  SubagentDoneVariantView.swift
//  ClaudeIsland
//
//  Variant B — subagent done (sticky). Per-subagent row. Dismiss on ×
//  click / session state change / tap on empty panel area / notch click.
//  Spec §5.6 / §5.7.
//

import SwiftUI

struct SubagentDoneVariantView: View {
    let entry: CompletionEntry
    let subagents: [SubagentLine]
    @ObservedObject private var controller = CompletionPanelController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            rows
            terminalButtonRow
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { controller.dismissFront(stableId: entry.stableId) })
        .onAppear { controller.setPanelVisible(true) }
        .onDisappear { controller.setPanelVisible(false) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(entry.projectName).font(.system(size: 12, weight: .semibold))
            Text(L10n.subagentDoneBadge(subagents.count))
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(Color(red: 0xB4/255, green: 0xB4/255, blue: 0xFF/255).opacity(0.2)))
                .foregroundColor(Color(red: 0xB4/255, green: 0xB4/255, blue: 0xFF/255))
            Spacer()
            Button { controller.dismissFront(stableId: entry.stableId) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.qrClose)
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(subagents.enumerated()), id: \.offset) { _, line in
                HStack(spacing: 8) {
                    Text("[\(line.agentType)]")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255))
                        .frame(minWidth: 80, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        if !line.description.isEmpty {
                            Text(line.description).font(.system(size: 11))
                                .foregroundColor(.white.opacity(0.9)).lineLimit(1)
                        }
                        if !line.lastToolHint.isEmpty {
                            Text(line.lastToolHint).font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.6)).lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)
            }
        }
    }

    private var terminalButtonRow: some View {
        HStack {
            Button(L10n.qrAcknowledge) { controller.dismissFront(stableId: entry.stableId) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                        )
                )
                .foregroundColor(.white.opacity(0.9))
            Spacer()
            Button(L10n.qrGoToTerminal) { jumpToTerminal() }
                .buttonStyle(.plain).font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 7)
                    .fill(Color(red: 0xCA/255, green: 0xFF/255, blue: 0x00/255)))
                .foregroundColor(.black)
        }
    }

    private func jumpToTerminal() {
        let stableId = entry.stableId
        Task {
            guard let session = await SessionStore.shared.session(withStableId: stableId) else { return }
            _ = await TerminalJumper.shared.jump(to: session)
            await MainActor.run { controller.dismissFront(stableId: stableId) }
        }
    }
}
