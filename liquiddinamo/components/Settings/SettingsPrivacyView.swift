//
//  SettingsPrivacyView.swift
//  LiquidDynamo
//
//  Camera & Microphone Privacy Control Center:
//  Real-time preview and tuning of ambient liquid glow indicators
//  when camera or microphone hardware is accessed.
//

import AppKit
import Defaults
import SwiftUI

public struct SettingsPrivacyView: View {
    @Default(.cameraNotchGlowEnabled) private var cameraGlowEnabled
    @Default(.micNotchGlowEnabled) private var micGlowEnabled
    @Default(.privacyIndicatorsEnabled) private var masterEnabled
    @Default(.autoCheckUpdates) private var autoCheckUpdates
    @Default(.privacyPublicIPLookup) private var privacyPublicIPLookup
    @Default(.privacyMeshyUploadEnabled) private var privacyMeshyUploadEnabled
    @Default(.enableLyrics) private var enableLyrics


    public init() {}

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacy & Security")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text("Hardware sensor indicators and outbound network access controls")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $masterEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)


                // Privacy Indicator Modules
                indicatorsCard
                    .padding(.horizontal, 24)

                // Network Access & Endpoints Disclosure Card
                networkAccessCard
                    .padding(.horizontal, 24)

                Spacer(minLength: 20)
            }
        }
    }

    // MARK: - Sensor Toggle Cards
    private var indicatorsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hardware Sensor Tracking")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // Camera Glow Setting
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.2)).frame(width: 32, height: 32)
                    Image(systemName: "camera.fill").font(.system(size: 14)).foregroundStyle(Color.green)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Camera Sensor Active")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Glows with soft liquid green. Replaces intrusive popups.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $cameraGlowEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            Divider().opacity(0.2)

            // Microphone Glow Setting
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.2)).frame(width: 32, height: 32)
                    Image(systemName: "mic.fill").font(.system(size: 14)).foregroundStyle(Color.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Microphone Sensor Active")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("Glows with soft liquid orange whenever input audio streams.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $micGlowEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    // MARK: - Network Access & Endpoints Disclosure Card
    private var networkAccessCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Network Access & Endpoints")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("LiquidDynamo transmits zero background telemetry or personal files. Features with outbound network activity are disclosed below with strict user opt-in controls.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Divider().opacity(0.2)

            // 1. Software Update Checks
            networkEndpointRow(
                icon: "arrow.triangle.2.circlepath",
                iconColor: .blue,
                title: "Software Update Checks",
                host: "api.github.com / github.com",
                detail: "Checks for signed and notarized application updates. Transmits app version and architecture only.",
                isOn: $autoCheckUpdates
            )

            Divider().opacity(0.15)

            // 2. Public IP Lookup
            networkEndpointRow(
                icon: "network",
                iconColor: .teal,
                title: "Public IP Address Lookup",
                host: "api64.ipify.org",
                detail: "On-demand external IP address lookup in the Network Dashboard. Off by default.",
                isOn: $privacyPublicIPLookup
            )

            Divider().opacity(0.15)

            // 3. Meshy AI 3D Generation
            networkEndpointRow(
                icon: "cube.transparent",
                iconColor: .purple,
                title: "Cloud 3D Model Generation",
                host: "api.meshy.ai",
                detail: "Generates 3D models from device images. API key is stored securely in Keychain only. Off by default.",
                isOn: $privacyMeshyUploadEnabled
            )

            Divider().opacity(0.15)

            // 4. Music Lyrics
            networkEndpointRow(
                icon: "music.note.list",
                iconColor: .pink,
                title: "Synced Lyrics Lookup",
                host: "lrclib.net",
                detail: "Fetches synchronized lyrics for currently playing music tracks. Transmits track title and artist name.",
                isOn: $enableLyrics
            )

            Divider().opacity(0.15)

            // 5. Powerload & Local Lottie info
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.2)).frame(width: 32, height: 32)
                        Image(systemName: "bolt.fill").font(.system(size: 14)).foregroundStyle(Color.orange)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Powerload Multi-Interface Downloader")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("Contacts user-supplied download URLs directly. Zero telemetry or intermediary servers.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("User URLs")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.2)).frame(width: 32, height: 32)
                        Image(systemName: "waveform").font(.system(size: 14)).foregroundStyle(Color.green)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Music Visualizer (Lottie)")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Text("Wave visualizer is bundled locally within the app bundle. Zero network requests.")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text("Bundled (Offline)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.1), lineWidth: 1))
        )
    }

    private func networkEndpointRow(
        icon: String,
        iconColor: Color,
        title: String,
        host: String,
        detail: String,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(iconColor.opacity(0.2)).frame(width: 32, height: 32)
                Image(systemName: icon).font(.system(size: 14)).foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text("(\(host))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(detail)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
}
