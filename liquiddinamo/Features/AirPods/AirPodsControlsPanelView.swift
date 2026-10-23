//
//  AirPodsControlsPanelView.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

// MARK: - View Model for Controls Panel

@MainActor
public final class AirPodsControlsViewModel: ObservableObject {
    public let service = AirPodsService.shared

    @Published public var pendingNoiseMode: AirPodsNoiseMode = .off
    @Published public var pendingAdaptiveLevel: Double = 0.5
    @Published public var pendingConversationAwareness: Bool = false
    @Published public var pendingOneBudANC: Bool = false
    @Published public var volumeLevel: Double = 0.5
    @Published public var isMuted: Bool = false

    @Published public var errorMessage: String? = nil
    @Published public var isExecutingWrite: Bool = false

    private var cancellables = Set<AnyCancellable>()

    public init() {
        syncFromService()

        service.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.syncFromService()
            }
            .store(in: &cancellables)
    }

    public func syncFromService() {
        if let mode = service.state.noiseMode {
            pendingNoiseMode = mode
        }
        if let adaptive = service.state.adaptiveLevel {
            pendingAdaptiveLevel = adaptive
        }
        if let ca = service.state.conversationAwarenessEnabled {
            pendingConversationAwareness = ca
        }
        if let oneBud = service.state.oneBudANCEnabled {
            pendingOneBudANC = oneBud
        }
    }

    public func setNoiseMode(_ mode: AirPodsNoiseMode) {
        guard mode != service.state.noiseMode else { return }
        executeWriteCommand(.setNoiseMode(mode)) { [weak self] in
            guard let self = self else { return }
            self.pendingNoiseMode = self.service.state.noiseMode ?? .off
        }
    }

    public func setAdaptiveLevel(_ level: Double) {
        executeWriteCommand(.setAdaptiveLevel(level)) { [weak self] in
            guard let self = self else { return }
            self.pendingAdaptiveLevel = self.service.state.adaptiveLevel ?? 0.5
        }
    }

    public func setConversationAwareness(_ enabled: Bool) {
        executeWriteCommand(.setConversationAwareness(enabled)) { [weak self] in
            guard let self = self else { return }
            self.pendingConversationAwareness = self.service.state.conversationAwarenessEnabled ?? false
        }
    }

    public func setOneBudANC(_ enabled: Bool) {
        executeWriteCommand(.setOneBudANC(enabled)) { [weak self] in
            guard let self = self else { return }
            self.pendingOneBudANC = self.service.state.oneBudANCEnabled ?? false
        }
    }

    public func setVolume(_ volume: Double) {
        self.volumeLevel = volume
        self.isMuted = volume == 0
        executeWriteCommand(.setVolume(volume))
    }

    public func toggleMute() {
        isMuted.toggle()
        let target = isMuted ? 0.0 : 0.5
        setVolume(target)
    }

    public func executeWriteCommand(_ command: AirPodsCommand, onRevert: (() -> Void)? = nil) {
        isExecutingWrite = true
        errorMessage = nil

        Task {
            let result = await service.writeCommand(command)
            await MainActor.run {
                self.isExecutingWrite = false
                switch result {
                case .success:
                    break
                case .failure(let error):
                    onRevert?()
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    public func startHeadTracking(onDenied: @escaping () -> Void) {
        service.setHeadTracking(enabled: true) { [weak self] errorMsg in
            guard let self = self else { return }
            onDenied()
            self.errorMessage = errorMsg
        }
    }

    public func stopHeadTracking() {
        service.setHeadTracking(enabled: false)
    }

    public func dismissError() {
        errorMessage = nil
    }
}

// MARK: - AirPods Controls Panel View

@MainActor
public struct AirPodsControlsPanelView: View {
    @ObservedObject public var viewModel: AirPodsControlsViewModel
    @ObservedObject private var service = AirPodsService.shared

    // Settings
    @Default(.enableAirPodsFollowHead) private var enableFollowHead
    @Default(.showAirPodsNoiseControl) private var showNoiseControl
    @Default(.showAirPodsAdaptiveLevel) private var showAdaptiveLevel
    @Default(.showAirPodsConversationAwareness) private var showConversationAwareness
    @Default(.showAirPodsOneBudANC) private var showOneBudANC
    @Default(.showAirPodsVolume) private var showVolume

    public init(viewModel: AirPodsControlsViewModel) {
        self.viewModel = viewModel
    }

    public init() {
        self.viewModel = AirPodsControlsViewModel()
    }

    public var body: some View {
        VStack(spacing: 14) {
            // Error feedback banner
            if let error = viewModel.errorMessage {
                errorBanner(message: error)
            }

            // 1. Noise Control Modes
            if showNoiseControl {
                noiseControlSection
            }

            // 2. Adaptive Level Slider
            if showAdaptiveLevel && service.capabilities.supportsAdaptiveAudio {
                adaptiveLevelSection
            }

            // 3. Feature Toggles (Follow Head, Conversation Awareness, One-Bud ANC)
            featureTogglesSection

            // 4. Volume Slider with Mute
            if showVolume {
                volumeSection
            }

            Divider()
                .background(Color.white.opacity(0.12))

            // 5. Always Available: Battery Details, Ear Status & Sound Settings Button
            alwaysAvailableSection
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(white: 0.08).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .onAppear {
            if enableFollowHead && service.capabilities.supportsHeadMotion {
                viewModel.startHeadTracking {
                    enableFollowHead = false
                }
            }
        }
        .onDisappear {
            viewModel.stopHeadTracking()
        }
        .onChange(of: service.state.isConnected) { _, connected in
            if !connected {
                viewModel.stopHeadTracking()
            }
        }
    }

    // MARK: - 1. Noise Control Segmented Picker

    private var noiseControlSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("NOISE CONTROL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))

                Spacer()

                if !service.capabilities.supportsNoiseControl {
                    Text("Not supported on \(service.state.modelName)")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.orange.opacity(0.85))
                }
            }

            Picker("", selection: $viewModel.pendingNoiseMode) {
                ForEach(AirPodsNoiseMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.systemImageName)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(!service.state.isConnected || !service.capabilities.supportsNoiseControl || viewModel.isExecutingWrite)
            .onChange(of: viewModel.pendingNoiseMode) { _, newMode in
                viewModel.setNoiseMode(newMode)
            }

            if service.capabilities.supportsNoiseControl && !service.capabilities.supportsAdaptiveAudio && viewModel.pendingNoiseMode == .adaptive {
                Text("Adaptive Audio requires AirPods Pro (2nd gen).")
                    .font(.system(size: 9.5))
                    .foregroundColor(.orange.opacity(0.8))
            }
        }
    }

    // MARK: - 2. Adaptive Level Slider

    private var adaptiveLevelSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("ADAPTIVE AUDIO LEVEL")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.55))

                Spacer()

                Text("\(Int(viewModel.pendingAdaptiveLevel * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.85))
            }

            let isAdaptiveActive = service.state.noiseMode == .adaptive
            Slider(value: $viewModel.pendingAdaptiveLevel, in: 0.0...1.0) {
                Text("Adaptive Level")
            }
            .disabled(!service.state.isConnected || !isAdaptiveActive || viewModel.isExecutingWrite)
            .onChange(of: viewModel.pendingAdaptiveLevel) { _, newLevel in
                viewModel.setAdaptiveLevel(newLevel)
            }

            if !isAdaptiveActive {
                Text("Adaptive level requires Adaptive mode to be active.")
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
    }

    // MARK: - 3. Feature Toggles

    private var featureTogglesSection: some View {
        VStack(spacing: 8) {
            // Follow My Head Toggle
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Follow my head")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                        Text("3D scene mirrors head pose via motion sensors")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.5))
                    }
                } icon: {
                    Image(systemName: "person.spatialaudio.fill")
                        .foregroundColor(enableFollowHead ? .cyan : .white.opacity(0.5))
                }

                Spacer()

                Toggle("", isOn: $enableFollowHead)
                    .toggleStyle(.switch)
                    .disabled(!service.state.isConnected || !service.capabilities.supportsHeadMotion)
                    .onChange(of: enableFollowHead) { _, enabled in
                        if enabled {
                            viewModel.startHeadTracking {
                                enableFollowHead = false
                            }
                        } else {
                            viewModel.stopHeadTracking()
                        }
                    }
            }

            if !service.capabilities.supportsHeadMotion {
                HStack {
                    Text("Head tracking is not supported on \(service.state.modelName).")
                        .font(.system(size: 9.5))
                        .foregroundColor(.white.opacity(0.45))
                    Spacer()
                }
            }

            // Conversation Awareness Toggle
            if showConversationAwareness {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Conversation Awareness")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Text("Lowers volume when speaking")
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .foregroundColor(viewModel.pendingConversationAwareness ? .green : .white.opacity(0.5))
                    }

                    Spacer()

                    Toggle("", isOn: $viewModel.pendingConversationAwareness)
                        .toggleStyle(.switch)
                        .disabled(!service.state.isConnected || !service.capabilities.supportsConversationAwareness || viewModel.isExecutingWrite)
                        .onChange(of: viewModel.pendingConversationAwareness) { _, enabled in
                            viewModel.setConversationAwareness(enabled)
                        }
                }

                if !service.capabilities.supportsConversationAwareness {
                    HStack {
                        Text("Conversation Awareness requires AirPods Pro (2nd gen).")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                    }
                }
            }

            // One-Bud ANC Toggle
            if showOneBudANC {
                HStack {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Noise Cancellation with One Bud")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                            Text("Allows ANC even when wearing only one earbud")
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    } icon: {
                        Image(systemName: "ear.badge.waveform")
                            .foregroundColor(viewModel.pendingOneBudANC ? .blue : .white.opacity(0.5))
                    }

                    Spacer()

                    Toggle("", isOn: $viewModel.pendingOneBudANC)
                        .toggleStyle(.switch)
                        .disabled(!service.state.isConnected || !service.capabilities.supportsOneBudANC || viewModel.isExecutingWrite)
                        .onChange(of: viewModel.pendingOneBudANC) { _, enabled in
                            viewModel.setOneBudANC(enabled)
                        }
                }

                if !service.capabilities.supportsOneBudANC {
                    HStack {
                        Text("One-bud ANC is not supported on \(service.state.modelName).")
                            .font(.system(size: 9.5))
                            .foregroundColor(.white.opacity(0.45))
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - 4. Volume Section

    private var volumeSection: some View {
        HStack(spacing: 10) {
            Button {
                viewModel.toggleMute()
            } label: {
                Image(systemName: viewModel.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 12))
                    .foregroundColor(viewModel.isMuted ? .red : .white.opacity(0.75))
            }
            .buttonStyle(.plain)

            Slider(value: $viewModel.volumeLevel, in: 0.0...1.0) {
                Text("Volume")
            }
            .onChange(of: viewModel.volumeLevel) { _, val in
                viewModel.setVolume(val)
            }

            Text("\(Int(viewModel.volumeLevel * 100))%")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.65))
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - 5. Always Available Section

    private var alwaysAvailableSection: some View {
        VStack(spacing: 10) {
            // Battery & Ear Details Row
            HStack(spacing: 8) {
                // Left Bud Card
                partStatusBadge(
                    name: "Left Bud",
                    battery: service.state.leftBattery,
                    inEar: service.state.leftInEar
                )

                // Right Bud Card
                partStatusBadge(
                    name: "Right Bud",
                    battery: service.state.rightBattery,
                    inEar: service.state.rightInEar
                )

                // Case Card
                partStatusBadge(
                    name: "Case",
                    battery: service.state.caseBattery,
                    lidOpen: service.state.lidOpen
                )
            }

            // Open Sound Settings Button
            Button {
                service.openSoundSettings()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Open Sound settings")
                        .font(.system(size: 11.5, weight: .medium))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9.5))
                }
                .foregroundColor(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func partStatusBadge(
        name: String,
        battery: AirPodsBatteryPart,
        inEar: Bool? = nil,
        lidOpen: Bool? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name.uppercased())
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(.white.opacity(0.45))

            HStack(spacing: 3) {
                if let level = battery.level {
                    Text("\(level)%")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(level <= 5 ? .red : (level <= 15 ? .orange : .green))
                    if battery.isCharging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                    }
                } else {
                    Text("--")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer()

                if let inEar = inEar {
                    Image(systemName: inEar ? "ear.fill" : "ear")
                        .font(.system(size: 9))
                        .foregroundColor(inEar ? .green : .white.opacity(0.3))
                } else if let lid = lidOpen {
                    Image(systemName: lid ? "door.left.hand.open" : "door.left.hand.closed")
                        .font(.system(size: 9))
                        .foregroundColor(lid ? .orange : .white.opacity(0.3))
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 12))

            Text(message)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(2)

            Spacer()

            Button {
                service.openSoundSettings()
            } label: {
                Text("Sound settings")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.cyan)
                    .underline()
            }
            .buttonStyle(.plain)

            Button {
                withAnimation { viewModel.dismissError() }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                )
        )
    }
}
