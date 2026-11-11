//
//  ClipboardHistoryIslandCardView.swift
//  LiquidDynamo
//
//  Expanded Dynamic Island card for Clipboard History.
//  Strictly enforces compact 28pt fixed rows, dynamic height hugging (up to 6-8 items),
//  privacy protections, and click-to-copy pasteboard integration.
//

import AppKit
import Defaults
import SwiftUI

public struct ClipboardHistoryIslandCardView: View {
    @ObservedObject private var service = ClipboardHistoryService.shared
    @Default(.showDashboardClipboard) private var showClipboard
    @State private var copiedId: UUID? = nil

    private let rowHeight: CGFloat = 28.0
    private let maxVisibleRows: Int = 6

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            if service.isScreenCaptured {
                screenCapturedNotice
            } else if service.pinnedEntries.isEmpty && service.recentEntries.isEmpty {
                emptyNotice
            } else {
                entriesList
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Header Row

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.accentColor)

            Text("CLIPBOARD")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.6))

            let totalCount = service.pinnedEntries.count + service.recentEntries.count
            if totalCount > 0 {
                Text("\(totalCount)")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }

            Spacer()

            if !service.recentEntries.isEmpty {
                Button {
                    service.clearHistory()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .padding(3)
                }
                .buttonStyle(.plain)
                .help("Clear recent history")
            }
        }
    }

    // MARK: - Compact 28pt Rows Hugging List

    private var entriesList: some View {
        let combined = (service.pinnedEntries + service.recentEntries).prefix(maxVisibleRows)

        return VStack(spacing: 3) {
            ForEach(combined) { entry in
                compactEntryRow(entry)
                    .frame(height: rowHeight)
            }
        }
    }

    private func compactEntryRow(_ entry: ClipboardEntry) -> some View {
        let isCopied = copiedId == entry.id

        return HStack(spacing: 6) {
            // Type icon or checkmark
            if isCopied {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(Color.green)
                    .frame(width: 14)
            } else if entry.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8.5))
                    .foregroundStyle(Color.yellow)
                    .frame(width: 14)
            } else {
                Image(systemName: entry.iconSymbolName)
                    .font(.system(size: 9))
                    .foregroundStyle(entry.iconColor)
                    .frame(width: 14)
            }

            // Single line preview truncated with ellipsis
            Text(entry.previewText)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 4)

            // Time ago label or Copied confirmation
            if isCopied {
                Text("Copied")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.green)
            } else {
                Text(timeAgoFormatted(entry.timestamp))
                    .font(.system(size: 8.5, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            // Pin toggle button
            Button {
                service.togglePin(entry)
            } label: {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 8))
                    .foregroundStyle(entry.isPinned ? Color.yellow : Color.white.opacity(0.35))
                    .padding(2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCopied ? Color.green.opacity(0.12) : (entry.isPinned ? Color.yellow.opacity(0.08) : Color.white.opacity(0.03)))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            service.copyToPasteboard(entry)
            copiedId = entry.id
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                if copiedId == entry.id {
                    copiedId = nil
                }
            }
        }
    }

    // MARK: - Notices

    private var screenCapturedNotice: some View {
        HStack(spacing: 5) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.yellow)
            Text("Shielded during screen capture")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.vertical, 4)
    }

    private var emptyNotice: some View {
        HStack(spacing: 5) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.4))
            Text("Clipboard Empty")
                .font(.system(size: 9.5))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .padding(.vertical, 4)
    }

    private func timeAgoFormatted(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else if seconds < 86400 {
            return "\(seconds / 3600)h ago"
        } else {
            return "\(seconds / 86400)d ago"
        }
    }
}
