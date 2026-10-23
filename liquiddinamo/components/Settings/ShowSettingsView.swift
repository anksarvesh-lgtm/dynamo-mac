//
//  ShowSettingsView.swift
//  LiquidDynamo
//
//  Show Section: Modules with toggle, one-line explanation, status badge,
//  reordering, and chevron detail sheets.
//

import AppKit
import Defaults
import SwiftUI

public struct ShowSettingsView: View {
    @ObservedObject var coordinator = LiquidViewCoordinator.shared
    @ObservedObject private var permManager = AppPermissionManager.shared

    @Default(.showMedia) private var showMedia
    @Default(.showNotchOSD) private var showNotchOSD
    @Default(.showBatteryIndicator) private var showBatteryIndicator
    @Default(.showCalendar) private var showCalendar
    @Default(.liquidShelf) private var liquidShelf
    @Default(.showLiveActivities) private var showLiveActivities
    @Default(.showDashboardSystemInfo) private var showDashboardSystemInfo
    @Default(.showDashboardDropper) private var showDashboardDropper
    @Default(.showDashboardClipboard) private var showDashboardClipboard
    @Default(.showDashboardDevices) private var showDashboardDevices

    var searchText: String

    // Detail sheet states
    @State private var activeDetailModule: String? = nil

    // Module ordering
    @State private var moduleOrder: [String] = [
        "media", "hud", "battery", "calendar", "shelf", "liveactivities"
    ]

    public init(searchText: String = "") {
        self.searchText = searchText
    }

