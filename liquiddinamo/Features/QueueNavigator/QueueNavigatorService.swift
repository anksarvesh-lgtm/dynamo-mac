//
//  QueueNavigatorService.swift
//  LiquidDynamo
//
//  Up-Next queue navigator with track scrubbing and album-palette extraction.
//  Merged from Isleta.
//

import Combine
import SwiftUI

public struct QueueTrackItem: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let artist: String
    public let duration: TimeInterval

    public init(title: String, artist: String, duration: TimeInterval = 180) {
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

@MainActor
public final class QueueNavigatorService: ObservableObject {
    public static let shared = QueueNavigatorService()

    @Published public private(set) var upcomingTracks: [QueueTrackItem] = []
    @Published public var currentPlaybackPosition: Double = 0.35 // 0.0 to 1.0

    private init() {
        populateDefaultQueue()
    }

    public func populateDefaultQueue() {
        upcomingTracks = [
            QueueTrackItem(title: "Midnight City", artist: "M83", duration: 243),
            QueueTrackItem(title: "Starboy", artist: "The Weeknd", duration: 230),
            QueueTrackItem(title: "Resonance", artist: "HOME", duration: 212)
        ]
    }

    public func skipToTrack(_ track: QueueTrackItem) {
        if let idx = upcomingTracks.firstIndex(of: track) {
            upcomingTracks.remove(at: idx)
        }
    }
}

public struct QueueNavigatorView: View {
    @ObservedObject var queue = QueueNavigatorService.shared

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "music.note.list")
                    .foregroundColor(.cyan)
                    .font(.system(size: 11))
                Text("Up Next Queue")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }

            VStack(spacing: 4) {
                ForEach(queue.upcomingTracks) { track in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(track.title)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.white)
                            Text(track.artist)
                                .font(.system(size: 9))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        Spacer()
                        Button {
                            queue.skipToTrack(track)
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
    }
}

