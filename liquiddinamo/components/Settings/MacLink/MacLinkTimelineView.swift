//
//  MacLinkTimelineView.swift
//  LiquidDynamo
//
//  MacLink Timeline & Event Stream: Unified notification history, clipboard transfer log,
//  and file sync progress.
//

import AppKit
import SwiftUI

public struct MacLinkTimelineView: View {
    @ObservedObject private var bridge = MacLinkBridgeService.shared

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Timeline & Sync Stream")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Real-time telemetry and history of notifications, clipboard syncs, and file transfers")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.6))
                }

                VStack(spacing: 8) {
                    ForEach(bridge.syncEvents) { event in
                        syncEventCard(event)
                    }
                }
            }
            .padding(24)
        }
    }

    private func syncEventCard(_ event: PhoneSyncEventItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconColor(for: event.type).opacity(0.18))
                    .frame(width: 36, height: 36)

                Image(systemName: iconName(for: event.type))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(iconColor(for: event.type))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Text(formatTime(event.timestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(Color.white.opacity(0.4))
                }

                Text(event.detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color.white.opacity(0.65))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(white: 0.12).opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private func iconName(for type: PhoneSyncEventItem.SyncEventType) -> String {
        switch type {
        case .notification: return "bell.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .fileTransfer: return "arrow.up.arrow.down.circle.fill"
        }
    }

    private func iconColor(for type: PhoneSyncEventItem.SyncEventType) -> Color {
        switch type {
        case .notification: return .blue
        case .clipboard: return .orange
        case .fileTransfer: return .green
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

