import IslandCore
import SwiftUI

struct DownloadCompactLeading: View {
    let download: DownloadActivity
    let id: String
    @Environment(\.islandNamespace) private var ns
    var body: some View {
        ZStack {
            if download.state == .completed {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(IslandPalette.batteryGood)
            } else {
                ProgressRing(fraction: download.fraction ?? 0, tint: IslandPalette.download, lineWidth: 2.2).frame(width: 18, height: 18)
                Image(systemName: "arrow.down").font(.system(size: 8, weight: .heavy)).foregroundStyle(IslandPalette.download)
            }
        }
        .islandMatched("icon-\(id)", in: ns)
    }
}

struct DownloadCompactTrailing: View {
    let download: DownloadActivity
    var body: some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(download.state == .completed ? IslandPalette.batteryGood : IslandPalette.download)
            .contentTransition(.numericText())
    }
    private var text: String {
        switch download.state {
        case .completed: "Done"
        case .failed: "Failed"
        case .cancelled: "Stopped"
        case .active: download.fraction.map { "\(Int(($0 * 100).rounded(.down)))%" } ?? Formatters.bytes(download.completedBytes)
        }
    }
}

struct DownloadExpanded: View {
    let download: DownloadActivity
    let id: String
    @Environment(\.islandNamespace) private var ns
    @Environment(\.islandCommands) private var send

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                DownloadCompactLeading(download: download, id: id)
                    .scaleEffect(1.7)
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(download.filename).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                    Text(detail).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(IslandPalette.secondaryText).lineLimit(1)
                }
                Spacer(minLength: 0)
                actions
            }
            if download.state == .active {
                LinearProgress(fraction: download.fraction, tint: IslandPalette.download, height: 5)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var detail: String {
        switch download.state {
        case .completed: return "Downloaded · \(Formatters.bytes(download.totalBytes ?? download.completedBytes))"
        case .failed: return "Download failed"
        case .cancelled: return "Download cancelled"
        case .active:
            var parts: [String] = []
            if let total = download.totalBytes {
                parts.append("\(Formatters.bytes(download.completedBytes)) of \(Formatters.bytes(total))")
            } else {
                parts.append(Formatters.bytes(download.completedBytes))
            }
            if download.isPaused { parts.append("Paused") }
            if let s = download.bytesPerSecond, s > 0, !download.isPaused { parts.append(Formatters.speed(s)) }
            if let eta = download.estimatedTimeRemaining, !download.isPaused { parts.append("\(DurationFormatter.spoken(eta)) left") }
            return parts.joined(separator: " · ")
        }
    }

    @ViewBuilder private var actions: some View {
        HStack(spacing: 8) {
            if download.state == .completed, let url = download.fileURL {
                IslandPillButton(title: "Open", symbol: nil, tint: .white) { send(.download(.open(url))) }
                IslandIconButton(symbol: "folder", size: 13, label: "Show in Finder") { send(.download(.reveal(url))) }
            } else if download.state == .active {
                if download.isPausable {
                    IslandIconButton(symbol: download.isPaused ? "play.fill" : "pause.fill", size: 13,
                                     label: download.isPaused ? "Resume download" : "Pause download") {
                        send(.download(download.isPaused ? .resume(id: id) : .pause(id: id)))
                    }
                }
                if download.isCancellable {
                    IslandIconButton(symbol: "xmark", size: 13, label: "Cancel download") { send(.download(.cancel(id: id))) }
                }
            }
            if download.state != .active {
                IslandIconButton(symbol: "xmark", size: 11, label: "Dismiss") { send(.ui(.dismiss(activityID: id))) }
            }
        }
    }
}
