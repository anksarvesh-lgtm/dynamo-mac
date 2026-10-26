//
//  LiquidClipboardRegionView.swift
//  LiquidDynamo
//
//  Organic liquid region displaying clipboard history.
//

import AppKit
import Defaults
import SwiftUI

public struct LiquidClipboardRegionView: View {
    @ObservedObject private var service = ClipboardHistoryService.shared
    @Default(.showDashboardClipboard) private var showClipboard
    @State private var copiedId: UUID?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerView

            if !showClipboard {
                optInPromptView
            } else if service.accessDenied {
                permissionDeniedView
            } else if service.isScreenCaptured {
                screenCapturedShieldView
            } else if service.pinnedEntries.isEmpty && service.recentEntries.isEmpty {
                emptyDropView
            } else {
                entriesFlowView
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Permission Denied View
    private var permissionDeniedView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Needs permission")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.primary)
            }
            Text("LiquidDynamo needs permission to read copied text from other apps.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    service.openPrivacySettings()
                } label: {
                    Text("Open System Settings")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(OrganicDropletShape().fill(Color.orange.opacity(0.8)))
                }
                .buttonStyle(.plain)

                Button {
                    service.requestExplicitPasteboardAccess()
                } label: {
                    Text("Retry Access")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(OrganicDropletShape().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header
    private var headerView: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            Text("Clipboard")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.primary)

            let count = service.pinnedEntries.count + service.recentEntries.count
            if showClipboard && count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(OrganicDropletShape().fill(Color.white.opacity(0.12)))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if showClipboard && !service.recentEntries.isEmpty {
                Button {
                    service.clearHistory()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Clear")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help("Clear recent unpinned history")
            }
        }
    }

    // MARK: - Opt In Prompt
    private var optInPromptView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Clipboard history is private and opt-in. It keeps up to 5 text snippets in memory only, ignores password managers, and shields contents during screen recording.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Defaults[.showDashboardClipboard] = true
                service.start()
            } label: {
                Text("Enable Clipboard History")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(OrganicDropletShape().fill(Color.accentColor.opacity(0.8)))
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Shield View
    private var screenCapturedShieldView: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.yellow)
            Text("Clipboard shielded while screen is shared or recorded")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Empty Drop View
    private var emptyDropView: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.6))
            Text("Clipboard Empty")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(.vertical, 6)
    }

    // MARK: - Entries Flow
    private var entriesFlowView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !service.pinnedEntries.isEmpty {
                Text("PINNED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.yellow.opacity(0.8))
                    .padding(.horizontal, 4)
                ForEach(service.pinnedEntries) { entry in
                    entryRow(entry: entry)
                }
            }

            if !service.recentEntries.isEmpty {
                if !service.pinnedEntries.isEmpty {
                    Text("RECENT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }
                ForEach(service.recentEntries.prefix(25)) { entry in
                    entryRow(entry: entry)
                }
            }
        }
    }

    private func entryRow(entry: ClipboardEntry) -> some View {
        HStack(spacing: 8) {
            Button {
                service.copyToPasteboard(entry)
                copiedId = entry.id
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    if copiedId == entry.id {
                        copiedId = nil
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if copiedId == entry.id {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.green)
                    } else if entry.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                    } else {
                        Image(systemName: entry.iconSymbolName)
                            .font(.system(size: 9))
                            .foregroundColor(entry.iconColor)
                    }

                    Text(entry.previewText)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Spacer(minLength: 4)

                    if copiedId == entry.id {
                        Text("Copied!")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.green)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Pin / Unpin button
            Button {
                service.togglePin(entry)
            } label: {
                Image(systemName: entry.isPinned ? "pin.slash" : "pin")
                    .font(.system(size: 10))
                    .foregroundColor(entry.isPinned ? .yellow : .secondary.opacity(0.6))
                    .padding(3)
            }
            .buttonStyle(.plain)
            .help(entry.isPinned ? "Unpin item" : "Pin item")

            // Remove button
            Button {
                service.remove(entry)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(3)
            }
            .buttonStyle(.plain)
            .help("Remove entry")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            OrganicDropletShape()
                .fill(entry.isPinned ? Color.yellow.opacity(0.08) : Color.white.opacity(0.05))
        )
    }
}
