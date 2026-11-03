//
//  LiquidUnifiedDetailContainerView.swift
//  LiquidDynamo
//
//  Adaptive Utility Detail Expansion:
//  - Replaces traditional popups/floating panels with in-place liquid expansion
//  - Persistent Connected Devices section remains visible at top
//  - Back button `<` smoothly morphs container back to 3-slide carousel
//  - 3-column structured architecture for Clipboard, Dropper, Scopa, Powerload, Phone Bridge, Watcher, and Devices
//

import AppKit
import Combine
import SwiftUI

public enum ExpandedMode: Equatable {
    case none
    case clipboard
    case dropper
    case scopa
    case powerload
    case phoneBridge
    case watcher
    case device(String)
}

public struct LiquidUnifiedDetailContainerView: View {
    public let mode: ExpandedMode
    public var onDismiss: () -> Void

    @ObservedObject var clipboardService = ClipboardHistoryService.shared
    @ObservedObject var shelfState = ShelfStateViewModel.shared
    @ObservedObject var colorDropper = ColorDropperTool.shared
    @ObservedObject var cleaner = StorageCleanupManager.shared
    @ObservedObject var powerloadEngine = PowerloadDownloadEngine.shared
    @ObservedObject var phoneBridgeEngine = PhoneBridgeEngine.shared
    @ObservedObject var watcherService = WatcherService.shared
    @ObservedObject var deviceMonitor = DeviceMonitor.shared
    @ObservedObject var memoryRegistry = DeviceMemoryRegistry.shared

    // Detail UI state
    @State private var searchText: String = ""
    @State private var selectedCategoryIndex: Int = 0
    @State private var copiedItemId: UUID? = nil
    @State private var hoveredAction: String? = nil

    public init(mode: ExpandedMode, onDismiss: @escaping () -> Void) {
        self.mode = mode
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 8) {
            switch mode {
            case .clipboard:
                clipboardDetailView
            case .dropper:
                dropperDetailView
            case .scopa:
                scopaDetailView
            case .powerload:
                powerloadDetailView
            case .phoneBridge:
                phoneBridgeDetailView
            case .watcher:
                watcherDetailView
            case .device(let key):
                deviceDetailView(key: key)
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            // Organic Dark Liquid Glass Boundary
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LiquidColorTokens.primaryGlass.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                stops: [
                                    .init(color: LiquidColorTokens.silverHighlight.opacity(0.35), location: 0.0),
                                    .init(color: LiquidColorTokens.tealRefraction.opacity(0.40), location: 0.5),
                                    .init(color: LiquidColorTokens.champagneReflection.opacity(0.20), location: 1.0)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                )
                .shadow(color: LiquidColorTokens.deepShadow.opacity(0.7), radius: 16, x: 0, y: 8)
        )
    }

    // =========================================================================
    // MARK: - CLIPBOARD DETAIL VIEW (Matches Reference Design Perfectly)
    // =========================================================================

    @ViewBuilder
    private var clipboardDetailView: some View {
        let totalCount = clipboardService.recentEntries.count + clipboardService.pinnedEntries.count
        let itemsCount = totalCount > 0 ? totalCount : 25

        VStack(spacing: 10) {
            // Header Row: Back Button < | Icon | Title | Search | Actions
            HStack(spacing: 10) {
                // Back to Carousel Button
                backButton

                // Glowing Cyan Icon & Title
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.cyan.opacity(0.22))
                            .frame(width: 32, height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.cyan.opacity(0.65), lineWidth: 1.0)
                            )
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.cyan)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Clipboard")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.primaryText)

