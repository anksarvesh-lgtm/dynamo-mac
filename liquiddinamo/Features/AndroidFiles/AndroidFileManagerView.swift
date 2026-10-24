//
//  AndroidFileManagerView.swift
//  LiquidDynamo
//
//  Native Liquid Glass SwiftUI file manager interface for Android (ADB) devices.
//  Features dual-pane sidebar with quick locations, breadcrumb navigation,
//  multi-select, drag-and-drop, lazy thumbnails, keyboard shortcuts, and transfer progress.
//

import AppKit
import Foundation
import SwiftUI

public struct AndroidFileManagerView: View {
    @ObservedObject public var viewModel: AndroidFileManagerViewModel
    @ObservedObject private var thumbnailCache = AndroidThumbnailCache.shared

    public init(viewModel: AndroidFileManagerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ZStack {
            // Liquid OLED backdrop
            Color(red: 0.08, green: 0.09, blue: 0.11)
                .ignoresSafeArea()

            VisualEffectBackdropView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            HSplitView {
                // MARK: - Left Sidebar
                sidebarView
                    .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

                // MARK: - Right Main Content Area
                VStack(spacing: 0) {
                    topToolbar
                    deviceStorageBar
                    breadcrumbPathBar

                    Divider()
                        .background(Color.white.opacity(0.12))

                    if let err = viewModel.errorMessage {
                        errorBanner(err)
                    }

                    if viewModel.scopedStorageRestricted {
                        scopedStorageBanner
                    }

                    ZStack {
                        if viewModel.isLoading {
                            loadingView
                        } else if viewModel.displayEntries.isEmpty {
                            emptyFolderView
                        } else {
                            if viewModel.isGridView {
                                fileGridView
                            } else {
                                fileListView
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if !viewModel.transferQueue.isEmpty {
                        transferDrawer
                    }

                    statusBar
                }
            }
        }
        .sheet(isPresented: $viewModel.isShowingNewFolderSheet) {
            newFolderSheet
        }
        .onAppear {
            viewModel.refresh()
        }
    }

    // MARK: - Sidebar View

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Device Identity Capsule
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.deviceName)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(viewModel.deviceModel.isEmpty ? "Android Device" : viewModel.deviceModel)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            Divider()
                .background(Color.white.opacity(0.10))

            // Quick Locations List
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("LOCATIONS")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    ForEach(AndroidQuickLocation.standardLocations) { loc in
                        let isSelected = viewModel.currentPath == loc.path || viewModel.currentPath.hasPrefix(loc.path + "/")
                        Button {
                            viewModel.navigate(to: loc.path)
                        } label: {
                            HStack(spacing: 9) {
                                Image(systemName: loc.iconName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(loc.tintColor)
                                    .frame(width: 18)

                                Text(loc.name)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.8))

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color.white.opacity(0.12) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 8)
                    }
                }
            }

            Spacer()

