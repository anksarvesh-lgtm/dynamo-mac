// SPDX-License-Identifier: MIT
import AppKit
import CoreGraphics
import Foundation
import NotchCore
import Testing

@testable import NotchFeatures

struct MediaStreamParserTests {
    // Line shapes as mediaremote-adapter v0.7.7 prints them with `stream --micros`.
    private let empty = #"{"type":"data","diff":false,"payload":{}}"#
    private let song =
        #"{"type":"data","diff":false,"payload":{"title":"Song","artist":"Artist","album":"Album","playing":true,"playbackRate":1,"durationMicros":180000000,"elapsedTimeMicros":30000000,"timestampEpochMicros":1790000000000000,"bundleIdentifier":"com.apple.WebKit.GPU","parentApplicationBundleIdentifier":"com.apple.Safari","processIdentifier":42}}"#

    /// Feeds lines to a fresh parser and returns what's playing after the last one.
    private func play(_ lines: String...) -> NowPlaying? {
        var parser = MediaStreamParser()
        var now: NowPlaying?
        for line in lines { now = parser.consume(line) }
        return now
    }

    @Test func theFirstEmptyPayloadMeansNothingIsPlaying() {
        #expect(play(empty) == nil)
    }

    @Test func aFullPayloadBecomesTheTrackInSeconds() throws {
        let now = try #require(play(empty, song))
        #expect(now.title == "Song" && now.artist == "Artist" && now.album == "Album")
        #expect(now.isPlaying)
        #expect(now.duration == 180 && now.elapsed == 30)
        #expect(now.timestamp == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(now.appBundleID == "com.apple.Safari", "browsers report their media helper; use the parent app")
    }

    @Test func diffsMergeAndNullRemovesAKey() throws {
        let paused = try #require(play(song, #"{"type":"data","diff":true,"payload":{"playing":false}}"#))
        #expect(!paused.isPlaying && paused.title == "Song")
        let noAlbum = try #require(play(song, #"{"type":"data","diff":true,"payload":{"album":null}}"#))
        #expect(noAlbum.album == nil && noAlbum.artist == "Artist")
    }

    @Test func aFullPayloadReplacesEverything() throws {
        let next = try #require(play(song, #"{"type":"data","diff":false,"payload":{"title":"Next","playing":true}}"#))
        #expect(next.title == "Next" && next.artist == nil)
        #expect(play(song, empty) == nil, "an empty full payload clears the track")
    }

    @Test func artworkIsDecodedFromBase64() throws {
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let line =
            #"{"type":"data","diff":false,"payload":{"title":"Art","playing":true,"artworkData":"\#(bytes.base64EncodedString())"}}"#
        #expect(try #require(play(line)).artwork == bytes)
    }

