//
//  OnboardingView.swift
//  LiquidDynamo
//
//  Streamlined First-Run Setup (Onboarding):
//  1. "What do you want your notch to show?" (Presets + Express jump)
//  2. "How should it behave?" (Hover/Click, Display, Login, Look preview)
//  3. "Allow what you picked." (Gated permissions only, never blocks finish)
//  4. Finish (Live notch demo + menu bar instruction)
//

import AppKit
import Defaults
import Foundation
import LaunchAtLogin
import SwiftUI

public enum SetupPreset: String, CaseIterable, Identifiable {
    case essentials = "Essentials"
    case media = "Media and Music"
    case productivity = "Productivity"
    case everything = "Everything"
    case custom = "Custom"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .essentials: return "sparkles"
        case .media: return "music.note"
        case .productivity: return "calendar.badge.clock"
        case .everything: return "square.grid.2x2.fill"
        case .custom: return "slider.horizontal.3"
        }
    }

    public var oneLineDescription: String {
        switch self {
        case .essentials:
            return "Volume & brightness HUDs, battery percentage, and music playback."
        case .media:
            return "Now playing art, audio spectrogram visualizer, and media controls."
        case .productivity:
            return "Calendar schedule, countdown timers, reminders, and notifications."
        case .everything:
            return "All modules including devices, clipboard shelf, mirror, and live activities."
        case .custom:
            return "Choose exactly which modules you want active in your notch."
        }
    }
}

public enum LookChoice: String, CaseIterable, Identifiable {
    case clear = "Clear"
    case balanced = "Balanced"
    case solid = "Solid"

    public var id: String { rawValue }

    public var transparencyValue: Double {
        switch self {
        case .clear: return 0.85
        case .balanced: return 0.50
        case .solid: return 0.15
        }
    }

    public var description: String {
        switch self {
        case .clear: return "Maximum liquid transparency & refraction"
        case .balanced: return "Soft frosted glass with clear highlights"
        case .solid: return "High contrast deep liquid container"
        }
    }
}

public enum OnboardingStep: Int, CaseIterable {
    case welcome = 1
    case behavior = 2
    case permissions = 3
    case finish = 4

    public static var musicPermission: OnboardingStep { .permissions }
}

struct OnboardingView: View {
    @State private var currentStep: Int = 1 // 1: Modules, 2: Behavior, 3: Permissions, 4: Finish
    @State private var selectedPreset: SetupPreset = .essentials
    @State private var selectedLook: LookChoice = .balanced
    @State private var openOnHover: Bool = Defaults[.openNotchOnHover]
    @State private var openOnDrag: Bool = Defaults[.openNotchOnDrag]
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var showOnAllDisplays: Bool = Defaults[.showOnAllDisplays]
    @State private var customSearchText: String = ""

    // Custom Module Selection Checklist
    @State private var customModules: [String: Bool] = [
        "media": true,
        "volume": true,
        "brightness": true,
        "battery": true,
        "calendar": false,
        "reminders": false,
        "shelf": false,
        "clipboard": false,
        "devices": false,
        "mirror": false
    ]

    @ObservedObject private var permManager = AppPermissionManager.shared

    let onFinish: () -> Void
    let onOpenSettings: () -> Void

