//
//  ScopaIslandCardView.swift
//  LiquidDynamo
//
//  Compact Liquid Glass card for Scopa (Storage Overview & Dev Cache Cleaner).
//  Displays genuine APFS storage statistics, developer cache breakdowns,
//  one-click scanning, and safe cleanup strictly via macOS Trash.
//

import AppKit
import Defaults
import Foundation
import SwiftUI

public struct ScopaIslandCardView: View {
    @ObservedObject private var manager = StorageCleanupManager.shared
    @ObservedObject private var coordinator = LiquidViewCoordinator.shared
    @State private var isCleaningInProgress: Bool = false
    @State private var cleanFeedbackText: String? = nil

    public init() {}

    private var storageStats: (usedGB: Double, totalGB: Double, freeGB: Double) {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(forPath: "/")
            let total = (attrs[.systemSize] as? NSNumber)?.int64Value ?? 0
            let free = (attrs[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
            let used = total - free
            return (
                usedGB: Double(used) / 1_000_000_000.0,
                totalGB: Double(total) / 1_000_000_000.0,
                freeGB: Double(free) / 1_000_000_000.0
            )
        } catch {
            return (usedGB: 0, totalGB: 0, freeGB: 0)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow

            // Storage Meter Bar
            storageProgressRow

            // Dev Cache Breakdown & Reclaimable Amount
            if let res = manager.latestResult {
                cacheBreakdownRow(res)
            } else if manager.isScanning {
                scanningRow
            } else {
                readyToScanRow
            }

            // Safe Cleanup / Action Bar
            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Color.accentColor)

            Text("SCOPA")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.6))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .layoutPriority(0)

            Spacer(minLength: 2)

            Button {
                withAnimation(IslandMotion.shared.springInteractive) {
                    coordinator.currentView = .cleaner
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(2)
            }
            .buttonStyle(.plain)
            .help("Open Full Storage Cleaner")
            .layoutPriority(1)
        }
    }

    // MARK: - Storage Meter Bar

    private var storageProgressRow: some View {
        let stats = storageStats
        let usedRatio = stats.totalGB > 0 ? max(0.0, min(1.0, stats.usedGB / stats.totalGB)) : 0.0

        return VStack(spacing: 3) {
            HStack {
                Text("\(Int(round(stats.usedGB))) GB used")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.9))

                Spacer()

                Text("\(Int(round(stats.freeGB))) GB free")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 4)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor, Color.cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * CGFloat(usedRatio), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Cache Breakdown

    private func cacheBreakdownRow(_ res: StorageCleanupResult) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Text(res.formattedTotalReclaimable)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.green)
                Text("reclaimable dev caches")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            Spacer(minLength: 4)

            // Category Mini Tag
            let devCount = res.itemsByCategory[.developer]?.count ?? 0
            if devCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "hammer.fill")
                        .font(.system(size: 7.5))
                    Text("\(devCount) caches")
                        .font(.system(size: 8, weight: .medium))
                }
                .foregroundStyle(Color.white.opacity(0.7))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(0.06)))
            }
        }
        .padding(.vertical, 1)
    }

    private var scanningRow: some View {
        HStack(spacing: 5) {
            ProgressView()
                .controlSize(.mini)
            Text("Scanning system caches…")
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.6))
        }
        .padding(.vertical, 2)
    }

    private var readyToScanRow: some View {
        HStack {
            Text("Caches ready for safe scan")
                .font(.system(size: 9))
                .foregroundStyle(Color.white.opacity(0.5))
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Action Row (Strictly Moves to macOS Trash)

    private var actionRow: some View {
        HStack(spacing: 6) {
            if let feedback = cleanFeedbackText {
                Text(feedback)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .lineLimit(1)
            } else if isCleaningInProgress {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("Moving to Trash…")
                        .font(.system(size: 8.5))
                        .foregroundStyle(Color.white.opacity(0.7))
                }
            } else {
                // One-click Safe Trash Cleanup
                if let res = manager.latestResult, res.totalReclaimableBytes > 0 {
                    Button {
                        performSafeCleanup()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 8))
                            Text("Clean to Trash")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.accentColor.opacity(0.75)))
                    }
                    .buttonStyle(.plain)
                    .help("Safely moves recoverable caches to macOS Trash (never permanently deleted)")
                }

                // Scan Button
                Button {
                    manager.scanAgain()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                        Text("Scan")
                            .font(.system(size: 8.5, weight: .medium))
                    }
                    .foregroundStyle(Color.white.opacity(0.8))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Scan APFS storage and developer caches")
            }

            Spacer(minLength: 0)
        }
    }

    private func performSafeCleanup() {
        guard !isCleaningInProgress else { return }
        isCleaningInProgress = true

        Task {
            let (count, bytes) = await manager.cleanSafeItems()
            let formatted = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            await MainActor.run {
                isCleaningInProgress = false
                cleanFeedbackText = "Cleaned \(formatted) to Trash"
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                cleanFeedbackText = nil
            }
        }
    }
}