    @Test(arguments: ["", "not json", #"{"type":"error"}"#, #"{"type":"data","diff":true}"#])
    func linesItDoesntUnderstandChangeNothing(line: String) throws {
        #expect(try #require(play(song, line)).title == "Song")
    }

    @Test func shuffleRepeatAndSkippingByTimeComeAlong() throws {
        let modes = #"{"type":"data","diff":true,"payload":{"shuffleMode":3,"repeatMode":2}}"#
        let now = try #require(play(song, modes))
        #expect(now.shuffle == true && now.repeatMode == .one)
        let off = try #require(play(song, #"{"type":"data","diff":true,"payload":{"shuffleMode":1,"repeatMode":1}}"#))
        #expect(off.shuffle == false && off.repeatMode == .off)
        let podcast =
            #"{"type":"data","diff":true,"payload":{"supportsRewind15Seconds":true,"supportsFastForward15Seconds":true}}"#
        #expect(try #require(play(song, podcast)).skipsByInterval)
    }

    @Test func playersThatDontSayLeaveTheModesUnknown() throws {
        let now = try #require(play(song))
        #expect(now.shuffle == nil && now.repeatMode == nil && !now.skipsByInterval, "Spotify reports none of them")
        let unknown = try #require(play(song, #"{"type":"data","diff":true,"payload":{"shuffleMode":0}}"#))
        #expect(unknown.shuffle == nil, "0 is MediaRemote's unknown")
    }
}

struct RepeatModeTests {
    @Test func aClickGoesOffAllOneAndBack() {
        #expect(RepeatMode.off.next(allowsOne: true) == .all)
        #expect(RepeatMode.all.next(allowsOne: true) == .one)
        #expect(RepeatMode.one.next(allowsOne: true) == .off)
        #expect(RepeatMode.all.next(allowsOne: false) == .off, "Spotify's AppleScript has no repeat-one")
    }

    @Test func mediaRemoteNumbersRoundTrip() {
        for mode in [RepeatMode.off, .all, .one] { #expect(RepeatMode(remote: mode.remote) == mode) }
        #expect(RepeatMode(remote: 0) == nil)
    }
}

struct PlayerScriptTests {
    private func list(_ items: NSAppleEventDescriptor...) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (index, item) in items.enumerated() { list.insert(item, at: index + 1) }
        return list
    }

    @Test func musicsStateReadsItsRepeatNames() throws {
        let state = try #require(
            ScriptedState(
                list(.init(boolean: true), .init(string: "one"), .init(double: 42.5), .init(string: "ABC123"))))
        #expect(state.shuffle && state.repeatMode == .one && state.position == 42.5 && state.trackID == "ABC123")
    }

    @Test func spotifysRepeatIsOnOrOff() throws {
        let on = try #require(
            ScriptedState(list(.init(boolean: false), .init(boolean: true), .init(double: 0), .init(string: ""))))
        #expect(!on.shuffle && on.repeatMode == .all)
        #expect(on.trackID == nil, "no track, no link")
        let off = try #require(
            ScriptedState(list(.init(boolean: false), .init(boolean: false), .init(double: 0), .init(string: "x"))))
        #expect(off.repeatMode == .off)
    }

    @Test func aShortListIsNotAState() {
        #expect(ScriptedState(list(.init(boolean: true))) == nil)
    }

    @Test func upNextZipsItsColumns() throws {
        let queue = try #require(
            PlayerQueue(
                upNext: list(
                    .init(string: "Chill"), list(.init(string: "A1"), .init(string: "B2")),
                    list(.init(string: "First"), .init(string: "Second")),
                    list(.init(string: "Artist"), .init(string: "")),
                    list(.init(double: 200), .init(double: 61)))))
        #expect(queue.title == "Chill")
        #expect(queue.items.map(\.id) == ["A1", "B2"] && queue.items.map(\.title) == ["First", "Second"])
        #expect(queue.items[0].artist == "Artist" && queue.items[1].artist == nil, "an empty artist is none")
        #expect(queue.items[1].duration == 61)
    }

    @Test func theLastTrackHasNothingNext() throws {
        let queue = try #require(PlayerQueue(upNext: list(.init(string: "Chill"), list(), list(), list(), list())))
        #expect(queue.items.isEmpty)
    }

    @Test func playersAreRecognizedByBundle() {
        #expect(ScriptedPlayer(bundleID: "com.spotify.client") == .spotify)
        #expect(ScriptedPlayer(bundleID: "com.apple.Music") == .music)
        #expect(ScriptedPlayer(bundleID: "com.google.Chrome") == nil && ScriptedPlayer(bundleID: nil) == nil)
    }
}

struct NowPlayingTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    @Test func positionAdvancesWhilePlaying() {
        let now = NowPlaying(title: "T", isPlaying: true, duration: 100, elapsed: 10, timestamp: start)
        #expect(now.position(at: start.addingTimeInterval(5)) == 15)
        #expect(now.position(at: start.addingTimeInterval(500)) == 100, "clamped to the duration")
    }

    @Test func positionHoldsWhilePausedAndFollowsTheRate() {
        let paused = NowPlaying(title: "T", isPlaying: false, duration: 100, elapsed: 10, timestamp: start)
        #expect(paused.position(at: start.addingTimeInterval(30)) == 10)
        let doubled = NowPlaying(title: "T", isPlaying: true, playbackRate: 2, elapsed: 10, timestamp: start)
        #expect(doubled.position(at: start.addingTimeInterval(5)) == 20)
    }
}

struct PlayerNotificationTests {
    @Test func musicReportsTheTrackInMilliseconds() throws {
        let info: [AnyHashable: Any] = [
            "Name": "Song", "Artist": "Artist", "Album": "Album", "Player State": "Playing", "Total Time": 200_000.0,
        ]
        let now = try #require(PlayerNotification(info, name: "com.apple.Music.playerInfo").merge(into: nil))
        #expect(now.title == "Song" && now.isPlaying && now.duration == 200)
        #expect(now.appBundleID == "com.apple.Music")
    }

