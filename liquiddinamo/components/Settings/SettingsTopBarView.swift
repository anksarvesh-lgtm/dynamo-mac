//
//  SettingsTopBarView.swift
//  LiquidDynamo
//
//  Control Center Top Bar with unified search, system health indicators,
//  and quick action buttons to test and control the Dynamic Island.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsTopBarView: View {
    @Binding var searchText: String
    @ObservedObject var stats = SystemStatsService.shared
    @ObservedObject var battery = BatteryStatusViewModel.shared
    @State private var isTestAnimating: Bool = false

    public init(searchText: Binding<String>) {
        self._searchText = searchText
    }

    public var body: some View {
        HStack(spacing: 14) {
            // Global Liquid Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Search control center, modules, settings…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, design: .rounded))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            )
            .frame(maxWidth: 320)

            Spacer()

            // Live Telemetry Mini Status Pill
            HStack(spacing: 10) {
                // CPU chip readout
                HStack(spacing: 4) {
                    Circle()
                        .fill(stats.overallCPU > 60 ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)

                    Text("\(Int(stats.overallCPU))% CPU")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Divider()
                    .frame(height: 12)
                    .opacity(0.3)

                // Battery / Power readout
                HStack(spacing: 4) {
                    Image(systemName: stats.isBatteryCharging ? "battery.100.bolt" : "battery.75")
                        .font(.system(size: 11))
                        .foregroundStyle(stats.isBatteryCharging ? .green : .secondary)

                    Text("\(stats.batteryPercentage)%")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.8)
                    )
            )

            // Quick Actions: Open Dashboard
            Button {
                AppDelegate.shared?.vm.open()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.topthird.inset.filled")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Dashboard")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)

            // Quick Actions: Test Dynamic Notch Expansion
            Button {
                triggerTestAlert()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    Text("Test Notch")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.25), Color.blue.opacity(0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color.cyan.opacity(0.4), lineWidth: 0.8)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            ZStack {
                Color(nsColor: .windowBackgroundColor).opacity(0.35)
                LinearGradient(
                    colors: [Color.white.opacity(0.04), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        )
        .overlay(
            Divider().opacity(0.2),
            alignment: .bottom
        )
    }

    private func triggerTestAlert() {
        let payload = AlertPayload(
            id: "test.notch.\(UUID().uuidString)",
            kind: .custom(title: "Liquid Glass Active", subtitle: "Dynamic Island Engine 120fps", icon: "sparkles"),
            title: "Liquid Glass Active",
            subtitle: "Dynamic Island 120fps",
            iconName: "sparkles",
            iconColor: .cyan,
            dwellDuration: 3.5
        )
        IslandController.shared.showAlert(payload: payload)
    }
}
