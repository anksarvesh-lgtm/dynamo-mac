//
//  ToolbarMorePopoverView.swift
//  LiquidDynamo
//
//  Liquid Glass popover displaying overflowing feature shortcuts.
//  Provides instant search filtering, category badges, active indicators,
//  and one-click activation.
//

import AppKit
import Defaults
import SwiftUI

public struct ToolbarMorePopoverView: View {
    public let overflowItems: [ToolbarFeatureID]
    public let onSelect: (ToolbarFeatureID) -> Void

    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss

    public init(
        overflowItems: [ToolbarFeatureID],
        onSelect: @escaping (ToolbarFeatureID) -> Void
    ) {
        self.overflowItems = overflowItems
        self.onSelect = onSelect
    }

    private var filteredItems: [ToolbarFeatureID] {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            return overflowItems
        }
        let query = searchText.lowercased()
        return overflowItems.filter {
            $0.displayName.lowercased().contains(query) ||
            $0.category.rawValue.lowercased().contains(query)
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with search
            HStack(spacing: 8) {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.accentColor)

                Text("More Tools")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)

                Spacer()

                Text("\(overflowItems.count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
            }

            // Search input field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))

                TextField("Search tools…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.white)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            )

            // Grid of overflowing features
            if filteredItems.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.3))
                    Text("No matching tools found")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 6),
                            GridItem(.flexible(), spacing: 6),
                            GridItem(.flexible(), spacing: 6)
                        ],
                        spacing: 6
                    ) {
                        ForEach(filteredItems) { feature in
                            popoverToolButton(feature)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 220)
            }
        }
        .padding(12)
        .frame(width: 320)
        .background(
            ZStack {
                VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
                Color.black.opacity(0.85)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.08),
                            Color.black.opacity(0.3)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.4), radius: 12, x: 0, y: 6)
    }

    private func popoverToolButton(_ feature: ToolbarFeatureID) -> some View {
        Button {
            onSelect(feature)
        } label: {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: feature.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                        )
                }

                Text(feature.displayName)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(feature.helpText)
    }
}