    public var body: some View {
        Form {
            Section {
                Text("Toggle the modules you want your liquid notch to display. Click any module's chevron to configure its detailed options.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Toggle("System Telemetry", isOn: $showDashboardSystemInfo)
                    Text("Real-time CPU load, memory breakdown, thermal state, and live network I/O outside the notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider().opacity(0.3)

                    Toggle("Temporary Dropper Shelf", isOn: $showDashboardDropper)
                    Text("Drag files over the notch to hold them temporarily in droplet masks without writing to disk.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider().opacity(0.3)

                    Toggle("Connected Devices", isOn: $showDashboardDevices)
                    Text("Shows 3D rotating models and live telemetry for headphones, SSDs, displays, and controllers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider().opacity(0.3)

                    Toggle("Privacy-First Clipboard History", isOn: $showDashboardClipboard)
                    Text("Retains up to 5 unpinned clippings in volatile memory. Passwords and concealed data are strictly excluded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if showDashboardClipboard {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text("Privacy Protected")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                            Text("Automatic exclusion applies to 1Password, Bitwarden, Apple Passwords, KeePassXC, and all concealed pasteboard markers. Clipboard tracking halts immediately if screen recording or sharing is active.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        HStack {
                            Button("Clear History") {
                                ClipboardHistoryService.shared.clearHistory()
                            }
                            .controlSize(.small)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Productivity Dashboard Regions")
            }

            Section {
                List {
                    ForEach(filteredModules, id: \.self) { moduleId in
                        moduleRow(for: moduleId)
                    }
                    .onMove(perform: moveModules)
                }
                .frame(minHeight: 380)
            } header: {
                HStack {
                    Text("Modules")
                    Spacer()
                    Text("Drag to reorder")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .sheet(item: detailBinding) { detailId in
            detailSheetView(for: detailId.id)
        }
    }

    private var filteredModules: [String] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return moduleOrder
        }
        let q = searchText.lowercased()
        return moduleOrder.filter { id in
            moduleTitle(for: id).lowercased().contains(q) ||
            moduleDescription(for: id).lowercased().contains(q)
        }
    }

    private func moveModules(from source: IndexSet, to destination: Int) {
        moduleOrder.move(fromOffsets: source, toOffset: destination)
    }

    private var detailBinding: Binding<DetailIdentifiable?> {
        Binding(
            get: {
                if let id = activeDetailModule {
                    return DetailIdentifiable(id: id)
                }
                return nil
            },
            set: { activeDetailModule = $0?.id }
        )
    }

    @ViewBuilder
    private func moduleRow(for id: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .font(.system(size: 13))

            Image(systemName: moduleIcon(for: id))
                .font(.system(size: 18))
                .foregroundStyle(isModuleEnabled(for: id) ? Color.effectiveAccent : Color.secondary)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(moduleTitle(for: id))
                        .font(.headline)

                    statusBadge(for: id)
                }

                Text(moduleDescription(for: id))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: moduleBinding(for: id))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.regular)

            Button {
                activeDetailModule = id
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Configure \(moduleTitle(for: id))")
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func statusBadge(for id: String) -> some View {
        let isEnabled = isModuleEnabled(for: id)
        let status = modulePermissionStatus(for: id)

        if !isEnabled {
            Text("Off")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        } else if status == .needsPermission {
            Text("Needs permission")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.18))
                .foregroundStyle(.orange)
                .clipShape(Capsule())
        } else {
            Text("Active")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.green.opacity(0.18))
                .foregroundStyle(.green)
                .clipShape(Capsule())
        }
    }

    private func isModuleEnabled(for id: String) -> Bool {
        switch id {
        case "media": return Defaults[.showMedia]
        case "hud": return Defaults[.showNotchOSD]
        case "battery": return Defaults[.showBatteryIndicator]
        case "calendar": return Defaults[.showCalendar]
        case "shelf": return Defaults[.liquidShelf]
        case "liveactivities": return Defaults[.showLiveActivities]
        default: return false
        }
    }

    private func moduleBinding(for id: String) -> Binding<Bool> {
        switch id {
        case "media":
            return Binding(
                get: { Defaults[.showMedia] },
                set: {
                    Defaults[.showMedia] = $0
                    if $0 {
                        Task { await AppPermissionManager.shared.requestPermission(for: .music) }
                    }
                }
            )
        case "hud":
            return Binding(
                get: { Defaults[.showNotchOSD] },
                set: { Defaults[.showNotchOSD] = $0 }
            )
        case "battery":
            return Binding(
                get: { Defaults[.showBatteryIndicator] },
                set: { Defaults[.showBatteryIndicator] = $0 }
            )
        case "calendar":
            return Binding(
                get: { Defaults[.showCalendar] },
                set: {
                    Defaults[.showCalendar] = $0
                    if $0 {
                        Task { await AppPermissionManager.shared.requestPermission(for: .calendar) }
                    }
                }
            )
        case "shelf":
            return Binding(
                get: { Defaults[.liquidShelf] },
                set: { Defaults[.liquidShelf] = $0 }
            )
        case "liveactivities":
            return Binding(
                get: { Defaults[.showLiveActivities] },
                set: { Defaults[.showLiveActivities] = $0 }
            )
        default:
            return .constant(false)
        }
    }

    private func modulePermissionStatus(for id: String) -> AppPermissionStatus {
        switch id {
        case "media":
            return permManager.status(for: .music)
        case "calendar":
            return permManager.status(for: .calendar)
        default:
            return .allowed
        }
    }

    private func moduleTitle(for id: String) -> String {
        switch id {
        case "media": return "Media Player"
        case "hud": return "Volume & Brightness HUD"
        case "battery": return "Battery & Power"
        case "calendar": return "Calendar & Up Next"
        case "shelf": return "Liquid Shelf"
        case "liveactivities": return "Live Activities & Alerts"
        default: return id
        }
    }

    private func moduleDescription(for id: String) -> String {
        switch id {
        case "media":
            return "Displays album art, song title, artist, and media controls emerging from the notch."
        case "hud":
            return "Fluid liquid volume, brightness, and keyboard backlight indicators."
        case "battery":
            return "Shows battery percentage, charging animations, and power level warnings."
        case "calendar":
            return "Shows upcoming meetings, event countdowns, and quick schedule details."
        case "shelf":
            return "A drag-and-drop holding tray emerging from the notch for files and links."
        case "liveactivities":
            return "Fluid alerts for AirPods, timers, downloads, and system events."
        default:
            return ""
        }
    }

    private func moduleIcon(for id: String) -> String {
        switch id {
        case "media": return "music.note"
        case "hud": return "dial.medium.fill"
        case "battery": return "battery.100.bolt"
        case "calendar": return "calendar"
        case "shelf": return "tray.and.arrow.down.fill"
        case "liveactivities": return "sparkles.rectangle.stack.fill"
        default: return "circle"
        }
    }

    @ViewBuilder
    private func detailSheetView(for id: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(moduleTitle(for: id))
                    .font(.title2.bold())
                Spacer()
                Button("Done") {
                    activeDetailModule = nil
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            ScrollView {
                switch id {
                case "media":
                    Media()
                        .padding()
                case "hud":
                    HUD()
                        .padding()
                case "battery":
                    Charge()
                        .padding()
                case "calendar":
                    CalendarSettings()
                        .padding()
                case "shelf":
                    Shelf()
                        .padding()
                case "liveactivities":
                    LiveActivitySettingsView()
                        .padding()
                default:
                    EmptyView()
                }
            }
        }
        .frame(minWidth: 540, minHeight: 480)
    }
}

private struct DetailIdentifiable: Identifiable {
    let id: String
}
