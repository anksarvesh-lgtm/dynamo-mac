//
//  ToolbarEditSheetView.swift
//  LiquidDynamo
//
//  Customization interface for the Dynamic Island Liquid Glass Toolbar.
//  Supports drag-and-drop icon reordering, pin/unpin toggles, enable/disable switches,
//  factory defaults reset, and miniature live notch preview.
//

import AppKit
import Defaults
import SwiftUI

public struct ToolbarEditSheetView: View {
    @Default(.toolbarConfig) private var config
    @EnvironmentObject private var vm: LiquidViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var localOrder: [ToolbarFeatureID] = []
    @State private var localEnabled: Set<ToolbarFeatureID> = []
    @State private var localPinned: Set<ToolbarFeatureID> = []
    @State private var selectedCategory: ToolbarCategory? = nil

    public init() {}

    private var filteredFeatures: [ToolbarFeatureID] {
        if let cat = selectedCategory {
            return localOrder.filter { $0.category == cat }
        }
        return localOrder
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerBar

            Divider()
                .opacity(0.15)

            // Live Miniature Notch Preview
            miniatureNotchPreview
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            Divider()
                .opacity(0.15)

            // Category Filter Pills
            categoryPillFilter
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

            // Reorderable & Toggleable Feature List
            featureListView
                .frame(maxHeight: .infinity)

            Divider()
                .opacity(0.15)

            // Footer Actions
            footerBar
        }
        .frame(width: 520, height: 560)
        .background(
            ZStack {
                VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.85)
            }
        )
        .onAppear {
            localOrder = config.featureOrder
            localEnabled = config.enabledFeatureIDs
            localPinned = config.pinnedFeatureIDs
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text("Customize Island Toolbar")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                Text("Drag to reorder, pin high priority tools, and toggle visibility")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.6))
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Miniature Notch Preview

    private var miniatureNotchPreview: some View {
        let previewLayout = NotchToolbarLayoutEngine.shared.computeLayout(
            totalWidth: 460,
            geometry: vm.geometry,
            config: ToolbarConfig(
                version: 1,
                featureOrder: localOrder,
                enabledFeatureIDs: localEnabled,
                pinnedFeatureIDs: localPinned
            )
        )

        return VStack(spacing: 6) {
            HStack {
                Text("LIVE NOTCH PREVIEW")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.5))

                Spacer()

                if vm.geometry.hasPhysicalNotch {
                    Text("Hardware Notch Safe")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.green.opacity(0.8))
                } else {
                    Text("Symmetrical Display")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color.cyan.opacity(0.8))
                }
            }

            // Preview Island Container
            HStack(spacing: 0) {
                // Left Safe Region
                HStack(spacing: 4) {
                    ForEach(previewLayout.leftItems) { item in
                        miniatureIcon(item.systemImage, isHome: item == .home)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Central Notch Hole
                if vm.geometry.hasPhysicalNotch {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.black)
                        .frame(width: max(80, vm.geometry.rawNotchWidth * 0.45), height: 16)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 4, height: 4)
                        )
                } else {
                    Color.clear.frame(width: 8, height: 16)
                }

                // Right Safe Region
                HStack(spacing: 4) {
                    ForEach(previewLayout.rightItems) { item in
                        miniatureIcon(item.systemImage, isHome: false)
                    }

                    if previewLayout.showMoreButton {
                        miniatureIcon("ellipsis", isHome: false, isMore: true)
                    }

                    miniatureIcon("slider.horizontal.3", isHome: false, isEdit: true)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }

    private func miniatureIcon(_ icon: String, isHome: Bool, isMore: Bool = false, isEdit: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(isHome ? Color.accentColor : (isMore ? Color.orange : (isEdit ? Color.cyan : Color.white.opacity(0.85))))
            .frame(width: 16, height: 16)
            .background(Circle().fill(Color.white.opacity(0.08)))
    }

    // MARK: - Category Filter

    private var categoryPillFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryFilterPill(title: "All", category: nil)
                ForEach(ToolbarCategory.allCases) { cat in
                    categoryFilterPill(title: cat.rawValue, category: cat)
                }
            }
        }
    }

    private func categoryFilterPill(title: String, category: ToolbarCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.6))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color.white.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Feature List

    private var featureListView: some View {
        List {
            ForEach(filteredFeatures) { feature in
                featureRow(feature)
                    .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            .onMove(perform: moveFeatures)
        }
        .listStyle(.plain)
    }

    private func featureRow(_ feature: ToolbarFeatureID) -> some View {
        let isEnabled = localEnabled.contains(feature)
        let isPinned = localPinned.contains(feature)

        return HStack(spacing: 10) {
            // Drag Handle (suppressed for fixed Home)
            if feature.isFixed {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.3))
                    .frame(width: 14)
            } else {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .frame(width: 14)
            }

            // Feature Icon
            Image(systemName: feature.systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.35))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.06)))

            // Feature Info
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(feature.displayName)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(isEnabled ? Color.white : Color.white.opacity(0.4))

                    if feature.isFixed {
                        Text("Permanent")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    }
                }

                Text(feature.category.rawValue)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.4))
            }

            Spacer()

            // Pin / Unpin Button
            if !feature.isFixed {
                Button {
                    if isPinned {
                        localPinned.remove(feature)
                    } else {
                        localPinned.insert(feature)
                    }
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(isPinned ? Color.yellow : Color.white.opacity(0.3))
                        .padding(4)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "Pinned to toolbar" : "Click to pin")
            }

            // Enable / Disable Toggle
            if !feature.isFixed {
                Toggle("", isOn: Binding(
                    get: { localEnabled.contains(feature) },
                    set: { enabled in
                        if enabled {
                            localEnabled.insert(feature)
                        } else {
                            localEnabled.remove(feature)
                        }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isEnabled ? 0.04 : 0.015))
        )
    }

    private func moveFeatures(from source: IndexSet, to destination: Int) {
        // Prevent moving Home away from index 0
        var items = localOrder
        items.move(fromOffsets: source, toOffset: destination)
        if let homeIndex = items.firstIndex(of: .home), homeIndex != 0 {
            items.remove(at: homeIndex)
            items.insert(.home, at: 0)
        }
        localOrder = items
    }

    // MARK: - Footer Bar

    private var footerBar: some View {
        HStack {
            Button("Reset to Defaults") {
                localOrder = ToolbarConfig.defaultFeatureOrder
                localEnabled = ToolbarConfig.defaultEnabledIDs
                localPinned = ToolbarConfig.defaultPinnedIDs
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color.red.opacity(0.85))

            Spacer()

            Button("Cancel") {
                dismiss()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(Color.white.opacity(0.7))

            Button("Save Layout") {
                config = ToolbarConfig(
                    version: 1,
                    featureOrder: localOrder,
                    enabledFeatureIDs: localEnabled,
                    pinnedFeatureIDs: localPinned
                )
                dismiss()
            }
            .controlSize(.regular)
            .tint(Color.accentColor)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
