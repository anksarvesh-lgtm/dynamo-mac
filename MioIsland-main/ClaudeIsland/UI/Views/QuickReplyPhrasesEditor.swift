//
//  QuickReplyPhrasesEditor.swift
//  ClaudeIsland
//
//  Settings → Behavior subview for editing the Variant A phrase list.
//  Enforces ≥1 ≤6 via QuickReplyPhrases.clamp. Spec §5.8.
//

import SwiftUI

struct QuickReplyPhrasesEditor: View {
    @State private var phrases: [QuickReplyPhrase] = QuickReplyPhrases.current

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach($phrases) { $p in
                HStack(spacing: 8) {
                    TextField("", text: $p.text).textFieldStyle(.roundedBorder)
                    Button {
                        guard phrases.count > QuickReplyPhrases.minCount else { return }
                        phrases.removeAll { $0.id == p.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(phrases.count > QuickReplyPhrases.minCount
                                             ? .red.opacity(0.7) : .gray.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .disabled(phrases.count <= QuickReplyPhrases.minCount)
                    .help(phrases.count <= QuickReplyPhrases.minCount
                          ? L10n.qrEditorMinHint : L10n.qrEditorDeleteHint)
                }
            }

            HStack {
                Button {
                    guard phrases.count < QuickReplyPhrases.maxCount else { return }
                    phrases.append(QuickReplyPhrase(text: ""))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(L10n.qrEditorAdd)
                    }
                }
                .buttonStyle(.plain)
                .disabled(phrases.count >= QuickReplyPhrases.maxCount)

                if phrases.count >= QuickReplyPhrases.maxCount {
                    Text(L10n.qrEditorMaxHint).font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                Button(L10n.qrEditorReset) {
                    QuickReplyPhrases.resetToDefaults()
                    phrases = QuickReplyPhrases.current
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: phrases) { _, new in
            QuickReplyPhrases.current = new
        }
    }
}
