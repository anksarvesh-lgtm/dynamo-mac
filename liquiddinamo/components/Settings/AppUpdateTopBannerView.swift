//
//  AppUpdateTopBannerView.swift
//  LiquidDynamo
//
//  Universal update banner shown at the top of every section in the application
//  when a new LiquidDynamo release is available on GitHub.
//

import AppKit
import SwiftUI

public struct AppUpdateTopBannerView: View {
    @ObservedObject private var updateChecker = GitHubUpdateChecker.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false

    public init() {}

    public var body: some View {
        if updateChecker.isUpdateAvailable && !updateChecker.isBannerDismissed {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    // Glowing Update Icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.15, green: 0.55, blue: 1.0).opacity(0.35),
                                        Color(red: 0.05, green: 0.35, blue: 0.85).opacity(0.15)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 32, height: 32)

                        Image(systemName: updateChecker.isDownloading ? "arrow.down.circle.fill" : "sparkles")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color(red: 0.35, green: 0.70, blue: 1.0))
                            .shadow(color: Color.blue.opacity(0.6), radius: 4)
                    }

                    // Content text / Version / Progress
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text("LiquidDynamo v\(updateChecker.latestVersionString) Available")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)

                            Text("GitHub Release")
                                .font(.system(size: 9.5, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.25))
                                .foregroundStyle(Color(red: 0.40, green: 0.75, blue: 1.0))
                                .clipShape(Capsule())
                        }

                        if updateChecker.isDownloading {
                            Text(updateChecker.downloadStatusFormatted)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.90))
                        } else if case .extracting = updateChecker.status {
                            Text("Extracting liquiddynamo.app…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(red: 0.75, green: 0.80, blue: 0.90))
                        } else if case .replacingAndRelaunching = updateChecker.status {
                            Text("Replacing in /Applications & relaunching…")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color.green.opacity(0.9))
                        } else if case .error(let msg) = updateChecker.status {
                            Text("Download error: \(msg)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.45))
                                .lineLimit(1)
                        } else {
                            Text("A new release is ready. Click update to download and replace in /Applications.")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(Color(red: 0.65, green: 0.70, blue: 0.78))
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    // Action buttons
                    HStack(spacing: 8) {
                        if updateChecker.isDownloading {
                            ProgressView(value: updateChecker.downloadProgress)
                                .progressViewStyle(.linear)
                                .frame(width: 100)
                                .tint(Color.blue)

                            Button("Cancel") {
                                updateChecker.cancelDownload()
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.65))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                        } else if case .extracting = updateChecker.status {
                            ProgressView()
                                .controlSize(.small)
                        } else if case .replacingAndRelaunching = updateChecker.status {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            // Update Now / Retry Button
                            let isErrorState: Bool = {
                                if case .error = updateChecker.status { return true }
                                return false
                            }()

                            Button {
                                updateChecker.downloadAndInstallUpdate()
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: isErrorState ? "arrow.clockwise" : "arrow.triangle.2.circlepath")
                                        .font(.system(size: 10.5, weight: .bold))
                                    Text(isErrorState ? "Retry" : "Update Now")
                                        .font(.system(size: 11.5, weight: .semibold))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    LinearGradient(
                                        colors: isErrorState ? [
                                            Color(red: 0.85, green: 0.25, blue: 0.25),
                                            Color(red: 0.65, green: 0.15, blue: 0.15)
                                        ] : [
                                            Color(red: 0.15, green: 0.52, blue: 0.98),
                                            Color(red: 0.08, green: 0.40, blue: 0.88)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .shadow(color: isErrorState ? Color.red.opacity(0.4) : Color.blue.opacity(0.4), radius: 4, y: 1.5)
                            }
                            .buttonStyle(.plain)

                            // Dismiss Button
                            Button {
                                updateChecker.dismissBanner()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.white.opacity(0.5))
                                    .padding(6)
                                    .background(Color.white.opacity(0.06))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.09, green: 0.13, blue: 0.20).opacity(0.92),
                                    Color(red: 0.07, green: 0.09, blue: 0.14).opacity(0.95)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.blue.opacity(0.45),
                                    Color.blue.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 10, y: 3)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
