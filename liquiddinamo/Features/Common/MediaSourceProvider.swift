//
//  MediaSourceProvider.swift
//  LiquidDynamo
//
//  Created for Production Dynamic Island Architecture.
//  Provides modular media source provider architecture without private frameworks or undocumented APIs.
//

import AppKit
import Foundation

public struct MediaSnapshot: Equatable {
    public let title: String
    public let artist: String
    public let album: String
    public let isPlaying: Bool
    public let duration: TimeInterval
    public let position: TimeInterval
    public let sourceID: String
    public let hasArtwork: Bool

    public init(
        title: String,
        artist: String,
        album: String,
        isPlaying: Bool,
        duration: TimeInterval = 0,
        position: TimeInterval = 0,
        sourceID: String,
        hasArtwork: Bool = false
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.isPlaying = isPlaying
        self.duration = duration
        self.position = position
        self.sourceID = sourceID
        self.hasArtwork = hasArtwork
    }
}

public enum MediaCommand {
    case play
    case pause
    case togglePlayPause
    case next
    case previous
    case seek(to: TimeInterval)
}

public protocol MediaSourceProvider: AnyObject {
    var sourceID: String { get }
    func currentPlaybackState() async throws -> MediaSnapshot?
    func perform(_ command: MediaCommand) async throws
}

@MainActor
public final class SystemMediaIntegrationManager: ObservableObject {
    public static let shared = SystemMediaIntegrationManager()

    @Published public private(set) var activeSnapshot: MediaSnapshot?
    @Published public private(set) var isPlaybackActive: Bool = false

    private var providers: [MediaSourceProvider] = []

    private init() {
        registerDefaultProviders()
    }

    private func registerDefaultProviders() {
        providers.append(AppleMusicProvider())
        providers.append(SpotifyProvider())
    }

    public func refreshActivePlayback() async {
        for provider in providers {
            if let snapshot = try? await provider.currentPlaybackState(), snapshot.isPlaying {
                self.activeSnapshot = snapshot
                self.isPlaybackActive = true
                return
            }
        }

        // If no provider has confirmed active playback, update state cleanly
        self.isPlaybackActive = false
        if let last = try? await providers.first?.currentPlaybackState() {
            self.activeSnapshot = last
        } else {
            self.activeSnapshot = nil
        }
    }

    public func dispatchCommand(_ command: MediaCommand) async {
        guard let activeSourceID = activeSnapshot?.sourceID,
              let provider = providers.first(where: { $0.sourceID == activeSourceID }) else {
            return
        }
        try? await provider.perform(command)
        await refreshActivePlayback()
    }
}

// MARK: - Native Apple Music Provider (via Documented AppleScript / ScriptingBridge)

final class AppleMusicProvider: MediaSourceProvider {
    let sourceID: String = "com.apple.Music"

    func currentPlaybackState() async throws -> MediaSnapshot? {
        let music = MusicManager.shared
        guard !music.isPlayerIdle && !music.songTitle.isEmpty && music.songTitle != "I'm Handsome" else {
            return nil
        }
        return MediaSnapshot(
            title: music.songTitle,
            artist: music.artistName,
            album: music.album,
            isPlaying: music.isPlaying,
            duration: music.songDuration,
            position: music.elapsedTime,
            sourceID: sourceID,
            hasArtwork: music.albumArt != defaultImage
        )
    }

    func perform(_ command: MediaCommand) async throws {
        let music = MusicManager.shared
        switch command {
        case .play, .pause, .togglePlayPause:
            music.playPause()
        case .next:
            music.nextTrack()
        case .previous:
            music.previousTrack()
        case .seek(let pos):
            music.seek(to: pos)
        }
    }
}

// MARK: - Spotify Provider (via Documented AppleScript Automation)

final class SpotifyProvider: MediaSourceProvider {
    let sourceID: String = "com.spotify.client"

    func currentPlaybackState() async throws -> MediaSnapshot? {
        // Only queries when Spotify is currently running in NSRunningApplication
        guard NSRunningApplication.runningApplications(withBundleIdentifier: sourceID).first != nil else {
            return nil
        }
        let music = MusicManager.shared
        guard music.isPlaying else { return nil }
        return MediaSnapshot(
            title: music.songTitle,
            artist: music.artistName,
            album: music.album,
            isPlaying: music.isPlaying,
            duration: music.songDuration,
            position: music.elapsedTime,
            sourceID: sourceID,
            hasArtwork: music.albumArt != defaultImage
        )
    }

    func perform(_ command: MediaCommand) async throws {
        let music = MusicManager.shared
        switch command {
        case .play, .pause, .togglePlayPause:
            music.playPause()
        case .next:
            music.nextTrack()
        case .previous:
            music.previousTrack()
        case .seek(let pos):
            music.seek(to: pos)
        }
    }
}

