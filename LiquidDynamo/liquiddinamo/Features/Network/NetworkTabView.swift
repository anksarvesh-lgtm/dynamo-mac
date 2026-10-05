//
//  NetworkTabView.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Charts
import Defaults
import SwiftUI

/// Complete Network Dashboard Tab view.
///
/// Features:
/// - Top row: Connection status, interface type, SSID or "Allow network name" button, and on-demand Public IP button.
/// - Wi-Fi card: Signal strength (bars + dBm), noise, SNR with plain-language quality rating (Excellent, Good, Fair, Poor), channel, band, link speed, security, and local IP.
/// - Live speed card: Real-time download & upload speeds with a 60-second rolling graph.
/// - Speed test card: On-demand Apple networkQuality test with progress, last result, and 20-item local history.
/// - Zero idle CPU: Fully halts polling and background timers when tab is hidden.
public struct NetworkTabView: View {
    @ObservedObject private var connectionService = ConnectionStatusService.shared
    @ObservedObject private var wifiService = WiFiInfoService.shared
    @ObservedObject private var throughputService = NetworkThroughputService.shared
    @ObservedObject private var speedTestService = SpeedTestService.shared
    @ObservedObject private var publicIPService = PublicIPService.shared
    @Default(.showCollapsedNetworkWing) var showCollapsedNetworkWing

    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                topRowCard
                wiFiCard
                liveSpeedCard
                SpeedTestView()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            wifiService.setTabVisible(true)
            throughputService.start()
            connectionService.start()
        }
        .onDisappear {
            wifiService.setTabVisible(false)
            if !showCollapsedNetworkWing {
                throughputService.stop()
            }
            connectionService.stop()
        }
    }

    // MARK: - Top Row Card

    private var topRowCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                // Connection Status Pill
                HStack(spacing: 5) {
                    Circle()
                        .fill(connectionService.isOnline ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(connectionService.isOnline ? "Online" : "Offline")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(connectionService.isOnline ? .primary : .secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .clipShape(Capsule())

                // Interface Type
                HStack(spacing: 5) {
                    Premium3DIconView(name: connectionService.interfaceType.iconName, size: 14, interactive: false)
                    Text(connectionService.interfaceType.displayName)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)

                    if let iface = connectionService.primaryInterfaceName {
                        Text("(\(iface))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Network Name (SSID) or "Allow network name" button
                networkNameOrPermissionButton
            }

            // Public IP Row (Off by default, fetches only when clicked)
            publicIPRow
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 20, tint: .cyan)
    }

    // MARK: - Network Name / Permission Button

    @ViewBuilder
    private var networkNameOrPermissionButton: some View {
        if wifiService.needsLocationAuthorization {
            Button {
                wifiService.requestLocationAuthorization()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 8))
                    Text("Allow network name")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.12))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        } else if let info = wifiService.currentInfo {
            HStack(spacing: 5) {
                Premium3DIconView(.wifi, size: 14, interactive: false)
                Text(info.displayName)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
            }
        }
    }

    // MARK: - Public IP Row

    private var publicIPRow: some View {
        HStack(alignment: .center) {
            if !publicIPService.isRevealed {
                Button {
                    publicIPService.fetch()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "network")
                            .font(.system(size: 10))
                        Text("Show public IP")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                Text("Contacts api64.ipify.org")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary.opacity(0.7))
            } else {
                HStack(spacing: 6) {
                    Text("Public IP:")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)

                    if publicIPService.isFetching {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Fetching from api64.ipify.org...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if let ip = publicIPService.publicIP {
                        Text(ip)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(ip, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy public IP")

                        Text("via api64.ipify.org")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary.opacity(0.7))
                    } else if let err = publicIPService.errorMessage {
                        Text("Error: \(err)")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)

                        Button("Retry") {
                            publicIPService.fetch()
                        }
                        .font(.system(size: 9, weight: .semibold))
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    Button("Hide") {
                        publicIPService.hide()
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: - Wi-Fi Card

    private var wiFiCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("WI-FI TELEMETRY", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()

                if let info = wifiService.currentInfo {
                    let quality = snrQuality(snr: info.signalToNoiseRatio)
                    Text(quality.label)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(quality.color.opacity(0.15))
                        .foregroundStyle(quality.color)
                        .clipShape(Capsule())
                }
            }

            switch wifiService.state {
            case .noInterface:
                VStack(spacing: 6) {
                    Image(systemName: "cable.connector")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("No Wi-Fi interface available on this Mac")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)

            case .wifiOff(let iface):
                VStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("Wi-Fi is turned off (\(iface))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)

            case .disconnected(let iface):
                VStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                    Text("Wi-Fi is disconnected (\(iface))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)

            case .connected(let info):
                VStack(spacing: 10) {
                    // Signal Strength Bar + dBm
                    HStack(spacing: 12) {
                        signalBarsView(bars: info.signalBars)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("SIGNAL STRENGTH")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("\(info.rssi) dBm")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 1) {
                            Text("SIGNAL-TO-NOISE (SNR)")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                            Text("\(info.signalToNoiseRatio) dB")
                                .font(.system(size: 13, weight: .bold, design: .monospaced))
                                .foregroundStyle(snrQuality(snr: info.signalToNoiseRatio).color)
                        }
                    }

                    Divider()
                        .overlay(Color.white.opacity(0.06))

                    // Telemetry Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        telemetryCell(title: "NOISE FLOOR", value: "\(info.noise) dBm")
                        telemetryCell(title: "CHANNEL & BAND", value: "Ch \(info.channelNumber) (\(info.channelBand.displayName))")
                        telemetryCell(title: "CHANNEL WIDTH", value: info.channelWidth.displayName)
                        telemetryCell(title: "LINK SPEED", value: "\(Int(info.transmitRate)) Mbps")
                        telemetryCell(title: "SECURITY", value: info.securityType.displayName)
                        telemetryCell(title: "LOCAL IP", value: info.localIPv4 ?? "Unavailable")
                    }
                }
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 20, tint: .cyan)
    }

    private func signalBarsView(bars: Int) -> some View {
        HStack(alignment: .bottom, spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(bars >= 1 ? Color.green : Color.white.opacity(0.15))
                .frame(width: 4, height: 8)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(bars >= 2 ? Color.green : Color.white.opacity(0.15))
                .frame(width: 4, height: 12)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(bars >= 3 ? Color.green : Color.white.opacity(0.15))
                .frame(width: 4, height: 16)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(bars >= 4 ? Color.green : Color.white.opacity(0.15))
                .frame(width: 4, height: 20)
        }
    }

    private func telemetryCell(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - SNR Quality Rating
    //
    // Signal-to-Noise Ratio (SNR) Quality Thresholds:
    // - SNR >= 40 dB: Excellent (Superb link quality, maximum PHY throughput, near-zero packet error)
    // - SNR 25...39 dB: Good (Solid, fast, stable connection suitable for high-bandwidth/low-latency tasks)
    // - SNR 15...24 dB: Fair (Acceptable for web browsing, occasional packet retransmissions)
    // - SNR < 15 dB: Poor (High packet loss, high latency jitter, frequently degraded link)
    private func snrQuality(snr: Int) -> (label: String, color: Color) {
        if snr >= 40 {
            return ("Excellent", .green)
        } else if snr >= 25 {
            return ("Good", .mint)
        } else if snr >= 15 {
            return ("Fair", .yellow)
        } else {
            return ("Poor", .red)
        }
    }

    // MARK: - Live Speed Card

    private var liveSpeedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("LIVE NETWORK THROUGHPUT", systemImage: "waveform.path.ecg")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("60-SECOND ROLLING")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            // Current Rates
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("DOWNLOAD")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(formatByteRate(throughputService.downloadBytesPerSecond))
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("UPLOAD")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(formatByteRate(throughputService.uploadBytesPerSecond))
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }

                Spacer()
            }

            // 60-Second Real-Time Graph
            if throughputService.history.count >= 2 {
                throughputGraph
                    .frame(height: 55)
                    .padding(.top, 4)
            } else {
                HStack {
                    Spacer()
                    Text("Sampling throughput (updated every second)...")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(height: 45)
            }
        }
        .padding(14)
        .liquidGlassCard(cornerRadius: 20, tint: .cyan)
    }

    private var throughputGraph: some View {
        Chart {
            ForEach(throughputService.history) { sample in
                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Download", sample.downloadBytesPerSecond / 1_000_000.0)
                )
                .foregroundStyle(Color.green)
                .interpolationMethod(.monotone)

                AreaMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Download", sample.downloadBytesPerSecond / 1_000_000.0)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.green.opacity(0.3), Color.green.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.monotone)

                LineMark(
                    x: .value("Time", sample.timestamp),
                    y: .value("Upload", sample.uploadBytesPerSecond / 1_000_000.0)
                )
                .foregroundStyle(Color.purple)
                .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 2)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let doubleVal = value.as(Double.self) {
                        Text(String(format: "%.1f MB/s", doubleVal))
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func formatByteRate(_ bytesPerSecond: Double) -> String {
        let b = max(0, bytesPerSecond)
        if b >= 1_000_000_000 {
            return String(format: "%.2f GB/s", b / 1_000_000_000.0)
        } else if b >= 1_000_000 {
            return String(format: "%.2f MB/s", b / 1_000_000.0)
        } else if b >= 1_000 {
            return String(format: "%.1f KB/s", b / 1_000.0)
        } else {
            return String(format: "%.0f B/s", b)
        }
    }
}
