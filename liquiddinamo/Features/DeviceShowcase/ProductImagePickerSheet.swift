//
//  ProductImagePickerSheet.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Picker Mode

public enum ProductImagePickerTab: String, CaseIterable, Identifiable {
    case preset3D = "Bundled 3D Library"
    case filePicker = "From File"
    case dragDrop = "Drag & Drop"

    public var id: String { rawValue }
}

// MARK: - View Model

@MainActor
public final class ProductImagePickerViewModel: ObservableObject {
    public struct PresetItem: Identifiable {
        public let id: String
        public let name: String
        public let category: String
        public let icon: Premium3DIcon
    }

    @Published public var selectedTab: ProductImagePickerTab = .preset3D
    @Published public var searchQuery: String = ""
    @Published public var errorMessage: String? = nil

    @Published public var isProcessing: Bool = false
    @Published public var processingStatus: String = ""
    @Published public var confirmedPreview: ProcessedProductImage? = nil
    @Published public var isDropTargeted: Bool = false

    public let bundledPresets: [PresetItem] = [
        PresetItem(id: "airpods_pro", name: "AirPods Pro", category: "Audio", icon: .airPods),
        PresetItem(id: "airpods_max", name: "AirPods Max", category: "Audio", icon: .headphones),
        PresetItem(id: "studio_display", name: "Studio Display", category: "Display", icon: .desktopMac),
        PresetItem(id: "macbook_pro", name: "MacBook Pro", category: "Computer", icon: .desktopMac),
        PresetItem(id: "iphone_pro", name: "iPhone 16 Pro", category: "Mobile", icon: .androidPhone),
        PresetItem(id: "android_phone", name: "Android Device", category: "Mobile", icon: .androidPhone),
        PresetItem(id: "homepod", name: "HomePod Speaker", category: "Speaker", icon: .smartSpeaker),
        PresetItem(id: "beats_studio", name: "Beats Studio", category: "Audio", icon: .headphones),
        PresetItem(id: "external_drive", name: "External Storage", category: "Storage", icon: .shelf),
        PresetItem(id: "smart_watch", name: "Apple Watch", category: "Wearable", icon: .generic),
    ]

    public init(device: DeviceIdentity) {
        self.searchQuery = device.displayName
    }

    // MARK: - Bundled Preset Selection

    public func selectPreset(_ preset: PresetItem) {
        errorMessage = nil
        isProcessing = true
        processingStatus = "Loading bundled 3D asset..."

        if let processed = ProductImageProcessor.shared.createFromSymbol(icon: preset.icon) {
            self.isProcessing = false
            self.confirmedPreview = processed
        } else {
            self.isProcessing = false
            self.errorMessage = "Failed to load asset for \(preset.name)"
        }
    }



    // MARK: - Local File Picking