    init(step: OnboardingStep = .welcome, onFinish: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self._currentStep = State(initialValue: step.rawValue)
        self.onFinish = onFinish
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header Progress Bar & Navigation
            headerView

            Divider()

            // Main Step Content
            ZStack {
                switch currentStep {
                case 1:
                    screen1WhatToShow
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 2:
                    screen2HowToBehavior
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 3:
                    screen3AllowWhatYouPicked
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                case 4:
                    screen4Finish
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer Navigation Buttons
            footerView
        }
        .frame(width: 520, height: 620)
        .background(
            VisualEffectView(material: .windowBackground, blendingMode: .behindWindow)
                .ignoresSafeArea()
        )
        .onAppear {
            permManager.refreshAll()
        }
    }

    // MARK: - Header & Progress Dots

    private var headerView: some View {
        HStack {
            if currentStep > 1 && currentStep < 4 {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep -= 1
                    }
                }) {
                    Label("Back", systemImage: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            } else {
                Spacer().frame(width: 50)
            }

            Spacer()

            // Progress Dots (1 to 3)
            if currentStep < 4 {
                HStack(spacing: 6) {
                    ForEach(1...3, id: \.self) { step in
                        Circle()
                            .fill(step == currentStep ? Color.effectiveAccent : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
            } else {
                Text("Complete")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Skip Button
            if currentStep < 4 {
                Button("Skip") {
                    applyPresetChoices()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep = 4
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            } else {
                Spacer().frame(width: 50)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Screen 1: What do you want your notch to show?

    private var screen1WhatToShow: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("What do you want your notch to show?")
                    .font(.system(size: 20, weight: .bold))
                Text("Pick a setup. You can always change individual modules later.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(SetupPreset.allCases) { preset in
                        presetCard(preset)
                    }

                    if selectedPreset == .custom {
                        customModuleChecklist
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            // Express Jump Button
            HStack {
                Spacer()
                Button(action: {
                    selectedPreset = .essentials
                    applyPresetChoices()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep = 4
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .foregroundStyle(.yellow)
                        Text("Use recommended settings (Express)")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .tint(.effectiveAccent)
                Spacer()
            }
            .padding(.bottom, 12)
        }
    }

    private func presetCard(_ preset: SetupPreset) -> some View {
        let isSelected = selectedPreset == preset
        return Button(action: {
            selectedPreset = preset
            updateCustomSelection(for: preset)
        }) {
            HStack(spacing: 14) {
                Image(systemName: preset.iconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isSelected ? Color.effectiveAccent : Color.primary)
                    .frame(width: 32, height: 32)
                    .background(
                        Circle().fill(isSelected ? Color.effectiveAccent.opacity(0.18) : Color.white.opacity(0.06))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(preset.rawValue)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(preset.oneLineDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.effectiveAccent : Color.secondary.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.effectiveAccent.opacity(0.12) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(isSelected ? Color.effectiveAccent.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var customModuleChecklist: some View {
        VStack(spacing: 6) {
            TextField("Search modules…", text: $customSearchText)
                .textFieldStyle(.roundedBorder)
                .padding(.bottom, 4)

            let modules = [
                ("media", "Media & Music", "music.note"),
                ("volume", "Volume HUD", "speaker.wave.2"),
                ("brightness", "Brightness HUD", "sun.max"),
                ("battery", "Battery Level", "battery.100.bolt"),
                ("calendar", "Calendar Events", "calendar"),
                ("reminders", "Reminders", "checklist"),
                ("shelf", "Temporary Dropper Tray", "tray.and.arrow.down.fill"),
                ("clipboard", "Privacy Clipboard History", "doc.on.clipboard"),
                ("devices", "Connected 3D Devices", "headphones"),
                ("mirror", "Camera Mirror", "camera")
            ]

            let filtered = customSearchText.isEmpty
                ? modules
                : modules.filter { $0.1.localizedCaseInsensitiveContains(customSearchText) }

            ForEach(filtered, id: \.0) { mod in
                Toggle(isOn: Binding(
                    get: { customModules[mod.0] ?? false },
                    set: { customModules[mod.0] = $0 }
                )) {
                    Label(mod.1, systemImage: mod.2)
                        .font(.system(size: 12))
                }
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.2))
        )
    }

    // MARK: - Screen 2: How should it behave?
 
    private var screen2HowToBehavior: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("How should it behave?")
                    .font(.system(size: 20, weight: .bold))
                Text("Choose your interaction and preview the look directly in your notch.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 16) {
                // Open Trigger
                VStack(alignment: .leading, spacing: 8) {
                    Text("OPEN NOTCH")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    Picker("Open Mode", selection: $openOnHover) {
                        Text("On Click (Recommended)").tag(false)
                        Text("On Hover").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: openOnHover) { val in
                        Defaults[.openNotchOnHover] = val
                    }

                    Toggle("Open on dragging file over notch", isOn: $openOnDrag)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .onChange(of: openOnDrag) { val in
                            Defaults[.openNotchOnDrag] = val
                        }

                    Toggle("Show live CPU and network beside the notch?", isOn: Binding(
                        get: { Defaults[.enableSideReadouts] },
                        set: { Defaults[.enableSideReadouts] = $0 }
                    ))
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                }

                // Look / Transparency (Live preview applied to notch)
                VStack(alignment: .leading, spacing: 8) {
                    Text("LOOK (PREVIEWS LIVE IN NOTCH)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        ForEach(LookChoice.allCases) { look in
                            Button(action: {
                                selectedLook = look
                                Defaults[.islandTransparency] = look.transparencyValue
                            }) {
                                VStack(spacing: 4) {
                                    Text(look.rawValue)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(selectedLook == look ? .white : .secondary)
                                    Text(look == .clear ? "Water" : (look == .balanced ? "Glass" : "Deep"))
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedLook == look ? Color.effectiveAccent.opacity(0.18) : Color.white.opacity(0.04))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .strokeBorder(selectedLook == look ? Color.effectiveAccent : Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Displays
                VStack(alignment: .leading, spacing: 8) {
                    Text("DISPLAY SETUP")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)

                    let isNotched = NotchSafeAreaEngine.shared.currentGeometry.isNotched
                    HStack {
                        Image(systemName: isNotched ? "laptopcomputer" : "display")
                            .font(.system(size: 14))
                            .foregroundStyle(Color.effectiveAccent)
                        Text(isNotched ? "Hardware Notch Detected" : "Standard Display (Floating Liquid Mode)")
                            .font(.system(size: 12, weight: .medium))
                        Spacer()
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))

                    Toggle("Show on all connected displays", isOn: $showOnAllDisplays)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .onChange(of: showOnAllDisplays) { val in
                            Defaults[.showOnAllDisplays] = val
                        }
                }

                // Launch at Login
                Toggle("Launch LiquidDynamo at login", isOn: $launchAtLogin)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 12))
                    .onChange(of: launchAtLogin) { val in
                        LaunchAtLogin.isEnabled = val
                    }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    // MARK: - Screen 3: Allow what you picked

    private var screen3AllowWhatYouPicked: some View {
        let needed = permManager.neededPermissions(forModuleKeys: activeModuleKeys)

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Allow what you picked")
                    .font(.system(size: 20, weight: .bold))
                Text("Only permissions needed for your chosen modules are shown below.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if needed.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.green)
                    Text("Zero Extra Permissions Required!")
                        .font(.system(size: 14, weight: .semibold))
                    Text("The modules you picked (Volume, Brightness, and Battery) work seamlessly without needing special system access.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(needed) { perm in
                            permissionRow(perm)
                        }
                    }
                    .padding(.top, 4)
                }

                // Allow All Needed Button
                HStack {
                    Spacer()
                    Button(action: {
                        Task {
                            for perm in needed {
                                await permManager.request(kind: perm)
                            }
                        }
                    }) {
                        Label("Allow All Needed", systemImage: "lock.open.fill")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.effectiveAccent)
                    Spacer()
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
    }

    private func permissionRow(_ perm: AppPermissionKind) -> some View {
        let status = permManager.status(for: perm)
        let isAllowed = status == .allowed

        return HStack(spacing: 12) {
            Image(systemName: perm.iconName)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isAllowed ? .green : Color.effectiveAccent)
                .frame(width: 28, height: 28)
                .background(Circle().fill((isAllowed ? Color.green : Color.effectiveAccent).opacity(0.15)))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(perm.displayName)
                        .font(.system(size: 12.5, weight: .semibold))

                    if isAllowed {
                        Text("Allowed")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    } else {
                        Text("Needs permission")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                }

                Text(perm.reasonText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !isAllowed {
                Button("Allow") {
                    Task {
                        await permManager.request(kind: perm)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.04))
        )
    }

    // MARK: - Screen 4: Finish & Live Demo

    private var screen4Finish: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.effectiveAccent.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: "sparkles")
                    .font(.system(size: 38))
                    .foregroundStyle(Color.effectiveAccent)
            }

            Text("You're All Set!")
                .font(.system(size: 24, weight: .bold))

            Text("Look up at your notch right now to see your liquid info stream flow into place.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 8) {
                Image("MenuBarIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
                    .foregroundStyle(Color.effectiveAccent)
                Text("Click the menu bar icon anytime to open Settings or toggle modules.")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))

            Spacer()

            Button("Get Started") {
                finishSetup()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.effectiveAccent)
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 24)
        }
        .onAppear {
            triggerLiveDemo()
        }
    }

    // MARK: - Footer Navigation

    private var footerView: some View {
        HStack {
            Spacer()

            if currentStep < 4 {
                Button("Continue") {
                    if currentStep == 1 {
                        applyPresetChoices()
                    }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.effectiveAccent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private var activeModuleKeys: Set<String> {
        switch selectedPreset {
        case .essentials:
            return ["volume", "brightness", "battery", "media"]
        case .media:
            return ["media", "volume"]
        case .productivity:
            return ["calendar", "reminders"]
        case .everything:
            return ["media", "volume", "brightness", "battery", "calendar", "reminders", "shelf", "devices", "mirror"]
        case .custom:
            return Set(customModules.filter { $0.value }.map { $0.key })
        }
    }

    private func updateCustomSelection(for preset: SetupPreset) {
        switch preset {
        case .essentials:
            customModules = ["media": true, "volume": true, "brightness": true, "battery": true, "calendar": false, "reminders": false, "shelf": false, "devices": false, "mirror": false]
        case .media:
            customModules = ["media": true, "volume": true, "brightness": false, "battery": false, "calendar": false, "reminders": false, "shelf": false, "devices": false, "mirror": false]
        case .productivity:
            customModules = ["media": false, "volume": false, "brightness": false, "battery": false, "calendar": true, "reminders": true, "shelf": false, "devices": false, "mirror": false]
        case .everything:
            customModules = ["media": true, "volume": true, "brightness": true, "battery": true, "calendar": true, "reminders": true, "shelf": true, "devices": true, "mirror": true]
        case .custom:
            break
        }
    }

    private func applyPresetChoices() {
        let keys = activeModuleKeys
        Defaults[.showNotchOSD] = keys.contains("volume") || keys.contains("brightness")
        Defaults[.showBatteryIndicator] = keys.contains("battery")
        Defaults[.showCalendar] = keys.contains("calendar")
        Defaults[.liquidShelf] = keys.contains("shelf")
        Defaults[.showDashboardDropper] = keys.contains("shelf")
        Defaults[.showDashboardClipboard] = keys.contains("clipboard")
        Defaults[.showDashboardDevices] = keys.contains("devices")
        Defaults[.enableBluetoothDeviceShowcase] = keys.contains("devices")
        Defaults[.showMirror] = keys.contains("mirror")
    }

    private func triggerLiveDemo() {
        // Trigger live notch stream demonstration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            DynamicIslandHub.shared.triggerTrackChangeAnnouncement(title: "Liquid Flow", artist: "LiquidDynamo")
        }
    }

    private func finishSetup() {
        applyPresetChoices()
        Defaults[.setupVersion] = 1
        LiquidViewCoordinator.shared.firstLaunch = false
        onFinish()
    }
}
