import SwiftUI

/// A notification dropping in under the notch: app icon, app name eyebrow, headline, body.
struct NotificationBannerView: View {
    let note: NotchNotification
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var showsSubtitle: Bool { !note.title.isEmpty && !note.subtitle.isEmpty }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: note.icon)
                .resizable()
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(note.appName.uppercased())
                        .font(UI.eyebrow)
                        .tracking(0.6)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Text(Self.relative(note.date))
                        .font(UI.caption())
                        .foregroundStyle(.secondary)
                    IconButton(symbol: "xmark", size: 20, help: "Dismiss", action: onDismiss)
                }
                Text(note.headline)
                    .font(UI.title())
                    .lineLimit(1)
                if showsSubtitle {
                    Text(note.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }
                if !note.body.isEmpty {
                    Text(note.body)
                        .font(UI.body(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(showsSubtitle ? 1 : 2)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    static func relative(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}