    @Test func aBarePauseKeepsTheTrack() throws {
        let playing = NowPlaying(title: "Song", artist: "Artist", isPlaying: true, duration: 200)
        let paused = PlayerNotification(["Player State": "Paused"], name: "com.apple.Music.playerInfo")
        let now = try #require(paused.merge(into: playing))
        #expect(now.title == "Song" && now.artist == "Artist" && now.duration == 200 && !now.isPlaying)
    }

    @Test func stoppingClearsTheTrack() {
        let playing = NowPlaying(title: "Song", isPlaying: true)
        let stopped = PlayerNotification(["Player State": "Stopped"], name: "com.spotify.client.PlaybackStateChanged")
        #expect(stopped.merge(into: playing) == nil)
    }

    @Test func spotifyIsIdentified() throws {
        let info: [AnyHashable: Any] = ["Name": "Song", "Player State": "Playing", "Duration": 1000.0]
        let update = PlayerNotification(info, name: "com.spotify.client.PlaybackStateChanged")
        let now = try #require(update.merge(into: nil))
        #expect(now.appBundleID == "com.spotify.client" && now.duration == 1)
    }
}

struct MediaAccentTests {
    /// A 4×4 image filled with one sRGB color.
    private func solid(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) throws -> CGImage {
        let context = try #require(
            CGContext(
                data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return try #require(context.makeImage())
    }

    @Test func vividCoversKeepTheirHue() throws {
        let accent = try #require(MediaFeature.accent(of: try solid(0.8, 0.1, 0.1)))
        #expect(accent.red > 0.7 && accent.green < 0.5 && accent.blue < 0.5)
    }

    @Test func darkCoversAreLiftedToReadOnBlack() throws {
        let accent = try #require(MediaFeature.accent(of: try solid(0.1, 0.05, 0.25)))
        #expect(max(accent.red, accent.green, accent.blue) >= 0.75)
    }

    @Test func greyCoversStayGrey() throws {
        let accent = try #require(MediaFeature.accent(of: try solid(0.2, 0.2, 0.2)))
        #expect(abs(accent.red - accent.green) < 0.02 && abs(accent.green - accent.blue) < 0.02)
    }

    @Test func seekingSendsWholeMicroseconds() {
        #expect(MediaAdapter.seek(to: 61.5) == ["seek", "61500000"])
        #expect(MediaAdapter.seek(to: -3) == ["seek", "0"])
    }
}

@MainActor
struct MediaFeatureTests {
    private let song = NowPlaying(title: "Song", artist: "A", isPlaying: true)
    private let next = NowPlaying(title: "Next", artist: "A", isPlaying: true)

    @Test func onlySettledTrackChangesOffScreenAreAnnounced() {
        #expect(MediaFeature.shouldAnnounce(next, after: song, settled: true, phase: .background))
        #expect(!MediaFeature.shouldAnnounce(next, after: song, settled: false, phase: .background), "startup state")
        #expect(!MediaFeature.shouldAnnounce(next, after: song, settled: true, phase: .foreground), "already on screen")
        var paused = song
        paused.isPlaying = false
        #expect(!MediaFeature.shouldAnnounce(paused, after: song, settled: true, phase: .background), "same track")
        #expect(!MediaFeature.shouldAnnounce(nil, after: song, settled: true, phase: .background))
    }

    @Test func theClosedNotchKeepsATrackWhilePlayingAndAMinuteAfter() {
        let start = Date(timeIntervalSince1970: 1_000)
        var paused = song
        paused.isPlaying = false
        #expect(MediaFeature.showsOngoing(song, pausedAt: nil, at: start, enabled: true))
        #expect(MediaFeature.showsOngoing(paused, pausedAt: start, at: start.addingTimeInterval(59), enabled: true))
        #expect(!MediaFeature.showsOngoing(paused, pausedAt: start, at: start.addingTimeInterval(61), enabled: true))
        #expect(!MediaFeature.showsOngoing(paused, pausedAt: nil, at: start, enabled: true), "found paused at launch")
        #expect(!MediaFeature.showsOngoing(song, pausedAt: nil, at: start, enabled: false), "setting off")
        #expect(!MediaFeature.showsOngoing(nil, pausedAt: nil, at: start, enabled: true))
    }

