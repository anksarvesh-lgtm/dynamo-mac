//
//  DeviceLibraryView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Defaults
import SceneKit
import SwiftUI

// MARK: - View Model

@MainActor
public final class DeviceLibraryViewModel: ObservableObject {
    @Published public var cachedDevices: [DeviceModelMetadata] = []
    @Published public var totalCacheBytes: Int64 = 0
    @Published public var renamingDeviceKey: String? = nil
    @Published public var editedName: String = ""
    @Published public var spinTriggers: [String: Int] = [:]
    @Published public var pickerDevice: DeviceIdentity? = nil
    @Published public var cloudGenerateDevice: DeviceIdentity? = nil

    public init() {}

    public func openImagePicker(for device: DeviceIdentity) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        self.pickerDevice = device
    }

    public func openCloudGeneration(for device: DeviceIdentity) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        self.cloudGenerateDevice = device
    }

    public func reloadData() async {
        let devices = await DeviceModelStore.shared.allCachedDevices()
        let size = await DeviceModelStore.shared.calculateTotalCacheSize()
        self.cachedDevices = devices
        self.totalCacheBytes = size
    }

    public func triggerCardSpin(key: String) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        spinTriggers[key, default: 0] += 1
    }

    public func startRename(for device: DeviceIdentity) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        editedName = device.displayName
        renamingDeviceKey = device.stableKey
    }

    public func commitRename(for key: String) {
        guard !editedName.trimmingCharacters(in: .whitespaces).isEmpty else {
            renamingDeviceKey = nil
            return
        }

        Task {
            if var meta = await DeviceModelStore.shared.getMetadata(for: key) {
                meta.deviceName = editedName
                // Re-save metadata
                if let modelURL = await DeviceModelStore.shared.getModelURL(for: key),
                   let modelData = try? Data(contentsOf: modelURL) {
                    _ = try? await DeviceModelStore.shared.saveModel(
                        deviceKey: key,
                        modelData: modelData,
                        metadata: meta
                    )
                }
            }
            renamingDeviceKey = nil
            await reloadData()
        }
    }

    public func handleDeleteModel(key: String) {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        Task {
            try? await DeviceModelStore.shared.deleteModel(for: key)
            DeviceModelResolver.shared.clearMemoryCache()
            await reloadData()
        }
    }

    public func handleClearCache() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        Task {
            try? await DeviceModelStore.shared.clearAllCache()
            DeviceModelResolver.shared.clearMemoryCache()
            await reloadData()
        }
    }
}

// MARK: - Device Library View

/// Device Library Tab view displaying all saved and connected devices as interactive 3D cards.
public struct DeviceLibraryView: View {
    @ObservedObject private var monitor = DeviceMonitor.shared
    @ObservedObject private var coordinator = CloudModelGenerationCoordinator.shared
    @StateObject private var vm = DeviceLibraryViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            headerBar

