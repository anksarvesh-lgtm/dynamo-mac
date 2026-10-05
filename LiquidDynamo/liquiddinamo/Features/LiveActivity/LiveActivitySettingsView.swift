//
//  LiveActivitySettingsView.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import Defaults
import SwiftUI

/// Settings pane for configuring Live Activity sources, severities, durations, and native system HUD suppression.
public struct LiveActivitySettingsView: View {
    @ObservedObject private var catalog = ModuleCatalog.shared
    @Default(.hudReplacement) var hudReplacement
    @State private var accessibilityAuthorized: Bool = false
    @State private var selectedFilter: SourceFilter = .all

    public enum SourceFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case huds = "HUDs"
        case alerts = "Alerts"
        case ongoing = "Ongoing"

        public var id: String { rawValue }
    }

    public init() {}

    public var body: some View {
        Form {
            // MARK: - Native System HUD Suppression
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Hide Native macOS System HUD")
                                .font(.headline)
                            Text("Replaces Apple's standard volume, display brightness, and keyboard backlight bezel overlays with LiquidDynamo's drop HUD.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { catalog.hideSystemHUD },
                            set: { catalog.hideSystemHUD = $0 }
                        ))
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.large)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled")
                            .foregroundColor(.blue)
                        Text("Safe, non-fragile interception: Intercepts media key events via standard CGEventTap without modifying system daemons or violating SIP.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .background(Color.blue.opacity(0.08))
                    .cornerRadius(8)

                    if catalog.hideSystemHUD {
                        switch MediaKeyInterceptor.shared.status {
                        case .enabled:
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Enabled: Media keys intercepted and native popup suppressed.")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        case .needsPermission:
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow)
                                    Text("Accessibility permission required to intercept hardware keys.")
                                        .font(.caption)
                                    Spacer()
                                    Button("Open Settings") {
                                        MediaKeyInterceptor.shared.openAccessibilitySettings()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                }
                                Text("Already enabled but not working? Remove LiquidDynamo from the list with the minus button, add it again from /Applications, then restart the app.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.yellow.opacity(0.12))
                            .cornerRadius(8)
                        case .repairNeeded:
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: "exclamationmark.shield.fill")
                                        .foregroundColor(.orange)
                                    Text("Permission repair needed (stale Accessibility grant).")
                                        .font(.caption)
                                    Spacer()
                                    Button("Open Settings") {
                                        MediaKeyInterceptor.shared.openAccessibilitySettings()
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    Button("Restart") {
                                        MediaKeyInterceptor.shared.restartApp()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                Text("Already enabled but not working? Remove LiquidDynamo from the list with the minus button, add it again from /Applications, then restart the app.")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(8)
                        case .unsupported:
                            Text("Not supported on this macOS version.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        case .disabled:
                            EmptyView()
                        }
                    }
                }
            } header: {
                Text("System HUD Integration")
            }

            // MARK: - Live Activity Sources
            Section {
                Picker("Filter", selection: $selectedFilter) {
                    ForEach(SourceFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.vertical, 4)

                ForEach(filteredModules) { item in
                    SourceRowView(item: item, catalog: catalog)
                }
            } header: {
                HStack {
                    Text("Live Activity Sources (\(filteredModules.count))")
                    Spacer()
                    Text("Custom Severity & Duration")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            checkAccessibility()
        }
    }

    private var filteredModules: [ModuleSourceItem] {
        catalog.modules.filter { module in
            switch selectedFilter {
            case .all:
                return true
            case .huds:
                return module.defaultKind == .hud
            case .alerts:
                return module.defaultKind == .alert || module.defaultKind == .notification
            case .ongoing:
                return module.defaultKind == .ongoing || module.defaultKind == .progress
            }
        }
    }

    private func checkAccessibility() {
        Task {
            accessibilityAuthorized = await XPCHelperClient.shared.isAccessibilityAuthorized()
        }
    }
}

// MARK: - Individual Source Configuration Row

private struct SourceRowView: View {
    let item: ModuleSourceItem
    @ObservedObject var catalog: ModuleCatalog

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: item.iconName)
                    .font(.system(size: 18))
                    .foregroundColor(catalog.sourceSeverity(for: item.id).color)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(item.displayName)
                            .font(.system(size: 14, weight: .medium))

                        if item.isExperimental {
                            Text("EXPERIMENTAL")
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.2))
                                .foregroundColor(.purple)
                                .cornerRadius(4)
                        }

                        if item.id == "caps_lock" {
                            Text("AX Required")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .foregroundColor(.secondary)
                                .cornerRadius(4)
                        }
                    }

                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { catalog.isSourceEnabled(item.id) },
                    set: { catalog.setSourceEnabled(item.id, enabled: $0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()

                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                Divider()
                    .padding(.vertical, 2)

                HStack(spacing: 24) {
                    // Severity Picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Severity Tint")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: Binding(
                            get: { catalog.sourceSeverity(for: item.id) },
                            set: { catalog.setSourceSeverity(for: item.id, severity: $0) }
                        )) {
                            ForEach(LiveActivitySeverity.allCases, id: \.self) { sev in
                                HStack {
                                    Circle()
                                        .fill(sev.color)
                                        .frame(width: 8, height: 8)
                                    Text(sev.rawValue.capitalized)
                                }
                                .tag(sev)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    // Duration Slider
                    if item.defaultKind != .ongoing {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Duration")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(String(format: "%.1f s", catalog.sourceDuration(for: item.id)))
                                    .font(.caption)
                                    .bold()
                            }

                            Slider(
                                value: Binding(
                                    get: { catalog.sourceDuration(for: item.id) },
                                    set: { catalog.setSourceDuration(for: item.id, duration: $0) }
                                ),
                                in: 1.0...8.0,
                                step: 0.5
                            )
                            .frame(width: 140)
                        }
                    }
                }
                .padding(.leading, 38)
            }
        }
        .padding(.vertical, 4)
    }
}
