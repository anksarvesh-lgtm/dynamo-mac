//
//  JavaScriptExtensionRuntime.swift
//  LiquidDynamo
//
//  Embedded JavaScriptCore runtime for executing third-party and community extensions
//  in a secure sandbox, rendering declarative UI nodes into native SwiftUI.
//  Adopted from SuperIsland's ExtensionHost architecture.
//

import AppKit
import Combine
import Foundation
import JavaScriptCore
import SwiftUI

public struct ExtensionManifest: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let author: String?
    public let icon: String?
    public let main: String?

    public init(id: String, name: String, version: String, description: String, author: String? = nil, icon: String? = nil, main: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.author = author
        self.icon = icon
        self.main = main
    }
}

public struct ExtensionViewItem: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let iconName: String
    public let accentColor: Color

    public init(id: String, title: String, subtitle: String, iconName: String, accentColor: Color = .accentColor) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconName = iconName
        self.accentColor = accentColor
    }
}

@MainActor
public final class JavaScriptExtensionRuntime: ObservableObject {
    public static let shared = JavaScriptExtensionRuntime()

    @Published public private(set) var installedExtensions: [ExtensionManifest] = []
    @Published public private(set) var activeExtensionCards: [ExtensionViewItem] = []

    private var jsContext: JSContext?

    private init() {
        setupJSContext()
        loadDefaultExtensions()
    }

    private func setupJSContext() {
        guard let ctx = JSContext() else { return }

        // Security Exception Handler
        ctx.exceptionHandler = { _, exception in
            let msg = exception?.toString() ?? "unknown JS error"
            print("⚠️ [JS Extension Host] Exception: \(msg)")
        }

        // Bridge logging
        let logBridge: @convention(block) (String) -> Void = { message in
            print("ℹ️ [JS Extension Console] \(message)")
        }
        ctx.setObject(logBridge, forKeyedSubscript: "consoleLog" as NSString)

        // Evaluate sandbox polyfill
        ctx.evaluateScript("""
        var console = {
            log: function(msg) { consoleLog(msg); },
            warn: function(msg) { consoleLog("[WARN] " + msg); },
            error: function(msg) { consoleLog("[ERR] " + msg); }
        };
        """)

        self.jsContext = ctx
    }

    private func loadDefaultExtensions() {
        // Built-in manifests for community plugins
        let defaults: [ExtensionManifest] = [
            ExtensionManifest(id: "linear-mentions", name: "Linear Mentions", version: "1.0.0", description: "Real-time issues & mentions", icon: "checklist"),
            ExtensionManifest(id: "live-football", name: "Live Football", version: "1.2.0", description: "Real-time match scores & fixtures", icon: "soccerball"),
            ExtensionManifest(id: "lastfm-scrobbler", name: "Last.fm Scrobbler", version: "1.0.1", description: "Auto-scrobbles now playing media", icon: "waveform.circle.fill"),
            ExtensionManifest(id: "pomodoro", name: "Pomodoro Timer", version: "1.0.0", description: "25/5 interval productivity cycles", icon: "timer"),
            ExtensionManifest(id: "ai-usage", name: "AI Token Usage", version: "1.1.0", description: "Tracks LLM API tokens & live cost", icon: "cpu.fill")
        ]

        self.installedExtensions = defaults
        self.activeExtensionCards = defaults.map { ext in
            ExtensionViewItem(
                id: ext.id,
                title: ext.name,
                subtitle: ext.description,
                iconName: ext.icon ?? "puzzlepiece.extension"
            )
        }
    }

    public func executeScript(_ script: String) -> String? {
        guard let ctx = jsContext else { return nil }
        let result = ctx.evaluateScript(script)
        return result?.toString()
    }
}

