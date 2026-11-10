//
//  OmniLauncherOverlayView.swift
//  LiquidDynamo
//
//  Spotlight-style floating launcher overlay rendering inside or below Dynamic Island.
//  Styled with authentic Liquid Glass materials matching Apple VisionOS / macOS Dynamic Island.
//

import AppKit
import SwiftUI

public struct OmniLauncherOverlayView: View {
    @ObservedObject var launcher = OmniLauncherEngine.shared
    @FocusState private var isFieldFocused: Bool

    public init() {}

    public var body: some View {
        if launcher.isVisible {
            VStack(spacing: 8) {
                // MARK: - Exact Liquid Glass Search / Ask Pill
                HStack(spacing: 12) {
                    ZStack(alignment: .leading) {
                        if launcher.queryText.isEmpty {
                            Text("Search or Ask")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.65))
                        }

                        TextField("", text: $launcher.queryText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(Color.white)
                            .focused($isFieldFocused)
                            .onSubmit {
                                if let first = launcher.results.first {
                                    executeItem(first)
                                }
                            }
                    }

                    Spacer(minLength: 0)

                    if launcher.queryText.isEmpty {
                        Button {
                            // Native macOS Dictation trigger
                            NSApp.sendAction(NSSelectorFromString("startDictation:"), to: nil, from: nil)
                        } label: {
                            Image(systemName: "mic")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Color.white.opacity(0.65))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {
                            launcher.queryText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.white.opacity(0.60))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .frame(width: 480, height: 50)
                .background(
                    ZStack {
                        // 1. Behind-Window Frosted Liquid Glass Vibrancy
                        VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
                            .clipShape(Capsule())

                        // 2. Translucent Obsidian Depth Gradient (Matches reference image)
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.black.opacity(0.86),
                                        Color.black.opacity(0.68)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // 3. Apple Specular Perimeter Hairline Rim
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.24), location: 0.0),
                                        .init(color: Color.white.opacity(0.08), location: 0.50),
                                        .init(color: Color.black.opacity(0.20), location: 1.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 0.85
                            )

                        // 4. Horizon Sheen Specular Highlight
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.12),
                                        Color.clear
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                            .padding(1)
                    }
                    .compositingGroup()
                    .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
                    .shadow(color: Color.black.opacity(0.50), radius: 20, x: 0, y: 10)
                )

                // MARK: - Dropdown Results Sheet (Only visible when query is typed and results available)
                if !launcher.queryText.isEmpty && !launcher.results.isEmpty {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 4) {
                            ForEach(launcher.results) { item in
                                launcherRow(item)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)
                    }
                    .frame(width: 480)
                    .frame(maxHeight: 260)
                    .background(
                        ZStack {
                            VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
                                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.black.opacity(0.88),
                                            Color.black.opacity(0.72)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        stops: [
                                            .init(color: Color.white.opacity(0.22), location: 0.0),
                                            .init(color: Color.white.opacity(0.06), location: 0.60),
                                            .init(color: Color.clear, location: 1.0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.85
                                )
                        }
                        .compositingGroup()
                        .shadow(color: Color.black.opacity(0.40), radius: 12, x: 0, y: 6)
                        .shadow(color: Color.black.opacity(0.50), radius: 24, x: 0, y: 12)
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.top, 6)
            .transition(.scale(scale: 0.95).combined(with: .opacity))
            .onAppear {
                isFieldFocused = true
            }
            .onExitCommand {
                launcher.isVisible = false
            }
        }
    }

    private func launcherRow(_ item: OmniLauncherItem) -> some View {
        Button {
            executeItem(item)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.white.opacity(0.08)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)

                    Text(item.subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "return")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.3))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
        }
        .buttonStyle(.plain)
    }

    private func executeItem(_ item: OmniLauncherItem) {
        switch item.kind {
        case .app(let url):
            NSWorkspace.shared.open(url)
            launcher.isVisible = false
        case .calc(let text), .convert(let text):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            launcher.isVisible = false
        case .file(let url):
            NSWorkspace.shared.open(url)
            launcher.isVisible = false
        case .aiResearch(let prompt):
            if let encoded = prompt.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
               let url = URL(string: "https://duckduckgo.com/?q=\(encoded)") {
                NSWorkspace.shared.open(url)
            }
            launcher.isVisible = false
        case .quickAction(let action):
            switch action {
            case "shelf":
                LiquidViewCoordinator.shared.currentView = .shelf
            case "phone":
                LiquidViewCoordinator.shared.currentView = .phoneBridge
            case "clamshell":
                KeepAwakeService.shared.toggleKeepAwake()
            case "stats":
                LiquidViewCoordinator.shared.currentView = .stats
            default:
                break
            }
            launcher.isVisible = false
        }
    }
}
