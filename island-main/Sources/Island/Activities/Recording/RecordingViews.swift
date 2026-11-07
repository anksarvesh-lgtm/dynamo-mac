import IslandCore
import SwiftUI

struct RecordingCompactLeading: View {
    let recording: RecordingActivity
    let id: String
    @Environment(\.islandNamespace) private var ns
    var body: some View {
        HStack(spacing: 5) {
            // Static, like the system privacy indicator — a looping animation would cost CPU every frame.
            Circle().fill(IslandPalette.recording).frame(width: 7, height: 7)
            Image(systemName: recording.camera ? "video.fill" : "mic.fill")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(IslandPalette.recording)
        }
        .islandMatched("icon-\(id)", in: ns)
    }
}

struct RecordingCompactTrailing: View {
    let recording: RecordingActivity
    @Environment(\.islandContentActive) private var active
    var body: some View {
        TimelineView(.periodic(from: .now, by: clockInterval(active: active))) { ctx in
            Text(DurationFormatter.clock(ctx.date.timeIntervalSince(recording.startedAt)))
                .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(IslandPalette.recording)
        }
    }
}

struct RecordingExpanded: View {
    let recording: RecordingActivity
    let id: String
    @Environment(\.islandNamespace) private var ns
    @Environment(\.islandContentActive) private var active
    var body: some View {
        TimelineView(.periodic(from: .now, by: clockInterval(active: active))) { ctx in
            HStack(spacing: 14) {
                Image(systemName: recording.camera ? "video.fill" : "mic.fill")
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(IslandPalette.recording)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(IslandPalette.recording.opacity(0.18)))
                    .islandMatched("icon-\(id)", in: ns)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    Text("Controlled by the app using it").font(.system(size: 11.5)).foregroundStyle(IslandPalette.secondaryText)
                }
                Spacer()
                Text(DurationFormatter.clock(ctx.date.timeIntervalSince(recording.startedAt)))
                    .font(.system(size: 22, weight: .light).monospacedDigit()).foregroundStyle(IslandPalette.recording)
            }
            .accessibilityElement(children: .combine)
        }
    }
    private var title: String {
        switch (recording.microphone, recording.camera) {
        case (true, true): "Camera & microphone in use"
        case (false, true): "Camera in use"
        default: "Microphone in use"
        }
    }
}

