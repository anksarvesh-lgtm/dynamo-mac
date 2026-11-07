//
//  SpotlightLauncherService.swift
//  LiquidDynamo
//
//  Notch-integrated Spotlight launcher & fast search engine.
//  Merged from Island and NotchIsland.
//

import AppKit
import Combine
import Foundation

public struct LauncherSearchResult: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let subtitle: String
    public let iconName: String
    public let action: () -> Void

    public static func == (lhs: LauncherSearchResult, rhs: LauncherSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
public final class SpotlightLauncherService: ObservableObject {
    public static let shared = SpotlightLauncherService()

    @Published public var query: String = ""
    @Published public private(set) var results: [LauncherSearchResult] = []

    private var cancellables = Set<AnyCancellable>()

    private init() {
        $query
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] q in
                self?.performSearch(q)
            }
            .store(in: &cancellables)
    }

    public func performSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = defaultQuickActions()
            return
        }

        var found: [LauncherSearchResult] = []

        // 1. Math calculation check
        let expr = NSExpression(format: trimmed)
        if let val = try? expr.expressionValue(with: nil, context: nil) as? NSNumber {
            found.append(
                LauncherSearchResult(
                    title: "\(val)",
                    subtitle: "Calculated result (Press to copy)",
                    iconName: "equal.circle.fill"
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("\(val)", forType: .string)
                }
            )
        }

        // 2. Installed Applications Search
        let apps = ["Safari", "Terminal", "Music", "System Settings", "Finder", "Xcode", "Messages", "Slack"]
        for app in apps {
            if app.localizedCaseInsensitiveContains(trimmed) {
                found.append(
                    LauncherSearchResult(
                        title: app,
                        subtitle: "Application",
                        iconName: "app.fill"
                    ) {
                        NSWorkspace.shared.launchApplication(app)
                    }
                )
            }
        }

        // 3. Fallback web search action
        found.append(
            LauncherSearchResult(
                title: "Search Google for \"\(trimmed)\"",
                subtitle: "Web Search",
                iconName: "magnifyingglass"
            ) {
                if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let url = URL(string: "https://www.google.com/search?q=\(encoded)") {
                    NSWorkspace.shared.open(url)
                }
            }
        )

        results = found
    }

    private func defaultQuickActions() -> [LauncherSearchResult] {
        return [
            LauncherSearchResult(
                title: "Toggle Clamshell Keep-Awake",
                subtitle: "Keep Mac awake when lid is closed",
                iconName: "cup.and.saucer.fill"
            ) {
                KeepAwakeService.shared.toggleKeepAwake()
            },
            LauncherSearchResult(
                title: "Open Android File Manager",
                subtitle: "Browse connected Android devices",
                iconName: "folder.badge.gearshape"
            ) {
                PhoneBridgeWindowController.shared.showWindow()
            }
        ]
    }
}

