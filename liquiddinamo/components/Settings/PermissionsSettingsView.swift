//
//  PermissionsSettingsView.swift
//  LiquidDynamo
//
//  Permissions Section: unified list of all permissions, status badges,
//  one-line reasons, Fix buttons opening System Settings, and stale-Accessibility repair steps.
//

import AppKit
import Defaults
import SwiftUI

public struct PermissionsSettingsView: View {
    @ObservedObject private var permManager = AppPermissionManager.shared

    public init() {}

    public var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LiquidDynamo functions immediately without required permissions. Grant permissions only for the specific modules and system features you wish to enable.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                ForEach(AppPermissionKind.allCases) { kind in
                    permissionRow(for: kind)
                }
            } header: {
                HStack(spacing: 8) {
                    Text("Permissions Status")
                    Spacer()
                    if permManager.isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 14, height: 14)
                    }
                    Button {
                        permManager.refreshAll()
                        permManager.startPolling()
                    } label: {
                        Label("Check again", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.effectiveAccent)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .foregroundStyle(.orange)
                        Text("Stale Accessibility Permission Repair")
                            .font(.headline)
                    }

                    Text("macOS sometimes fails to grant accessibility permissions after updating an app, even if the toggle appears ON in System Settings. If the notch does not open or respond to gestures:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        stepRow(number: 1, text: "Click 'Fix' on Accessibility above to open System Settings.")
                        stepRow(number: 2, text: "Select LiquidDynamo and click the minus (-) button to remove it.")
                        stepRow(number: 3, text: "Click the plus (+) button to add LiquidDynamo again, or toggle it on and restart the app.")
                    }
                    .padding(.vertical, 4)

                    Button("Open Accessibility Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                            permManager.startPolling(for: .accessibility)
                        }
                    }
                    .controlSize(.regular)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Troubleshooting & Repair")
            }
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .onAppear {
            permManager.refreshAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permManager.refreshAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notif in
            if let win = notif.object as? NSWindow, win.title.contains("Settings") {
                permManager.refreshAll()
            }
        }
    }

    @ViewBuilder
    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .fontWeight(.bold)
                .foregroundStyle(Color.effectiveAccent)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func permissionRow(for kind: AppPermissionKind) -> some View {
        let status = permManager.status(for: kind)
        let isAllowed = status == .allowed
        let isRecentlyGranted = permManager.recentlyGrantedKinds.contains(kind)

        HStack(alignment: .center, spacing: 12) {
            Image(systemName: kind.iconName)
                .font(.system(size: 20))
                .frame(width: 28, height: 28)
                .foregroundStyle(isAllowed ? Color.green : Color.orange)
                .scaleEffect(isRecentlyGranted ? 1.15 : 1.0)
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isRecentlyGranted)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(kind.displayName)
                        .font(.headline)

                    badgeView(for: status, isRecentlyGranted: isRecentlyGranted)
                }

                Text(kind.reasonText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            if !isAllowed {
                HStack(spacing: 6) {
                    Button("Grant") {
                        Task {
                            await permManager.request(kind: kind)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button("Settings") {
                        permManager.openSettings(for: kind)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .transition(.opacity)
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Allowed")
                        .font(.caption.bold())
                        .foregroundStyle(.green)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.vertical, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: status)
    }

    @ViewBuilder
    private func badgeView(for status: AppPermissionStatus, isRecentlyGranted: Bool) -> some View {
        switch status {
        case .allowed:
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                Text("Allowed")
            }
            .font(.caption2.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(Color.green.opacity(0.18))
            .foregroundStyle(.green)
            .clipShape(Capsule())
            .scaleEffect(isRecentlyGranted ? 1.08 : 1.0)
            .animation(.spring(response: 0.35, dampingFraction: 0.6), value: isRecentlyGranted)

        case .needsPermission:
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 8, weight: .bold))
                Text("Needs permission")
            }
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.18))
            .foregroundStyle(.orange)
            .clipShape(Capsule())

        case .needsRepair:
            HStack(spacing: 3) {
                Image(systemName: "wrench.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("Needs repair")
            }
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.18))
            .foregroundStyle(.red)
            .clipShape(Capsule())

        case .notNeeded:
            Text("Not needed")
                .font(.caption2.bold())
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.15))
                .foregroundStyle(.secondary)
                .clipShape(Capsule())
        }
    }
}
