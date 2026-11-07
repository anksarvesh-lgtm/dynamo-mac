// SPDX-License-Identifier: MIT
import SwiftUI
import AppKit

public enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case devices = "Connected Devices"
    case trackpad = "Trackpad Monitor"
    case magicMouse = "Magic Mouse Monitor"
    case globalInput = "Global Input Monitor"
    case gestures = "Gesture Customization"
    case permissions = "Permissions"
    case diagnostics = "Network Diagnostics"
    case inspector = "Live Inspector"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .dashboard: return "gauge"
        case .devices: return "iphone.and.arrow.forward"
        case .trackpad: return "hand.tap"
        case .magicMouse: return "magicmouse"
        case .globalInput: return "cursorarrow.motionlines"
        case .gestures: return "hand.raised"
        case .permissions: return "lock.shield"
        case .diagnostics: return "network"
        case .inspector: return "waveform.path.ecg"
        }
    }
}

// MARK: - App State Observable Model
@MainActor
public final class AppState: ObservableObject {
    @Published public var selectedItem: SidebarItem = .dashboard
    @Published public var connectedDeviceName: String? = "Pixel 8 Pro"
    @Published public var isConnected: Bool = true
    @Published public var latencyMs: Int = 8
    @Published public var packetsPerSec: Int = 118
    @Published public var permissionStatus: PermissionStatus = PermissionManager.checkPermissions()

    // Trackpad Live State
    @Published public var activeTouches: Int = 0
    @Published public var magnification: CGFloat = 1.0
    @Published public var rotationDegrees: CGFloat = 0.0
    @Published public var forceStage: ForceTouchStage = .resting
    @Published public var forcePressure: Float = 0.0

    // Magic Mouse Live State
    @Published public var mouseScrollDx: CGFloat = 0
    @Published public var mouseScrollDy: CGFloat = 0
    @Published public var mouseSwipe: String? = nil

    // Live Telemetry Log
    @Published public var telemetryLog: [InputTelemetry] = []

    public let actionRouter = ActionRouter()
    public let server = RemoteInputServer()
    public let globalMonitor = GlobalMouseMonitor()

    public init() {
        setupMonitors()
    }

    private func setupMonitors() {
        globalMonitor.onPointerEvent = { [weak self] telemetry in
            Task { @MainActor in
                self?.appendTelemetry(telemetry)
            }
        }
        globalMonitor.startMonitoring()
    }

    public func appendTelemetry(_ telemetry: InputTelemetry) {
        if telemetryLog.count > 100 {
            telemetryLog.removeFirst(20)
        }
        telemetryLog.append(telemetry)
    }

    public func refreshPermissions() {
        permissionStatus = PermissionManager.checkPermissions()
    }
}

// MARK: - Main Container View
public struct MainContainerView: View {
    @StateObject private var state = AppState()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: $state.selectedItem) { item in
                Label(item.rawValue, systemImage: item.iconName)
                    .tag(item)
            }
            .navigationTitle("MacCompanion")
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch state.selectedItem {
                case .dashboard:
                    DashboardView(state: state)
                case .devices:
                    ConnectedDevicesView(state: state)
                case .trackpad:
                    TrackpadMonitorView(state: state)
                case .magicMouse:
                    MagicMouseMonitorView(state: state)
                case .globalInput:
                    GlobalInputMonitorView(state: state)
                case .gestures:
                    GestureSettingsView(state: state)
                case .permissions:
                    PermissionsView(state: state)
                case .diagnostics:
                    NetworkDiagnosticsView(state: state)
                case .inspector:
                    LiveInspectorView(state: state)
                }
            }
            .frame(minWidth: 500, minHeight: 400)
            .padding(20)
        }
    }
}

// MARK: - Subviews
struct DashboardView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Unified Touchpad & Gesture Dashboard")
                .font(.title2).bold()

            HStack(spacing: 16) {
                StatusCard(
                    title: "Remote Status",
                    value: state.isConnected ? "Connected" : "Disconnected",
                    subtitle: state.connectedDeviceName ?? "None",
                    color: state.isConnected ? .green : .red
                )
                StatusCard(
                    title: "Network Latency",
                    value: "\(state.latencyMs) ms",
                    subtitle: "Round-trip ping/pong",
                    color: .orange
                )
                StatusCard(
                    title: "Packet Throughput",
                    value: "\(state.packetsPerSec) / s",
                    subtitle: "Real-time coalesced stream",
                    color: .blue
                )
            }

            Divider().padding(.vertical, 8)

            Text("Quick Actions").font(.headline)
            HStack(spacing: 12) {
                Button("Trigger Emergency Input Release") {
                    state.server.inputController.emergencyInputCleanup()
                }
                .buttonStyle(.borderedProminent)

                Button("Refresh Permissions") {
                    state.refreshPermissions()
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
    }
}

struct ConnectedDevicesView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connected Devices").font(.title2).bold()
            List {
                HStack {
                    Image(systemName: "iphone.gen3").font(.title2).foregroundColor(.accentColor)
                    VStack(alignment: .leading) {
                        Text(state.connectedDeviceName ?? "Android Touchpad").font(.headline)
                        Text("Active WebSocket session (TLS, Monotonic sequence)").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("Connected").font(.subheadline).foregroundColor(.green)
                }
                .padding(.vertical, 4)
            }
        }
    }
}

