//
//  CloudModelConfirmationSheet.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Defaults
import SwiftUI

// MARK: - View Model

@MainActor
public final class CloudConfirmationViewModel: ObservableObject {
    @Published public var hasPreviewImage: Bool = false
    @Published public var previewImage: NSImage? = nil
    @Published public var apiKeyInput: String = ""
    @Published public var isApiKeySaved: Bool = false
    @Published public var showKeyEditor: Bool = false
    @Published public var errorMessage: String? = nil

    public init(device: DeviceIdentity) {
        self.isApiKeySaved = KeychainService.shared.hasMeshyKey()
        self.showKeyEditor = !isApiKeySaved
    }

    public func loadPreview(for deviceKey: String) async {
        let store = DeviceModelStore.shared
        if let img = await store.getPreviewImage(for: deviceKey) {
            self.previewImage = img
            self.hasPreviewImage = true
        } else {
            self.hasPreviewImage = false
        }
    }

    public func saveApiKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "API Key cannot be empty."
            return
        }
        let success = KeychainService.shared.setMeshyKey(trimmed)
        if success {
            self.isApiKeySaved = true
            self.showKeyEditor = false
            self.errorMessage = nil
            self.apiKeyInput = ""
        } else {
            self.errorMessage = "Failed to save API key to Keychain."
        }
    }
}

// MARK: - Cloud Model Confirmation Sheet

public struct CloudModelConfirmationSheet: View {
    public let device: DeviceIdentity
    public let onConfirm: () -> Void
    public let onDismiss: () -> Void
    public let onChooseImageRequested: () -> Void

    @ObservedObject private var coordinator = CloudModelGenerationCoordinator.shared
    @StateObject private var vm: CloudConfirmationViewModel

    public init(
        device: DeviceIdentity,
        onConfirm: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onChooseImageRequested: @escaping () -> Void
    ) {
        self.device = device
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
        self.onChooseImageRequested = onChooseImageRequested
        _vm = StateObject(wrappedValue: CloudConfirmationViewModel(device: device))
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar

            Divider()
                .background(Color.white.opacity(0.12))

            mainContent
                .padding(20)

            Divider()
                .background(Color.white.opacity(0.12))

            footerButtons
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await vm.loadPreview(for: device.stableKey)
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.purple)

            Text("Generate 3D Model")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Main Content

    private var mainContent: some View {
        VStack(spacing: 16) {
            // Preview & Target Device
            HStack(spacing: 16) {
                if let preview = vm.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 80, height: 80)
                        .padding(4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                } else {
                    ZStack {
                        Color.white.opacity(0.05)
                        Image(systemName: "photo")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)

                    Text(device.kind.rawValue)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))

                    if vm.hasPreviewImage {
                        Label("Confirmed 1024px transparent PNG ready", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                    } else {
                        Label("No product image selected yet", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }

                Spacer()
            }

            // If missing preview image, prompt to choose one
            if !vm.hasPreviewImage {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("A product photo is required to generate the 3D model.")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("Use online image search, file picker, or drag & drop first.")
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Button("Choose Image...") {
                        onDismiss()
                        onChooseImageRequested()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Cost & Quota Card
            VStack(spacing: 8) {
                HStack {
                    Label("Estimated Credit Cost", systemImage: "dollarsign.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))

                    Spacer()

                    Text("~20 credits (Meshy 7.1)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.purple)
                }

                HStack {
                    Label("Monthly Cap Status", systemImage: "chart.bar.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))

                    Spacer()

                    Text("\(coordinator.monthlyUsed) of \(coordinator.monthlyCap) used this month")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(coordinator.canGenerate() ? .white : .red)
                }

                if !coordinator.canGenerate() {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text("Monthly generation limit reached. You can increase this in Settings.")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                        Spacer()
                    }
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Keychain API Key Section
            if vm.showKeyEditor || !vm.isApiKeySaved {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Meshy API Key (Stored securely in macOS Keychain only)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))

                    HStack(spacing: 6) {
                        SecureField("Enter Meshy API Key (msy_...)", text: $vm.apiKeyInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .padding(6)
                            .background(Color.black.opacity(0.3))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        Button("Save Key", action: vm.saveApiKey)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }

                    if let err = vm.errorMessage {
                        Text(err)
                            .font(.system(size: 9))
                            .foregroundStyle(.red)
                    }

                    Text("Keys are stored exclusively in your Mac's Keychain and are never logged.")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(10)
                .background(Color.purple.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                HStack {
                    Image(systemName: "key.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("Meshy API Key configured in Keychain")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))

                    Spacer()

                    Button("Change") {
                        vm.showKeyEditor = true
                    }
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Footer Buttons

    private var footerButtons: some View {
        HStack(spacing: 12) {
            Button("Cancel", action: onDismiss)
                .buttonStyle(.bordered)
                .controlSize(.regular)

            Spacer()

            Button(action: onConfirm) {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                    Text("Start 3D Generation")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .controlSize(.regular)
            .disabled(!vm.hasPreviewImage || !vm.isApiKeySaved || !coordinator.canGenerate())
        }
    }
}
