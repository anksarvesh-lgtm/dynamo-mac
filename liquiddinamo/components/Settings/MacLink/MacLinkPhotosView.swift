//
//  MacLinkPhotosView.swift
//  LiquidDynamo
//
//  MacLink Photos & Media: Camera roll gallery grid, auto-backup to Mac Pictures,
//  and drag-and-drop photo transfer.
//

import AppKit
import SwiftUI

public struct MacLinkPhotosView: View {
    @ObservedObject private var bridge = MacLinkBridgeService.shared
    @State private var autoBackupEnabled: Bool = true
    @State private var selectedFilter: String = "All Photos"

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)
    ]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Top Toolbar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phone Camera Roll & Photos")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("\(bridge.recentPhotos.count) media items • Synced via high-speed USB/Wi-Fi")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                }

                Spacer()

                HStack(spacing: 12) {
                    Toggle("Auto-Backup to Mac", isOn: $autoBackupEnabled)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.8))

                    Button {
                        bridge.triggerPhotoBackup()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                            Text("Sync Now")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.blue))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .background(Color(white: 0.10).opacity(0.6))

            Divider().opacity(0.12)

            // Photos Grid
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(bridge.recentPhotos) { photo in
                        photoCard(photo)
                    }
                }
                .padding(18)
            }
        }
    }

    private func photoCard(_ photo: PhonePhotoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 110)

                Image(systemName: "photo.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(photo.filename)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                Text(formatSize(photo.sizeBytes))
                    .font(.system(size: 9.5))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.12).opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
        )
    }

    private func formatSize(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1_000_000.0
        return String(format: "%.1f MB", mb)
    }
}

