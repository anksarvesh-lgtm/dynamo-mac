//
//  CiderRPCController.swift
//  LiquidDynamo
//
//  RPC and HTTP API bridge for Cider (Electron Apple Music client).
//  Adopted from Atoll's dedicated Cider integration.
//

import AppKit
import Foundation

public final class CiderRPCController: @unchecked Sendable {
    public static let shared = CiderRPCController()

    public static let bundleIdentifier = "sh.cider.genten.mac"
    public static let defaultPort = 10767

    private var baseURL: URL {
        URL(string: "http://localhost:\(Self.defaultPort)/api/v1/playback")!
    }

    private init() {}

    @MainActor
    public var isCiderRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleIdentifier).isEmpty
    }

    /// Toggles play/pause in Cider via HTTP API
    public func togglePlayPause() async {
        guard await isCiderRunning else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("playpause"))
        request.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Skips to next track in Cider
    public func nextTrack() async {
        guard await isCiderRunning else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("next"))
        request.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: request)
    }

    /// Skips to previous track in Cider
    public func previousTrack() async {
        guard await isCiderRunning else { return }
        var request = URLRequest(url: baseURL.appendingPathComponent("previous"))
        request.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: request)
    }
}

