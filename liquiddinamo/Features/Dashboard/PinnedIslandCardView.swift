//
//  PinnedIslandCardView.swift
//  LiquidDynamo
//
//  Compact Liquid Glass card for Pinned items:
//  - Pinned favourite tools
//  - Pinned shelf files
//  - Pinned clipboard snippets
//  - Quick-access shortcuts
//

import AppKit
import Defaults
import SwiftUI

public struct PinnedIslandCardView: View {
    @ObservedObject private var shelf = ShelfStateViewModel.shared
    @ObservedObject private var clipboard = ClipboardHistoryService.shared
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared
    @Default(.toolbarConfig) private var toolbarConfig

    public init() {}

    private var pinnedTools: [ToolbarFeatureID] {
        toolbarConfig.pinnedFeatureIDs.filter { $0 != .home }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            // Pinned Tools Quick-Pills
            if !pinnedTools.isEmpty {
                pinnedToolsRow
            }

            // Pinned Files / Shelf Items
            if !shelf.items.isEmpty {
                pinnedFilesRow
            }

            // Pinned Clipboard Snippets
            if !clipboard.pinnedEntries.isEmpty {
                pinnedClipsRow
            }

            if pinnedTools.isEmpty && shelf.items.isEmpty && clipboard.pinnedEntries.isEmpty {
                emptyPinnedNotice
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "pin.fill")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(Color.yellow)

            Text("PINNED")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(0)

            let count = pinnedTools.count + shelf.items.count + clipboard.pinnedEntries.count
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                    .layoutPriority(1)
            }

            Spacer(minLength: 2)

            Button {
                withAnimation(IslandMotion.shared.springInteractive) {
                    coordinator.currentView = .shelf
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(2)
            }
            .buttonStyle(.plain)
            .help("Open Notch Shelf")
            .layoutPriority(1)
        }
    }

    // MARK: - Pinned Tools Row

    private var pinnedToolsRow: some View {
        HStack(spacing: 4) {
            ForEach(pinnedTools.prefix(3)) { tool in
                Button {
                    launchTool(tool)
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: tool.systemImage)
                            .font(.system(size: 8.5, weight: .semibold))
                        Text(tool.displayName)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.white.opacity(0.9))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.8))
                    )
                }
                .buttonStyle(.plain)
                .help(tool.helpText)
            }
        }
    }

    // MARK: - Pinned Files Row

    private var pinnedFilesRow: some View {
        VStack(spacing: 3) {
            ForEach(shelf.items.prefix(1)) { item in
                HStack(spacing: 5) {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.cyan)

                    Text(item.displayName)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 2)

                    Text(item.formattedFileSize)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
            }
        }
    }

    // MARK: - Pinned Clips Row

    private var pinnedClipsRow: some View {
        VStack(spacing: 3) {
            ForEach(clipboard.pinnedEntries.prefix(1)) { entry in
                HStack(spacing: 5) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.yellow)

                    Text(entry.previewText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Color.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 2)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.yellow.opacity(0.06)))
            }
        }
    }

    private var emptyPinnedNotice: some View {
        HStack(spacing: 4) {
            Text("Pin tools, files & clips for quick access")
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.45))
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func launchTool(_ tool: ToolbarFeatureID) {
        switch tool {
        case .colorDropper:
            ColorDropperTool.shared.sampleColor()
        case .keepAwake:
            coordinator.currentView = .keepAwake
        case .phoneBridge:
            coordinator.currentView = .phoneBridge
        case .powerload:
            coordinator.currentView = .powerload
        case .watcher:
            coordinator.currentView = .agent
        case .shelf:
            coordinator.currentView = .shelf
        case .calendar, .reminders, .timer, .stopwatch:
            coordinator.currentView = .calendar
        case .systemStats:
            coordinator.currentView = .stats
        case .deviceUniverse:
            coordinator.currentView = .bluetooth
        case .volumeControl, .brightnessControl, .audioControls:
            coordinator.currentView = .displaySound
        default:
            coordinator.currentView = .home
        }
    }
}
