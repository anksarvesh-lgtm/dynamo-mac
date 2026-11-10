//
//  OmniLauncherOverlayView.swift
//  LiquidDynamo
//
//  Spotlight-style floating launcher overlay rendering inside or below Dynamic Island.
//

import AppKit
import SwiftUI

public struct OmniLauncherOverlayView: View {
    @ObservedObject var launcher = OmniLauncherEngine.shared
    @FocusState private var isFieldFocused: Bool

    public init() {}

    public var body: some View {
        if launcher.isVisible {
            VStack(spacing: 0) {
                // Top Search Bar
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    TextField("Search apps, calculate, or ask AI (?)...", text: $launcher.queryText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white)
                        .focused($isFieldFocused)

                    if !launcher.queryText.isEmpty {
                        Button {
                            launcher.queryText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.white.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        launcher.isVisible = false
                    } label: {
                        Text("Esc")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.1)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.75))

                Divider().background(Color.white.opacity(0.1))

                // Results List
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(launcher.results) { item in
                            launcherRow(item)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                }
                .frame(maxHeight: 260)
            }
            .frame(width: 480)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.92))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.25), Color.white.opacity(0.06)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    )
                    .shadow(color: Color.black.opacity(0.6), radius: 24, x: 0, y: 12)
            )
            .padding(.top, 8)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
            .onAppear {
                isFieldFocused = true
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

