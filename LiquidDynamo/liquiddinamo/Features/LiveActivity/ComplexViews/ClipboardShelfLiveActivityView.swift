//
//  ClipboardShelfLiveActivityView.swift
//  LiquidDynamo
//
//  Step 3 Complex View Migration: Clipboard Shelf & Quick Drag Storage.
//  Provides both compact top band wing presentation and organic below-notch blooming droplet presentation.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

public struct ClipboardShelfLiveActivityView: View {
    @ObservedObject var shelfVM = ShelfStateViewModel.shared
    @ObservedObject var island = IslandController.shared

    public var isCompactWing: Bool = false
    public var isLeadingWing: Bool = true
    public var onDismiss: () -> Void = {}

    public init(
        isCompactWing: Bool = false,
        isLeadingWing: Bool = true,
        onDismiss: @escaping () -> Void = {}
    ) {
        self.isCompactWing = isCompactWing
        self.isLeadingWing = isLeadingWing
        self.onDismiss = onDismiss
    }

    private var itemCount: Int {
        shelfVM.items.count
    }

    private var topItemTitle: String {
        shelfVM.items.first?.displayName ?? "Empty Shelf"
    }

    private var topItemKindIcon: String {
        guard let item = shelfVM.items.first else { return "tray.fill" }
        switch item.kind {
        case .file:
            return "doc.fill"
        case .text:
            return "text.quote"
        case .link:
            return "link"
        }
    }

    private var tintColor: Color {
        Color.cyan
    }

    public var body: some View {
        if isCompactWing {
            compactWingLayout
        } else {
            bloomingDropletLayout
        }
    }

    // MARK: - 1. Compact Wing Presentation (Top Band)

    private var compactWingLayout: some View {
        HStack(spacing: 5) {
            if isLeadingWing {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tintColor)
                Text("Shelf (\(itemCount))")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } else {
                Text(topItemTitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                Image(systemName: topItemKindIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tintColor)
            }
        }
        .padding(.horizontal, 6)
        .avoidsNotch(id: isLeadingWing ? "ShelfWingL" : "ShelfWingR")
    }

    // MARK: - 2. Blooming Droplet Presentation (Below Notch)

    private var bloomingDropletLayout: some View {
        HStack(spacing: 12) {
            // Shelf Icon with Count Badge
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tintColor.opacity(0.2))
                    .frame(width: 32, height: 32)

                Image(systemName: topItemKindIcon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(tintColor)
                    .frame(width: 32, height: 32)

                if itemCount > 1 {
                    Text("\(itemCount)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(tintColor))
                        .offset(x: 4, y: -4)
                }
            }

            // Top Item Preview & Shelf Label
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("Clipboard Shelf")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(tintColor)
                    Text("• \(itemCount) items")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Text(topItemTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // Open Dashboard Shelf Button
            Button(action: {
                island.setExpanded(view: .shelf)
                onDismiss()
            }) {
                Text("Open")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tintColor))
            }
            .buttonStyle(.plain)

            // Dismiss Button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .avoidsNotch(id: "ClipboardShelfBloomingDroplet")
    }
}