    public func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .heic, .webP]
        panel.title = "Select Product Image"
        panel.prompt = "Choose Image"

        if panel.runModal() == .OK, let url = panel.url {
            processLocalImage(from: url)
        }
    }

    public func processLocalImage(from url: URL) {
        guard let image = NSImage(contentsOf: url) else {
            errorMessage = "Unable to load image from selected file."
            return
        }

        errorMessage = nil
        isProcessing = true
        processingStatus = "Isolating subject using Vision..."

        Task {
            do {
                let processed = try await ProductImageProcessor.shared.isolateProductSubject(
                    from: image,
                    sourceURL: url.absoluteString
                )
                self.isProcessing = false
                self.confirmedPreview = processed
            } catch {
                self.isProcessing = false
                self.errorMessage = "Failed to process image: \(error.localizedDescription)"
            }
        }
    }

    public func processDroppedImage(data: Data, filename: String?) {
        guard let image = NSImage(data: data) else {
            errorMessage = "Dropped data is not a recognized image."
            return
        }

        errorMessage = nil
        isProcessing = true
        processingStatus = "Isolating subject using Vision..."

        Task {
            do {
                let source = filename ?? "drag_and_drop"
                let processed = try await ProductImageProcessor.shared.isolateProductSubject(
                    from: image,
                    sourceURL: source
                )
                self.isProcessing = false
                self.confirmedPreview = processed
            } catch {
                self.isProcessing = false
                self.errorMessage = "Failed to process image: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Save

    public func confirmAndSave(device: DeviceIdentity, onComplete: @escaping () -> Void) {
        guard let preview = confirmedPreview else { return }

        Task {
            do {
                try await DeviceModelStore.shared.saveProductImage(
                    deviceKey: device.stableKey,
                    pngData: preview.pngData,
                    sourceURL: preview.sourceURL,
                    deviceName: device.displayName,
                    kind: device.kind.rawValue
                )
                DeviceModelResolver.shared.clearMemoryCache()
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                onComplete()
            } catch {
                self.errorMessage = "Failed to save product image: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Product Image Picker Sheet

public struct ProductImagePickerSheet: View {
    public let device: DeviceIdentity
    public let onDismiss: () -> Void
    public let onSaved: () -> Void

    @StateObject private var vm: ProductImagePickerViewModel

    public init(
        device: DeviceIdentity,
        onDismiss: @escaping () -> Void,
        onSaved: @escaping () -> Void
    ) {
        self.device = device
        self.onDismiss = onDismiss
        self.onSaved = onSaved
        _vm = StateObject(wrappedValue: ProductImagePickerViewModel(device: device))
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()
                .background(Color.white.opacity(0.12))

            if let preview = vm.confirmedPreview {
                confirmationView(preview: preview)
            } else if vm.isProcessing {
                processingOverlay
            } else {
                mainContentView
            }
        }
        .frame(width: 540, height: 460)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Product Image: \(device.displayName)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)

                Text("Nothing leaves your Mac unless you click. Vision isolates the subject on-device.")
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Main Content View

    private var mainContentView: some View {
        VStack(spacing: 12) {
            // Tab Picker
            Picker("", selection: $vm.selectedTab) {
                ForEach(ProductImagePickerTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if let err = vm.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            // Tab Content
            switch vm.selectedTab {
            case .preset3D:
                bundledAssetTabContent
            case .filePicker:
                filePickerTabContent
            case .dragDrop:
                dragDropTabContent
            }
        }
    }

    // MARK: - Bundled 3D Asset Library Tab

    private var bundledAssetTabContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Select from built-in high-resolution 3D models (100% offline):")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
                .padding(.horizontal, 16)

            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(vm.bundledPresets) { preset in
                        Button(action: { vm.selectPreset(preset) }) {
                            VStack(spacing: 8) {
                                Premium3DIconView(preset.icon, size: 48, interactive: false)
                                    .frame(height: 56)

                                VStack(spacing: 2) {
                                    Text(preset.name)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)

                                    Text(preset.category)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
    }

    // MARK: - File Picker Tab

    private var filePickerTabContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "folder.badge.plus")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.blue)

            VStack(spacing: 4) {
                Text("Select an image from your Mac")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)

                Text("Supports PNG, JPEG, HEIC, TIFF, and WebP.")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Button(action: vm.openFilePicker) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.viewfinder")
                    Text("Browse Files...")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }

    // MARK: - Drag & Drop Tab

    private var dragDropTabContent: some View {
        VStack(spacing: 12) {
            Spacer()

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        vm.isDropTargeted ? Color.blue : Color.white.opacity(0.2),
                        style: StrokeStyle(lineWidth: 2, dash: [8, 4])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(vm.isDropTargeted ? Color.blue.opacity(0.1) : Color.white.opacity(0.03))
                    )

                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(vm.isDropTargeted ? .blue : .white.opacity(0.5))

                    Text("Drop Product Image Here")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)

                    Text("Drag from Finder, Safari, or Photos")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(height: 200)
            .padding(.horizontal, 24)
            .onDrop(of: [.fileURL, .image], isTargeted: $vm.isDropTargeted) { providers in
                guard let provider = providers.first else { return false }

                // Check for file URL
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        DispatchQueue.main.async {
                            vm.processLocalImage(from: url)
                        }
                    }
                }

                // Check for NSImage / Data
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data = data {
                        DispatchQueue.main.async {
                            vm.processDroppedImage(data: data, filename: "dropped_image")
                        }
                    }
                }
                return true
            }

            Spacer()
        }
    }

    // MARK: - Processing Overlay

    private var processingOverlay: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(vm.processingStatus)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text("Vision is segmenting subject and removing background locally.")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
        }
    }

    // MARK: - Confirmation View

    private func confirmationView(preview: ProcessedProductImage) -> some View {
        VStack(spacing: 12) {
            Text("Confirm Isolated Subject")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.top, 10)

            // Checkerboard background preview container
            ZStack {
                CheckerboardPattern()
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Image(nsImage: preview.image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 210, height: 210)
                    .padding(10)
            }
            .frame(width: 230, height: 230)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )

            // Info details
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.system(size: 11))
                    Text("Vision Cutout • 1024 × 1024 Transparent PNG")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                }

                if let src = preview.sourceURL {
                    Text(src)
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 380)
                }
            }

            // Action Buttons
            HStack(spacing: 12) {
                Button("Choose Another") {
                    vm.confirmedPreview = nil
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(action: {
                    vm.confirmAndSave(device: device) {
                        onSaved()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark")
                        Text("Confirm & Use Image")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(.bottom, 12)
        }
    }
}

// MARK: - Checkerboard Pattern

private struct CheckerboardPattern: View {
    let size: CGFloat = 10

    var body: some View {
        Canvas { context, canvasSize in
            let cols = Int(ceil(canvasSize.width / size))
            let rows = Int(ceil(canvasSize.height / size))

            for row in 0..<rows {
                for col in 0..<cols {
                    let isEven = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * size,
                        y: CGFloat(row) * size,
                        width: size,
                        height: size
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isEven ? Color(white: 0.18) : Color(white: 0.12))
                    )
                }
            }
        }
    }
}