                        HStack(spacing: 4) {
                            Text("\(itemsCount) Items")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidColorTokens.secondaryText)
                            Text("•")
                                .font(.system(size: 8))
                                .foregroundStyle(LiquidColorTokens.mutedText)
                            Circle()
                                .fill(LiquidColorTokens.emerald)
                                .frame(width: 5, height: 5)
                            Text("Synced")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(LiquidColorTokens.emerald)
                        }
                    }
                }

                Spacer()

                // Capsule Search Bar
                searchBar(placeholder: "Search clipboard...")
                    .frame(maxWidth: 240)

                // Top Actions: Pin Filter, Trash / Clear, More Menu
                HStack(spacing: 6) {
                    actionCircleButton(icon: "pin", action: {
                        selectedCategoryIndex = (selectedCategoryIndex == 4 ? 0 : 4)
                    })
                    actionCircleButton(icon: "trash", action: {
                        clipboardService.clearHistory()
                    })
                    actionCircleButton(icon: "ellipsis", action: {
                        // Options menu
                    })
                }
            }
            .padding(.horizontal, 4)

            // 3-Column Body: Left Categories | Center Feed | Right Hero Card
            HStack(alignment: .top, spacing: 10) {
                // Column 1: Left Categories Rail
                VStack(spacing: 5) {
                    categoryPill(index: 0, icon: "doc.on.clipboard", title: "All Items", count: "\(itemsCount)")
                    categoryPill(index: 1, icon: "doc.text", title: "Text", count: "18")
                    categoryPill(index: 2, icon: "link", title: "Links", count: "4")
                    categoryPill(index: 3, icon: "photo", title: "Images", count: "2")
                    categoryPill(index: 4, icon: "pin", title: "Pinned", count: "\(clipboardService.pinnedEntries.count > 0 ? "\(clipboardService.pinnedEntries.count)" : "3")")
                    Spacer(minLength: 0)
                }
                .frame(width: 120)

                // Column 2: Center Item Feed
                VStack(spacing: 6) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 5) {
                            // Display filtered items or sample demonstration entries if empty
                            if filteredClipboardItems.isEmpty {
                                defaultClipboardItemsDemo
                            } else {
                                ForEach(filteredClipboardItems) { entry in
                                    clipboardItemCard(entry: entry)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                .frame(maxWidth: .infinity)

                // Column 3: Right Preview Hero Card
                VStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LiquidColorTokens.secondaryGlass.opacity(0.65))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                            )

                        VStack(spacing: 6) {
                            // 3D Glass Clipboard Icon
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.cyan.opacity(0.35), Color.blue.opacity(0.15)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.white.opacity(0.30), lineWidth: 1.0)
                                    )
                                    .shadow(color: Color.cyan.opacity(0.3), radius: 6)

                                Image(systemName: "doc.on.clipboard.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(Color.white)
                            }

                            Text("Clipboard")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(LiquidColorTokens.primaryText)

                            Text("Capture, manage and reuse your copied content across apps.")
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(LiquidColorTokens.secondaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 6)

                            // 3 Stat Pills
                            HStack(spacing: 4) {
                                statPill(icon: "square.stack.3d.up", text: "\(itemsCount) Items")
                                statPill(icon: "pin", text: "\(clipboardService.pinnedEntries.count > 0 ? "\(clipboardService.pinnedEntries.count)" : "3") Pinned")
                                statPill(icon: "arrow.triangle.2.circlepath", text: "Synced")
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 6)
                    }
                }
                .frame(width: 190)
            }

            // Bottom Pagination Dots
            paginationDots
        }
    }

    private var filteredClipboardItems: [ClipboardEntry] {
        var items: [ClipboardEntry] = []
        if selectedCategoryIndex == 4 {
            items = clipboardService.pinnedEntries
        } else if selectedCategoryIndex == 1 {
            items = clipboardService.recentEntries.filter { $0.type == .text }
        } else if selectedCategoryIndex == 2 {
            items = clipboardService.recentEntries.filter { $0.type == .url }
        } else if selectedCategoryIndex == 3 {
            items = clipboardService.recentEntries.filter { $0.type == .image }
        } else {
            items = clipboardService.pinnedEntries + clipboardService.recentEntries
        }
        if !searchText.isEmpty {
            items = items.filter { $0.previewText.localizedCaseInsensitiveContains(searchText) }
        }
        return items
    }

    // Default reference mockup entries when clipboard service has fewer entries
    @ViewBuilder
    private var defaultClipboardItemsDemo: some View {
        sampleFeedCard(
            icon: "link",
            title: "https://github.com/anksarvesh-lgtm/dynamo-mac",
            subtitle: "Copied 2 min ago • Link"
        )
        sampleFeedCard(
            icon: "doc.text",
            title: "MCP - Antigravity UI Research • Liquid Glass Design • Device Integration",
            subtitle: "Copied 16 min ago • Text"
        )
        sampleFeedCard(
            icon: "photo",
            title: "UI_Concept_v3.png",
            subtitle: "4.2 MB • 28 min ago • Image"
        )
    }

    @ViewBuilder
    private func sampleFeedCard(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.cyan)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidColorTokens.primaryText)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(LiquidColorTokens.mutedText)
            }

            Spacer()

            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidColorTokens.secondaryText)
                Image(systemName: "pin")
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidColorTokens.secondaryText)
                Image(systemName: "ellipsis")
                    .font(.system(size: 10))
                    .foregroundStyle(LiquidColorTokens.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LiquidColorTokens.secondaryGlass.opacity(0.55))
        )
    }

    @ViewBuilder
    private func clipboardItemCard(entry: ClipboardEntry) -> some View {
        let isCopied = (copiedItemId == entry.id)
        HStack(spacing: 8) {
            Image(systemName: entry.iconSymbolName)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(entry.iconColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.previewText)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(LiquidColorTokens.primaryText)
                    .lineLimit(1)

                Text(isCopied ? "Copied to clipboard!" : entry.detailText)
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(isCopied ? LiquidColorTokens.emerald : LiquidColorTokens.mutedText)
            }

            Spacer()

            HStack(spacing: 6) {
                Button {
                    clipboardService.copyToPasteboard(entry)
                    copiedItemId = entry.id
                    Task {
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        if copiedItemId == entry.id { copiedItemId = nil }
                    }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(isCopied ? LiquidColorTokens.emerald : LiquidColorTokens.secondaryText)
                }
                .buttonStyle(.plain)

                Button {
                    clipboardService.togglePin(entry)
                } label: {
                    Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(entry.isPinned ? Color.orange : LiquidColorTokens.secondaryText)
                }
                .buttonStyle(.plain)

                Button {
                    clipboardService.remove(entry)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(LiquidColorTokens.mutedText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isCopied ? LiquidColorTokens.emerald.opacity(0.15) : LiquidColorTokens.secondaryGlass.opacity(0.55))
        )
    }

    // =========================================================================
    // MARK: - DROPPER DETAIL VIEW
    // =========================================================================

    @ViewBuilder
    private var dropperDetailView: some View {
        VStack(spacing: 10) {
            // Header Row
            HStack(spacing: 10) {
                backButton

                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.orange.opacity(0.22))
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.orange.opacity(0.65), lineWidth: 1.0))
                        Image(systemName: "eyedropper.halffull")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Dropper")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.primaryText)

                        Text("Color Sampling & Temporary Shelf")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.secondaryText)
                    }
                }

                Spacer()

                Button {
                    colorDropper.sampleColor()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "eyedropper")
                        Text("Pick Screen Color")
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.orange.opacity(0.35))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Body: Staged shelf & Eyedropper Preview
            HStack(alignment: .top, spacing: 10) {
                // Shelf Staging Files
                VStack(alignment: .leading, spacing: 6) {
                    Text("Temporary File Shelf (\(shelfState.items.count))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(LiquidColorTokens.secondaryText)

                    if shelfState.items.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "tray.and.arrow.down")
                                .font(.system(size: 24))
                                .foregroundStyle(LiquidColorTokens.mutedText)
                            Text("Drag & Drop files here to stage them")
                                .font(.system(size: 10, design: .rounded))
                                .foregroundStyle(LiquidColorTokens.mutedText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: 140)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(shelfState.items) { item in
                                    ShelfItemView(item: item)
                                        .frame(width: 90)
                                }
                            }
                        }
                        .frame(height: 140)
                    }
                }
                .frame(maxWidth: .infinity)

                // Color Swatch & Metrics Card
                VStack(spacing: 8) {
                    let swatchColor = colorDropper.currentColor?.swiftUIColor ?? Color.orange
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(swatchColor.opacity(0.25))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(swatchColor, lineWidth: 1.2))

                        VStack(spacing: 4) {
                            Circle()
                                .fill(swatchColor)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1.0))

                            Text(colorDropper.currentColor?.hex ?? "#00D982")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(LiquidColorTokens.primaryText)

                            Button("Copy HEX") {
                                if let hex = colorDropper.currentColor?.hex {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(hex, forType: .string)
                                }
                            }
                            .font(.system(size: 9, weight: .bold))
                            .buttonStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .padding(8)
                    }
                    .frame(width: 140, height: 140)
                }
            }

            paginationDots
        }
    }

    // =========================================================================
    // MARK: - SCOPA DETAIL VIEW
    // =========================================================================

    @ViewBuilder
    private var scopaDetailView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                backButton

                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.teal.opacity(0.22))
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.teal.opacity(0.65), lineWidth: 1.0))
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.teal)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Scopa")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.primaryText)

                        Text("Smart System Storage Cleaner")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.secondaryText)
                    }
                }

                Spacer()

                Button {
                    cleaner.scanAgain()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Rescan")
                    }
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.teal.opacity(0.35))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            // Scopa Storage Cleaner View Integration
            NotchStorageCleanerView()
                .frame(maxHeight: 180)

            paginationDots
        }
    }

    // =========================================================================
    // MARK: - POWERLOAD DETAIL VIEW
    // =========================================================================

    @ViewBuilder
    private var powerloadDetailView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                backButton

                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.blue.opacity(0.22))
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.blue.opacity(0.65), lineWidth: 1.0))
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.blue)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Powerload")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.primaryText)

                        Text("Multi-Network Turbo Download Accelerator")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.secondaryText)
                    }
                }

                Spacer()
            }

            PowerloadView()
                .frame(maxHeight: 220)

            paginationDots
        }
    }

    // =========================================================================
    // MARK: - PHONE BRIDGE DETAIL VIEW
    // =========================================================================

    @ViewBuilder
    private var phoneBridgeDetailView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                backButton

                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LiquidColorTokens.emerald.opacity(0.22))
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(LiquidColorTokens.emerald.opacity(0.65), lineWidth: 1.0))
                        Image(systemName: "phone.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(LiquidColorTokens.emerald)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Phone Bridge")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.primaryText)

                        let connectedDev = phoneBridgeEngine.selectedDevice
                        Text(connectedDev?.displayName ?? "realme 8i • Connected via ADB")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.secondaryText)
                    }
                }

                Spacer()

                Button {
                    PhoneBridgeWindowController.shared.showWindow()
                } label: {
                    Text("In-App Manager")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(LiquidColorTokens.emerald.opacity(0.35))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            PhoneBridgeView()
                .frame(maxHeight: 220)

            paginationDots
        }
    }

    // =========================================================================
    // MARK: - WATCHER DETAIL VIEW
    // =========================================================================

    @ViewBuilder
    private var watcherDetailView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                backButton

                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(red: 0.58, green: 0.40, blue: 0.98).opacity(0.22))
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color(red: 0.58, green: 0.40, blue: 0.98).opacity(0.65), lineWidth: 1.0))
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color(red: 0.58, green: 0.40, blue: 0.98))
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Watcher")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.primaryText)

                        Text("AI Agent Monitor & System Telemetry")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.secondaryText)
                    }
                }

                Spacer()
            }

            WatcherDetailCard()
                .frame(maxHeight: 200)

            paginationDots
        }
    }

    // =========================================================================
    // MARK: - DEVICE DETAIL VIEW (MagSafe 3 / Bluetooth Audio)
    // =========================================================================

    @ViewBuilder
    private func deviceDetailView(key: String) -> some View {
        let dev = deviceMonitor.activeDevices[key] ?? DeviceIdentity(
            stableKey: key,
            kind: key.contains("magsafe") ? .charger : .headphones,
            displayName: key.contains("magsafe") ? "MagSafe 3 Charger" : "realme Buds Wireless",
            vendor: "Connected",
            model: "Device",
            connectionType: key.contains("magsafe") ? .power : .bluetooth,
            batteryPercentage: 86,
            iconName: key.contains("magsafe") ? "bolt.shield.fill" : "headphones"
        )

        VStack(spacing: 10) {
            HStack(spacing: 10) {
                backButton

                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(LiquidColorTokens.emerald.opacity(0.22))
                            .frame(width: 32, height: 32)
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(LiquidColorTokens.emerald.opacity(0.65), lineWidth: 1.0))
                        Image(systemName: dev.iconName)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(LiquidColorTokens.emerald)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(dev.displayName)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.primaryText)

                        Text("Device Telemetry & Status")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(LiquidColorTokens.secondaryText)
                    }
                }

                Spacer()
            }

            // Telemetry Card
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    if let watts = dev.chargerWatts {
                        Text("Power Draw: \(watts)W")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(LiquidColorTokens.emerald)
                    }
                    if let bat = dev.batteryPercentage {
                        Text("Battery Level: \(bat)%")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(LiquidColorTokens.emerald)
                    }
                    Text("Connection: \(dev.connectionType.rawValue)")
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(LiquidColorTokens.secondaryText)
                }

                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LiquidColorTokens.secondaryGlass.opacity(0.60))
            )

            paginationDots
        }
    }

    // =========================================================================
    // MARK: - SHARED COMPONENTS
    // =========================================================================

    // Back to Carousel Button <
    @ViewBuilder
    private var backButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                onDismiss()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(LiquidColorTokens.secondaryGlass.opacity(0.80))
                    .frame(width: 30, height: 30)
                    .overlay(
                        Circle().stroke(LiquidColorTokens.silverHighlight.opacity(0.35), lineWidth: 0.9)
                    )
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(LiquidColorTokens.primaryText)
            }
        }
        .buttonStyle(.plain)
    }

    // Category Pill for Left Rail
    @ViewBuilder
    private func categoryPill(index: Int, icon: String, title: String, count: String) -> some View {
        let isSelected = (selectedCategoryIndex == index)
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                selectedCategoryIndex = index
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(isSelected ? Color.cyan : LiquidColorTokens.secondaryText)

                Text(title)
                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundStyle(isSelected ? LiquidColorTokens.primaryText : LiquidColorTokens.secondaryText)

                Spacer(minLength: 2)

                Text(count)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.cyan : LiquidColorTokens.mutedText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.cyan.opacity(0.18) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? Color.cyan.opacity(0.45) : Color.clear, lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // Capsule Search Bar
    @ViewBuilder
    private func searchBar(placeholder: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10.5))
                .foregroundStyle(LiquidColorTokens.secondaryText)

            TextField(placeholder, text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(LiquidColorTokens.primaryText)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(LiquidColorTokens.mutedText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(LiquidColorTokens.secondaryGlass.opacity(0.85))
                .overlay(Capsule().stroke(Color.white.opacity(0.14), lineWidth: 0.8))
        )
    }

    // Action Circle Button (Pin, Trash, More)
    @ViewBuilder
    private func actionCircleButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LiquidColorTokens.secondaryGlass.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 0.75))

                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(LiquidColorTokens.secondaryText)
            }
        }
        .buttonStyle(.plain)
    }

    // Stat Pill for Hero Card
    @ViewBuilder
    private func statPill(icon: String, text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
                .foregroundStyle(LiquidColorTokens.secondaryText)
            Text(text)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(LiquidColorTokens.primaryText)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    // Pagination Dots
    @ViewBuilder
    private var paginationDots: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.white.opacity(0.25)).frame(width: 5, height: 5)
            Circle().fill(Color.white).frame(width: 7, height: 7).shadow(color: Color.white.opacity(0.6), radius: 3)
            Circle().fill(Color.white.opacity(0.25)).frame(width: 5, height: 5)
        }
        .padding(.top, 2)
    }
}