            // ADB Status Footer
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)

                Text("ADB Transport Connected")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.3))
        }
        .background(Color.black.opacity(0.25))
    }

    // MARK: - Top Toolbar

    private var topToolbar: some View {
        HStack(spacing: 8) {
            // Navigation History Buttons
            HStack(spacing: 2) {
                Button {
                    viewModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .disabled(!viewModel.canGoBack)
                .buttonStyle(.plain)
                .help("Back (Cmd+[)")

                Button {
                    viewModel.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .disabled(!viewModel.canGoForward)
                .buttonStyle(.plain)
                .help("Forward (Cmd+])")

                Button {
                    viewModel.goUp()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 26)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .disabled(!viewModel.canGoUp)
                .buttonStyle(.plain)
                .help("Enclosing Folder (Cmd+Up)")
            }

            Spacer()

            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Search in folder", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 140)

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Action Buttons
            HStack(spacing: 4) {
                Button {
                    viewModel.isShowingNewFolderSheet = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 26)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("New Folder (Cmd+N)")

                Button {
                    viewModel.promptUploadFiles()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 26)
                        .background(Color.green.opacity(0.25))
                        .foregroundStyle(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Upload to Device")

                if !viewModel.selectedPaths.isEmpty {
                    Button {
                        viewModel.downloadSelectedItems()
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12))
                            .frame(width: 28, height: 26)
                            .background(Color.blue.opacity(0.25))
                            .foregroundStyle(Color.cyan)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Download Selected to Mac (~/Downloads)")

                    Button {
                        viewModel.deleteSelected()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 12))
                            .frame(width: 28, height: 26)
                            .background(Color.red.opacity(0.25))
                            .foregroundStyle(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help("Delete Selected (Cmd+Delete)")
                }

                // Grid / List View Toggle
                Button {
                    viewModel.isGridView.toggle()
                } label: {
                    Image(systemName: viewModel.isGridView ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 26)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Toggle List/Grid View")

                // Hidden Files Toggle
                Button {
                    viewModel.showHiddenFiles.toggle()
                    viewModel.refresh()
                } label: {
                    Image(systemName: viewModel.showHiddenFiles ? "eye.fill" : "eye.slash")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 26)
                        .background(viewModel.showHiddenFiles ? Color.white.opacity(0.18) : Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Toggle Hidden Files")

                // Refresh Button
                Button {
                    viewModel.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12))
                        .frame(width: 28, height: 26)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Refresh (Cmd+R)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.18))
    }

    // MARK: - Device Storage Progress Bar

    private var deviceStorageBar: some View {
        Group {
            if viewModel.totalStorageBytes > 0 {
                let used = max(0, viewModel.totalStorageBytes - viewModel.freeStorageBytes)
                let pct = Double(used) / Double(viewModel.totalStorageBytes)

                HStack(spacing: 12) {
                    Text("Storage:")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.12))
                            Capsule()
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(pct))
                        }
                    }
                    .frame(height: 5)

                    Text("\(formatBytes(viewModel.freeStorageBytes)) free of \(formatBytes(viewModel.totalStorageBytes))")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.25))
            }
        }
    }

    // MARK: - Breadcrumb Path Bar

    private var breadcrumbPathBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(viewModel.breadcrumbs, id: \.path) { crumb in
                    Button {
                        viewModel.navigate(to: crumb.path)
                    } label: {
                        HStack(spacing: 3) {
                            Text(crumb.title)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(crumb.path == viewModel.currentPath ? Color.green : Color.white.opacity(0.8))

                            if crumb.path != viewModel.breadcrumbs.last?.path {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.secondary.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
        }
        .background(Color.black.opacity(0.12))
    }

    // MARK: - File List View

    private var fileListView: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(viewModel.displayEntries) { item in
                    let isSelected = viewModel.selectedPaths.contains(item.path)

                    HStack(spacing: 10) {
                        Image(systemName: item.iconSystemName)
                            .font(.system(size: 14))
                            .foregroundStyle(item.isDirectory ? Color.yellow : (item.isImage ? Color.cyan : (item.isVideo ? Color.purple : Color.white.opacity(0.8))))
                            .frame(width: 22)

                        Text(item.name)
                            .font(.system(size: 12, weight: item.isDirectory ? .bold : .regular, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        if item.isSymlink {
                            Text("→ \(item.symlinkTarget ?? "")")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if !item.isDirectory {
                            Text(formatBytes(item.size))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .trailing)
                        } else {
                            Text("--")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary.opacity(0.5))
                                .frame(width: 80, alignment: .trailing)
                        }

                        if let date = item.modificationDate {
                            Text(formatDate(date))
                                .font(.system(size: 10.5, design: .rounded))
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? Color.blue.opacity(0.35) : Color.white.opacity(0.02))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        viewModel.openEntry(item)
                    }
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            if isSelected {
                                viewModel.selectedPaths.remove(item.path)
                            } else {
                                viewModel.selectedPaths.insert(item.path)
                            }
                        } else {
                            viewModel.selectedPaths = [item.path]
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }

    // MARK: - File Grid View

    private var fileGridView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130), spacing: 12)], spacing: 12) {
                ForEach(viewModel.displayEntries) { item in
                    let isSelected = viewModel.selectedPaths.contains(item.path)

                    VStack(spacing: 6) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 74)

                            if let thumb = thumbnailCache.cachedImage(for: "\(viewModel.deviceSerial)_\(item.path)_\(item.size)") {
                                Image(nsImage: thumb)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 68)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: item.iconSystemName)
                                    .font(.system(size: 30))
                                    .foregroundStyle(item.isDirectory ? Color.yellow : (item.isImage ? Color.cyan : (item.isVideo ? Color.purple : Color.white.opacity(0.75))))
                            }
                        }

                        Text(item.name)
                            .font(.system(size: 11, weight: item.isDirectory ? .bold : .regular, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(height: 30, alignment: .top)

                        if !item.isDirectory {
                            Text(formatBytes(item.size))
                                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isSelected ? Color.blue.opacity(0.35) : Color.white.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(isSelected ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        viewModel.openEntry(item)
                    }
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            if isSelected {
                                viewModel.selectedPaths.remove(item.path)
                            } else {
                                viewModel.selectedPaths.insert(item.path)
                            }
                        } else {
                            viewModel.selectedPaths = [item.path]
                        }
                    }
                    .task {
                        if item.isImage || item.isVideo {
                            _ = await thumbnailCache.loadThumbnail(for: item, serial: viewModel.deviceSerial, client: viewModel.client)
                        }
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Transfer Drawer

    private var transferDrawer: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.arrow.down.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.green)

                    Text("Transfers (\(viewModel.transferQueue.filter { $0.status == .active || $0.status == .pending }.count) active)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                Spacer()

                Button {
                    viewModel.clearCompletedTransfers()
                } label: {
                    Text("Clear Finished")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.isTransferDrawerExpanded.toggle()
                } label: {
                    Image(systemName: viewModel.isTransferDrawerExpanded ? "chevron.down" : "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.40))

            if viewModel.isTransferDrawerExpanded {
                VStack(spacing: 6) {
                    ForEach(viewModel.transferQueue) { transfer in
                        HStack(spacing: 10) {
                            Image(systemName: transfer.isUpload ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(transfer.isUpload ? Color.green : Color.cyan)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(transfer.filename)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)

                                HStack(spacing: 8) {
                                    Text(transfer.status.rawValue)
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundStyle(statusColor(transfer.status))

                                    if transfer.status == .active && transfer.speedBytesPerSec > 0 {
                                        Text(String(format: "%.1f MB/s", transfer.speedBytesPerSec / 1_000_000.0))
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }

                                    if let err = transfer.errorMessage {
                                        Text(err)
                                            .font(.system(size: 9))
                                            .foregroundStyle(Color.red)
                                            .lineLimit(1)
                                    }
                                }
                            }

                            Spacer()

                            if transfer.status == .active {
                                ProgressView(value: transfer.percentage)
                                    .progressViewStyle(.linear)
                                    .frame(width: 80)

                                Button {
                                    viewModel.cancelTransfer(transfer.id)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            } else if transfer.status == .completed && !transfer.isUpload {
                                Button("Reveal in Finder") {
                                    viewModel.revealInFinder(localURL: transfer.localURL)
                                }
                                .font(.system(size: 9.5, weight: .bold))
                                .foregroundStyle(Color.cyan)
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.30))
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text("\(viewModel.displayEntries.count) items")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

            if !viewModel.selectedPaths.isEmpty {
                Text("• \(viewModel.selectedPaths.count) selected")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.green)
            }

            Spacer()

            Text(viewModel.currentPath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.35))
    }

    // MARK: - Banner & State Views

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.orange)

            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)

            Spacer()

            Button("Dismiss") {
                viewModel.errorMessage = nil
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.25))
    }

    private var scopedStorageBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 12))
                .foregroundStyle(Color.yellow)

            Text("Notice: Access to this folder is restricted by Android 11+ scoped storage privacy protections.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.20))
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.9)
            Text("Loading Android files…")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyFolderView: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 36))
                .foregroundStyle(.secondary.opacity(0.5))

            Text("This folder is empty")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var newFolderSheet: some View {
        VStack(spacing: 14) {
            Text("New Folder")
                .font(.system(size: 13, weight: .bold, design: .rounded))

            TextField("Folder Name", text: $viewModel.newFolderName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)

            HStack(spacing: 10) {
                Button("Cancel") {
                    viewModel.newFolderName = ""
                    viewModel.isShowingNewFolderSheet = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    viewModel.createFolder(named: viewModel.newFolderName)
                    viewModel.newFolderName = ""
                    viewModel.isShowingNewFolderSheet = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.newFolderName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 280)
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func statusColor(_ status: AndroidFileTransfer.Status) -> Color {
        switch status {
        case .pending: return .secondary
        case .active: return .green
        case .completed: return .cyan
        case .failed: return .red
        case .cancelled: return .secondary
        }
    }
}