struct TrackpadMonitorView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Built-in Trackpad Monitor").font(.title2).bold()
            Text("Interactive AppKit view capturing multi-touch, magnification, rotation, and Force Touch.")
                .font(.subheadline).foregroundColor(.secondary)

            HStack(spacing: 16) {
                MetricPill(label: "Active Touches", value: "\(state.activeTouches)")
                MetricPill(label: "Magnification", value: String(format: "%.2fx", state.magnification))
                MetricPill(label: "Rotation", value: String(format: "%.1f°", state.rotationDegrees))
                MetricPill(label: "Force Stage", value: "\(state.forceStage.rawValue)")
            }

            Divider()

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.3)))
                VStack(spacing: 8) {
                    Image(systemName: "hand.tap").font(.system(size: 36)).foregroundColor(.secondary)
                    Text("Interactive Touch Capture Surface").font(.headline)
                    Text("Pan, scroll, pinch, rotate, or Force Click to inspect live AppKit callbacks")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            .frame(height: 200)

            Spacer()
        }
    }
}

struct MagicMouseMonitorView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Apple Magic Mouse Monitor").font(.title2).bold()
            HStack(spacing: 16) {
                MetricPill(label: "Horizontal Scroll", value: String(format: "%.1f", state.mouseScrollDx))
                MetricPill(label: "Vertical Scroll", value: String(format: "%.1f", state.mouseScrollDy))
                MetricPill(label: "Force Touch Supported", value: "No (Hardware Rule)")
            }
            Spacer()
        }
    }
}

struct GlobalInputMonitorView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global Input Monitor (Observational)").font(.title2).bold()
            Text("Observes pointer movements, clicks, and scroll events across applications without modification.")
                .font(.subheadline).foregroundColor(.secondary)

            List(state.telemetryLog.suffix(15).reversed(), id: \.timestamp) { item in
                HStack {
                    Text(item.eventName).font(.system(.body, design: .monospaced)).bold()
                    Spacer()
                    Text("X: \(Int(item.coordinates.x)), Y: \(Int(item.coordinates.y))")
                        .font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                    Text(item.details).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }
}

struct GestureSettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Gesture-to-Action Mappings").font(.title2).bold()

            Form {
                Section("3-Finger Gestures") {
                    Picker("Swipe Up", selection: .constant(GestureAction.missionControl)) {
                        ForEach(GestureAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Swipe Down", selection: .constant(GestureAction.appExpose)) {
                        ForEach(GestureAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Swipe Left", selection: .constant(GestureAction.previousSpace)) {
                        ForEach(GestureAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Swipe Right", selection: .constant(GestureAction.nextSpace)) {
                        ForEach(GestureAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }

                Section("4-Finger Gestures") {
                    Picker("Swipe Up", selection: .constant(GestureAction.showDesktop)) {
                        ForEach(GestureAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Swipe Down", selection: .constant(GestureAction.launchpad)) {
                        ForEach(GestureAction.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
            }
        }
    }
}

struct PermissionsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("System Permissions").font(.title2).bold()

            VStack(spacing: 12) {
                PermissionRow(
                    name: "Accessibility",
                    granted: state.permissionStatus.isAccessibilityGranted,
                    description: "Required to synthesize mouse movements, clicks, and scroll CGEvent actions.",
                    openSettingsAction: { PermissionManager.openSystemAccessibilitySettings() }
                )
                PermissionRow(
                    name: "Input Monitoring",
                    granted: state.permissionStatus.isInputMonitoringGranted,
                    description: "Required for global pointer observation and event taps.",
                    openSettingsAction: { PermissionManager.openSystemInputMonitoringSettings() }
                )
            }

            Button("Check Permissions Again") {
                state.refreshPermissions()
            }
            .padding(.top, 8)

            Spacer()
        }
    }
}

struct NetworkDiagnosticsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Network Diagnostics").font(.title2).bold()
            LabeledContent("WebSocket Port", value: "\(state.server.port)")
            LabeledContent("Bonjour Service", value: "_maclink-touchpad._tcp")
            LabeledContent("Service Name", value: Host.current().localizedName ?? "Mac")
            LabeledContent("Fail-Safe State", value: state.server.inputController.buttonStateSummary)
            Spacer()
        }
    }
}

struct LiveInspectorView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Live Gesture Inspector").font(.title2).bold()
                Spacer()
                Button("Clear") { state.telemetryLog.removeAll() }
            }

            List(state.telemetryLog.reversed(), id: \.timestamp) { item in
                HStack {
                    Circle()
                        .fill(item.deviceType == "Trackpad" ? Color.blue : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(item.eventName).font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(item.details).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Reusable UI Components
struct StatusCard: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundColor(.secondary)
            Text(value).font(.title).bold().foregroundColor(color)
            Text(subtitle).font(.caption2).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

struct MetricPill: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.headline).bold()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct PermissionRow: View {
    let name: String
    let granted: Bool
    let description: String
    let openSettingsAction: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(granted ? .green : .orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.headline)
                Text(description).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            Button(granted ? "Granted" : "Open Settings") {
                openSettingsAction()
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(10)
    }
}

