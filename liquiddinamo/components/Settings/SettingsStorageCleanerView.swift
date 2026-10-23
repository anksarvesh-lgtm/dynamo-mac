//
//  SettingsStorageCleanerView.swift
//  LiquidDynamo
//
//  Storage Cleaner Control Center: Visual storage ring, 9 category cards,
//  safety checks, review drawers, and safe trashing with user confirmation.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsStorageCleanerView: View {
    @ObservedObject var cleaner = StorageCleanupManager.shared
    @Default(.storageCleanerStartupScan) private var startupScanEnabled

    @State private var selectedCategories: Set<StorageCleanupCategory> = Set(StorageCleanupCategory.allCases)
    @State private var reviewingCategory: StorageCleanupCategory? = nil
    @State private var showConfirmSheet: Bool = false
    @State private var cleaningMessage: String = ""

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // Header Banner
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Storage Cleaner")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Reclaim disk space safely. Scanned once at boot with zero background overhead.")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("Startup Scan", isOn: $startupScanEnabled)
                        .toggleStyle(.switch)
                        .font(.system(size: 12, design: .rounded))
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)

                // Hero Storage Wheel & Summary Banner
                heroStorageCard
                    .padding(.horizontal, 24)

                // Action Bar: Scan Again, Clean Selected, Select All
                actionBar
                    .padding(.horizontal, 24)

                // 9 Category Cards Grid
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reclaimable Categories")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 24)

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                        ForEach(StorageCleanupCategory.allCases) { cat in
                            categoryCard(for: cat)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer(minLength: 20)
            }
        }
        .sheet(isPresented: $showConfirmSheet) {
            confirmationDialog
        }
        .sheet(item: $reviewingCategory) { cat in
            reviewDrawer(for: cat)
        }
        .onAppear {
            if cleaner.latestResult == nil && !cleaner.isScanning {
                cleaner.performStartupScanIfNeeded()
            }
        }
    }

    // MARK: - Hero Storage Card & Donut Wheel
    private var heroStorageCard: some View {
        let res = cleaner.latestResult
        let reclaimableStr = res?.formattedTotalReclaimable ?? "Scanning…"
        let usedStr = res?.formattedVolumeUsed ?? "-- GB"
        let freeStr = res?.formattedVolumeFree ?? "-- GB"
        let totalStr = res?.formattedVolumeTotal ?? "-- GB"

        return HStack(spacing: 24) {
            // Segmented Donut Wheel
            ZStack {
                // Background Track
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 16)
                    .frame(width: 130, height: 130)

                // Used Slice
                Circle()
                    .trim(from: 0, to: CGFloat(res?.usedPercentage ?? 0.65))
                    .stroke(
                        LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))

                // Recoverable Slice (Highlighted in Emerald Green)
                Circle()
                    .trim(from: CGFloat(max(0, (res?.usedPercentage ?? 0.65) - (res?.reclaimablePercentage ?? 0.08))), to: CGFloat(res?.usedPercentage ?? 0.65))
                    .stroke(
                        LinearGradient(colors: [Color.green, Color.mint], startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: 18, lineCap: .round)
                    )
                    .frame(width: 130, height: 130)
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text(reclaimableStr)
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Recoverable")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            // Legend and Metrics
            VStack(alignment: .leading, spacing: 10) {
                Text("\(reclaimableStr) Available to Clean")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text("Safely removes redundant cache artifacts, stale build outputs, and obsolete downloads into macOS Trash.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    legendItem(color: Color.blue, label: "Used (\(usedStr))")
                    legendItem(color: Color.green, label: "Recoverable (\(reclaimableStr))")
                    legendItem(color: Color.gray.opacity(0.6), label: "Free (\(freeStr))")
                }
                .font(.system(size: 11, design: .rounded))

                Text("Volume Capacity: \(totalStr)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.25), Color.white.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
        )
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Action Bar
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                cleaner.scanAgain()
            } label: {
                HStack(spacing: 6) {
                    if cleaner.isScanning {
                        ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text("Scan Again")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8))
                )
            }
            .buttonStyle(.plain)
            .disabled(cleaner.isScanning || cleaner.isCleaning)

            Spacer()

            Button {
                showConfirmSheet = true
            } label: {
                HStack(spacing: 6) {
                    if cleaner.isCleaning {
                        ProgressView().scaleEffect(0.6).frame(width: 14, height: 14)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text("Clean Selected")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            LinearGradient(colors: [Color.green, Color.mint], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.3), lineWidth: 0.8))
                )
                .foregroundStyle(.black)
            }
            .buttonStyle(.plain)
            .disabled(cleaner.isCleaning || selectedCategories.isEmpty)
        }
    }

    // MARK: - Category Cards
    private func categoryCard(for category: StorageCleanupCategory) -> some View {
        let isSelected = selectedCategories.contains(category)
        let items = cleaner.latestResult?.itemsByCategory[category] ?? []
        let totalBytes = items.reduce(0) { $0 + $1.sizeBytes }
        let sizeFormatted = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(category.color.opacity(0.2))
                        .frame(width: 28, height: 28)
                    Image(systemName: category.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(category.color)
                }

                Spacer()

                Button {
                    if isSelected {
                        selectedCategories.remove(category)
                    } else {
                        selectedCategories.insert(category)
                    }
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16))
                        .foregroundStyle(isSelected ? category.color : .secondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(category.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)

                Text(category.subtitle)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Text(sizeFormatted)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(totalBytes > 0 ? category.color : .secondary)

                Spacer()

                if !items.isEmpty {
                    Button("Review") {
                        reviewingCategory = category
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.cyan)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.40))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            isSelected ? category.color.opacity(0.45) : Color.white.opacity(0.08),
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Review Drawer Sheet
    private func reviewDrawer(for category: StorageCleanupCategory) -> some View {
        let items = cleaner.latestResult?.itemsByCategory[category] ?? []

        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review \(category.rawValue)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("\(items.count) candidates located on disk")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    reviewingCategory = nil
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            List(items) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Text(item.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Text(item.formattedSize)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    Button {
                        cleaner.revealInFinder(path: item.path)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Show in Finder")
                }
                .padding(.vertical, 4)
            }

            Divider()

            HStack {
                Spacer()
                Button("Close") {
                    reviewingCategory = nil
                }
            }
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 500, minHeight: 380)
    }

    // MARK: - Safety Confirmation Dialog
    private var confirmationDialog: some View {
        let itemsToClean = cleaner.latestResult?.itemsByCategory
            .filter { selectedCategories.contains($0.key) }
            .flatMap { $0.value } ?? []
        let totalBytes = itemsToClean.reduce(0) { $0 + $1.sizeBytes }
        let totalStr = ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)

        return VStack(spacing: 20) {
            Image(systemName: "shield.lefthalf.filled.badge.checkmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.green)

            VStack(spacing: 6) {
                Text("Confirm Safe Cleanup")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text("LiquidDynamo will safely move \(itemsToClean.count) items (\(totalStr)) to your macOS Trash. No files are permanently destroyed.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    showConfirmSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Move to Trash") {
                    showConfirmSheet = false
                    Task {
                        _ = await cleaner.cleanItems(itemsToClean)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 420)
    }
}
