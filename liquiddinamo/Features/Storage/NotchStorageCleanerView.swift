//
//  NotchStorageCleanerView.swift
//  LiquidDynamo
//
//  Immersive full-width Storage Purge view for the expanded dynamic island / notch.
//  Faithfully incorporates Purge's categories, safety labels (Safe to Clean / Check First),
//  "where your space went" breakdown bar, Full Disk Access onboarding, and trash-only engine.
//

import AppKit
import Defaults
import SwiftUI

public struct NotchStorageCleanerView: View {
    @ObservedObject var cleaner = StorageCleanupManager.shared
    @State private var expandedCategory: StorageCleanupCategory? = nil
    @State private var showCleanSuccessBanner: Bool = false
    @State private var cleanedBytesReport: Int64 = 0
    @State private var showConfirmationSheet: Bool = false
    @State private var pendingCleanAction: (() -> Void)? = nil
    @State private var confirmationMessage: String = ""

    public init() {}

    public var body: some View {
        let res = cleaner.latestResult
        let reclaimable = res?.totalReclaimableBytes ?? 0
        let reclaimableStr = res?.formattedTotalReclaimable ?? (cleaner.isScanning ? "Scanning…" : "0 B")
        let categories = res?.categoriesWithReclaimableItems ?? []

        VStack(spacing: 11) {
            // Top Header: Title, Metric, Scan & Purge Action
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(colors: [Color.green.opacity(0.4), Color.mint.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                            )
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(Color.mint.opacity(0.6), lineWidth: 1))

                        Image(systemName: "sparkles")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Color.mint)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Storage Purge")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)

                            if !cleaner.hasFDA {
                                Text("Limited Scan")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(Color.orange.opacity(0.25)))
                                    .foregroundStyle(Color.orange)
                            }
                        }

                        Text(cleaner.isScanning ? "Scanning macOS caches & dev artifacts…" : "\(reclaimableStr) cleanable across \(categories.count) categories")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    // Rescan button
                    Button {
                        cleaner.scanAgain()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10, weight: .bold))
                            Text("Rescan")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.10))
                                .overlay(Capsule().stroke(Color.white.opacity(0.20), lineWidth: 0.6))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(cleaner.isScanning || cleaner.isCleaning)

                    // Clean Safe Items Button
                    if reclaimable > 0 {
                        Button {
                            confirmationMessage = "Move all Safe to Clean cache and build files to Trash?"
                            pendingCleanAction = {
                                Task {
                                    let (count, bytes) = await cleaner.cleanSafeItems()
                                    if count > 0 {
                                        cleanedBytesReport = bytes
                                        showCleanSuccessBanner = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                            showCleanSuccessBanner = false
                                        }
                                    }
                                }
                            }
                            showConfirmationSheet = true
                        } label: {
                            HStack(spacing: 5) {
                                if cleaner.isCleaning {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "checkmark.shield.fill")
                                        .font(.system(size: 10, weight: .bold))
                                }

                                Text(cleaner.isCleaning ? "Cleaning…" : "Clean Safe Items")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5.5)
                            .background(
                                Capsule()
                                    .fill(
                                        LinearGradient(colors: [Color.green, Color.mint], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .shadow(color: Color.green.opacity(0.4), radius: 6)
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(cleaner.isCleaning)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // FDA Onboarding Banner (if Full Disk Access not yet granted)
            if !cleaner.hasFDA {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.orange)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Full Disk Access Required for Deep Scan")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text("Enables App Uninstaller leftovers and full duplicate file scanning without per-folder prompts.")
                            .font(.system(size: 9.5, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        cleaner.requestFullDiskAccess()
                    } label: {
                        Text("Grant Access")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.orange))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.orange.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35), lineWidth: 0.75))
                )
                .padding(.horizontal, 14)
            }

            // Success celebration banner
            if showCleanSuccessBanner {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.green)
                        .font(.system(size: 12))
                    Text("Successfully moved \(ByteCountFormatter.string(fromByteCount: cleanedBytesReport, countStyle: .file)) to Trash!")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.25))
                        .overlay(Capsule().stroke(Color.green.opacity(0.50), lineWidth: 0.75))
                )
                .transition(.scale.combined(with: .opacity))
            }

            // Where your space went: Multi-segmented Overview Breakdown Bar
            if let result = res {
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        let w = geo.size.width
                        let total = max(1, CGFloat(result.volumeTotal))
                        let sysW = max(3, (CGFloat(result.systemBytes) / total) * w)
                        let appW = max(3, (CGFloat(result.appsBytes) / total) * w)
                        let recW = max(4, (CGFloat(result.totalReclaimableBytes) / total) * w)
                        let freeW = max(4, (CGFloat(result.volumeFree) / total) * w)

                        HStack(spacing: 2) {
                            // System space
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.gray.opacity(0.65))
                                .frame(width: sysW)

                            // Applications
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [Color.blue.opacity(0.85), Color.indigo.opacity(0.85)], startPoint: .leading, endPoint: .trailing))
                                .frame(width: appW)

                            // Cleanable / Reclaimable
                            RoundedRectangle(cornerRadius: 3)
                                .fill(LinearGradient(colors: [Color.green, Color.mint], startPoint: .leading, endPoint: .trailing))
                                .frame(width: recW)

                            // Free space
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.12))
                                .frame(width: freeW)
                        }
                    }
                    .frame(height: 7)

                    HStack {
                        HStack(spacing: 4) {
                            Circle().fill(Color.gray.opacity(0.8)).frame(width: 5.5, height: 5.5)
                            Text("System")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 4) {
                            Circle().fill(Color.blue).frame(width: 5.5, height: 5.5)
                            Text("Apps: \(result.formattedVolumeUsed)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Circle().fill(Color.mint).frame(width: 5.5, height: 5.5)
                            Text("Cleanable: \(result.formattedTotalReclaimable)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.mint)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Circle().fill(Color.white.opacity(0.3)).frame(width: 5.5, height: 5.5)
                            Text("Free: \(result.formattedVolumeFree)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
            }

            // Categories List
            if categories.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.green)
                    Text("Your Mac is spotless!")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("No unnecessary cache files or junk found.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(categories) { cat in
                            categoryCard(for: cat, in: res)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 220)
            }

            // Bottom Info Bar
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.green)
                    Text("Allowlist deletion only • Items moved to Trash • Never emptied")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    SettingsWindowController.shared.showWindow()
                } label: {
                    HStack(spacing: 3) {
                        Text("Open Full Settings")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 9.5))
                    }
                    .foregroundStyle(Color.mint)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
                )
        )
        .padding(.horizontal, 8)
        .confirmationDialog("Confirm Trash Action", isPresented: $showConfirmationSheet, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) {
                pendingCleanAction?()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
        .onAppear {
            if cleaner.latestResult == nil && !cleaner.isScanning {
                cleaner.performStartupScanIfNeeded()
            }
        }
    }

    @ViewBuilder
    private func categoryCard(for category: StorageCleanupCategory, in result: StorageCleanupResult?) -> some View {
        let isExpanded = expandedCategory == category
        let items = result?.itemsByCategory[category] ?? []
        let catTotal = result?.formattedTotal(for: category) ?? "0 B"

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Category Icon
                ZStack {
                    Circle()
                        .fill(category.color.opacity(0.20))
                        .frame(width: 26, height: 26)
                        .overlay(Circle().stroke(category.color.opacity(0.40), lineWidth: 0.75))

                    Image(systemName: category.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(category.color)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(category.rawValue)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(category.subtitle)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(catTotal)
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(category.color)

                // Clean Category Button
                Button {
                    confirmationMessage = "Move all \(items.count) item(s) in \(category.rawValue) to Trash?"
                    pendingCleanAction = {
                        Task {
                            await cleaner.cleanCategory(category)
                        }
                    }
                    showConfirmationSheet = true
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                        Text("Clean")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.10))
                            .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)

                // Expand Disclosure
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        expandedCategory = isExpanded ? nil : category
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isExpanded ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
            )

            if isExpanded {
                VStack(spacing: 3) {
                    ForEach(items.prefix(12)) { item in
                        HStack(spacing: 8) {
                            // Safety Tier Badge
                            HStack(spacing: 3) {
                                Image(systemName: item.safetyTier.symbolName)
                                    .font(.system(size: 8))
                                Text(item.safetyTier == .safeToClean ? "Safe" : "Check")
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                            }
                            .foregroundStyle(item.safetyTier.color)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(item.safetyTier.color.opacity(0.15))
                            )

                            // Duplicate Badge if applicable
                            if item.isDuplicate {
                                Text("Duplicate")
                                    .font(.system(size: 7.5, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.yellow)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.yellow.opacity(0.20)))
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.name)
                                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.95))
                                    .lineLimit(1)

                                if let detail = item.detail {
                                    Text(detail)
                                        .font(.system(size: 9, design: .rounded))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text(item.formattedSize)
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Button {
                                cleaner.revealInFinder(path: item.path)
                            } label: {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Reveal in Finder")

                            Button {
                                confirmationMessage = "Move \(item.name) to Trash?"
                                pendingCleanAction = {
                                    Task {
                                        await cleaner.cleanItems([item])
                                    }
                                }
                                showConfirmationSheet = true
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8.5))
                                    .foregroundStyle(Color.red.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                            .help("Move to Trash")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.black.opacity(0.35))
                        )
                    }

                    if items.count > 12 {
                        Text("+ \(items.count - 12) more items")
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.top, 4)
                .padding(.leading, 14)
            }
        }
    }
}