            if combinedDeviceList.isEmpty {
                emptyStateView
            } else {
                devicesScrollView
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .task {
            await vm.reloadData()
        }
        .sheet(item: $vm.pickerDevice) { device in
            ProductImagePickerSheet(
                device: device,
                onDismiss: { vm.pickerDevice = nil },
                onSaved: {
                    vm.pickerDevice = nil
                    Task { await vm.reloadData() }
                }
            )
        }
        .sheet(item: $vm.cloudGenerateDevice) { device in
            CloudModelConfirmationSheet(
                device: device,
                onConfirm: {
                    vm.cloudGenerateDevice = nil
                    coordinator.startGeneration(for: device) {
                        Task { await vm.reloadData() }
                    }
                },
                onDismiss: {
                    vm.cloudGenerateDevice = nil
                },
                onChooseImageRequested: {
                    vm.cloudGenerateDevice = nil
                    vm.openImagePicker(for: device)
                }
            )
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Device Library")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)

                Text("\(combinedDeviceList.count) device\(combinedDeviceList.count == 1 ? "" : "s") registered • \(ByteCountFormatter.string(fromByteCount: vm.totalCacheBytes, countStyle: .file)) cached")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            if vm.totalCacheBytes > 0 {
                Button(action: vm.handleClearCache) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                        Text("Clear Cache")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
                    .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Combined Device List

    public struct DisplayDeviceItem: Identifiable {
        public var id: String { identity.stableKey }
        public let identity: DeviceIdentity
        public let isConnected: Bool
        public let lastSeenDate: Date
        public let hasCustomModel: Bool
    }

    public var combinedDeviceList: [DisplayDeviceItem] {
        var items: [DisplayDeviceItem] = []
        var processedKeys = Set<String>()

        // 1. First add currently connected devices
        for (key, device) in monitor.activeDevices {
            processedKeys.insert(key)
            let hasCustom = vm.cachedDevices.contains { $0.deviceKey == key && $0.sourceTier != .categoryStandIn }
            items.append(DisplayDeviceItem(
                identity: device,
                isConnected: true,
                lastSeenDate: Date(),
                hasCustomModel: hasCustom
            ))
        }

        // 2. Then add saved offline devices from DeviceModelStore
        for meta in vm.cachedDevices {
            if !processedKeys.contains(meta.deviceKey) {
                let kind = DeviceKind(rawValue: meta.kind) ?? .generic
                let identity = DeviceIdentity(
                    stableKey: meta.deviceKey,
                    kind: kind,
                    displayName: meta.deviceName,
                    vendor: meta.provider ?? "Device",
                    model: meta.deviceName,
                    connectionType: meta.deviceKey.starts(with: "bt_") ? .bluetooth : (meta.deviceKey.starts(with: "vol_") ? .storage : .usb)
                )
                items.append(DisplayDeviceItem(
                    identity: identity,
                    isConnected: false,
                    lastSeenDate: meta.lastSeenAt,
                    hasCustomModel: meta.sourceTier != .categoryStandIn
                ))
            }
        }

        return items
    }

    // MARK: - Devices Scroll View

    private var devicesScrollView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 190), spacing: 10)], spacing: 10) {
                ForEach(combinedDeviceList) { item in
                    deviceCard(for: item)
                }
            }
            .padding(.bottom, 6)
        }
        .frame(maxHeight: 280)
    }

    // MARK: - Device Card

    private func deviceCard(for item: DisplayDeviceItem) -> some View {
        let job = coordinator.jobState(for: item.identity.stableKey)
        let isGenerating = job?.isGenerating ?? false

        return VStack(spacing: 8) {
            // Top: Status badge & 3D Interactive View
            ZStack(alignment: .topTrailing) {
                // 3D Turntable view (click to spin, drag to rotate)
                DeviceInteractive3DView(
                    device: item.identity,
                    size: 80,
                    rpm: 14.0,
                    isPaused: false,
                    externalSpinTrigger: vm.spinTriggers[item.identity.stableKey] ?? 0
                )
                .frame(height: 84)
                .padding(.top, 4)

                // Connected Indicator or Connection Badge
                HStack(spacing: 3) {
                    if item.isConnected {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("Active")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.green)
                    } else {
                        Text(item.identity.connectionType.rawValue)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.4))
                .clipShape(Capsule())
            }

            // Active Cloud Generation Progress Bar & Status
            if let job = job, isGenerating {
                VStack(spacing: 3) {
                    ProgressView(value: job.progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(Color.purple)
                    HStack {
                        Text(job.statusMessage)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.purple)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(job.progress * 100))%")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }

            // Middle: Name & Last Seen
            VStack(spacing: 2) {
                if vm.renamingDeviceKey == item.identity.stableKey {
                    HStack(spacing: 4) {
                        TextField("Name", text: $vm.editedName, onCommit: {
                            vm.commitRename(for: item.identity.stableKey)
                        })
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, weight: .semibold))
                        .padding(3)
                        .background(Color.white.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                        Button(action: { vm.commitRename(for: item.identity.stableKey) }) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                } else {
                    Text(item.identity.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Text(item.isConnected ? "Connected now" : formattedDate(item.lastSeenDate))
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            // Bottom: Action Bar
            HStack(spacing: 8) {
                // 1. Spin Action
                Button(action: { vm.triggerCardSpin(key: item.identity.stableKey) }) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Spin 3D Model")

                // 2. Rename Action
                Button(action: { vm.startRename(for: item.identity) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Rename Device")

                // 3. Choose Image Action (Online Search, File Picker, or Drag & Drop)
                Button(action: { vm.openImagePicker(for: item.identity) }) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.blue.opacity(0.9))
                }
                .buttonStyle(.plain)
                .help("Choose product image (Online search, File picker, or Drag & Drop)")

                // 4. Delete Model Action
                Button(action: { vm.handleDeleteModel(key: item.identity.stableKey) }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red.opacity(0.75))
                }
                .buttonStyle(.plain)
                .help("Delete Model (Revert to Stand-in)")

                Spacer()

                // 5. Generate Better 3D Model
                Button(action: {
                    vm.openCloudGeneration(for: item.identity)
                }) {
                    HStack(spacing: 3) {
                        if isGenerating {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 10, height: 10)
                            Text("Generating...")
                                .font(.system(size: 9, weight: .semibold))
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: 8))
                            Text("AI 3D")
                                .font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(isGenerating ? Color.purple.opacity(0.2) : Color.purple.opacity(0.15))
                    .clipShape(Capsule())
                    .foregroundStyle(isGenerating ? Color.purple : Color.white.opacity(0.85))
                    .overlay(
                        Capsule()
                            .stroke(Color.purple.opacity(0.4), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
                .help(isGenerating ? "Generation in progress..." : "Generate photorealistic 3D model via Meshy AI")
            }
            .padding(.top, 2)
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 20)
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            vm.openImagePicker(for: item.identity)
            return true
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "laptopcomputer.and.iphone")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.top, 16)

            Text("No Devices Connected")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)

            Text("Connect Bluetooth earphones, USB flash drives, or external SSDs to automatically showcase them in 3D.")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 240)
                .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: 180)
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Seen \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