    @Test func playingRaisesTheClosedNotchTabAndStoppingClearsIt() {
        let media = MediaFeature(bundle: Bundle(for: BundleMarker.self), defaults: UserDefaults(suiteName: #function)!)
        var shown: [Activity?] = []
        media.onOngoing = { shown.append($0) }
        media.phase = .background
        media.receive(song)
        #expect(shown.last??.title == "Song" && shown.last??.feature == .media)
        media.receive(song)
        #expect(shown.count == 1, "an unchanged track raises nothing")
        media.phase = .stopped
        #expect(shown.last! == nil)
    }

    @Test func swipesSkipOnlyWhenFarAndSideways() {
        #expect(swipeDirection(CGSize(width: -80, height: 5)) == true, "left: next")
        #expect(swipeDirection(CGSize(width: 80, height: 5)) == false, "right: previous")
        #expect(swipeDirection(CGSize(width: 40, height: 0)) == nil, "too short")
        #expect(swipeDirection(CGSize(width: 80, height: 60)) == nil, "too diagonal")
    }

    @Test func theClosedNotchCoverIsATinyPNG() throws {
        let context = try #require(
            CGContext(
                data: nil, width: 300, height: 300, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 300, height: 300))
        let image = try #require(context.makeImage())
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let tiny = try #require(MediaFeature.encodedThumbnail(of: png, side: 36))
        let decoded = try #require(NSBitmapImageRep(data: tiny))
        #expect(decoded.pixelsWide == 36 && decoded.pixelsHigh == 36)
    }

    @Test func withoutTheBundledHelperMediaFallsBack() {
        // Test runners don't bundle mediaremote-adapter, so this exercises the fallback path.
        let media = MediaFeature(bundle: Bundle(for: BundleMarker.self))
        #expect(media.source == .fallback)
        media.phase = .background
        media.receive(song)
        #expect(media.nowPlaying == song)
        media.phase = .stopped
        #expect(media.nowPlaying == nil, "stopping releases the state")
    }
}

private final class BundleMarker {}

struct SpectrumAnalyzerTests {
    private let rate = 48_000.0

    private func tone(_ frequency: Double, amplitude: Float = 1) -> [Float] {
        (0..<SpectrumAnalyzer.size).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    private func loudest(_ bands: [Float]) -> Int { bands.indices.max { bands[$0] < bands[$1] }! }

    @Test func silenceIsFlat() throws {
        let analyzer = try #require(SpectrumAnalyzer(sampleRate: rate))
        #expect(analyzer.bands(of: [Float](repeating: 0, count: SpectrumAnalyzer.size)).allSatisfy { $0 == 0 })
    }

    @Test(arguments: [100.0, 1_000.0, 8_000.0])
    func aToneLightsTheBandItFallsIn(frequency: Double) throws {
        let analyzer = try #require(SpectrumAnalyzer(sampleRate: rate))
        let bands = analyzer.bands(of: tone(frequency))
        let bin = Int((frequency / (rate / Double(SpectrumAnalyzer.size))).rounded())
        #expect(analyzer.bins[loudest(bands)].overlaps((bin - 1)..<(bin + 2)), "the band holding \(frequency) Hz")
        #expect(bands[loudest(bands)] > 0.6, "a full-scale tone is loud")
    }

    @Test func quieterSoundShowsLower() throws {
        let analyzer = try #require(SpectrumAnalyzer(sampleRate: rate))
        let loud = analyzer.bands(of: tone(1_000))
        let quiet = analyzer.bands(of: tone(1_000, amplitude: 0.01))  // 40 dB down
        #expect(quiet[loudest(loud)] < loud[loudest(loud)] - 0.5)
    }

    @Test func theTapOnlyRunsWhileItsBarsCanBeSeen() {
        #expect(MediaFeature.listensToAudio(phase: .foreground, enabled: true, playing: true, reduceMotion: false))
        #expect(!MediaFeature.listensToAudio(phase: .background, enabled: true, playing: true, reduceMotion: false))
        #expect(!MediaFeature.listensToAudio(phase: .foreground, enabled: false, playing: true, reduceMotion: false))
        #expect(!MediaFeature.listensToAudio(phase: .foreground, enabled: true, playing: false, reduceMotion: false))
        #expect(!MediaFeature.listensToAudio(phase: .foreground, enabled: true, playing: true, reduceMotion: true))
    }
}
