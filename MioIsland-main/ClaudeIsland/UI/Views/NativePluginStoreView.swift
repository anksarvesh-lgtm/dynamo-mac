//
//  NativePluginStoreView.swift
//  ClaudeIsland
//
//  Plugin management UI in System Settings. Shows official + installed
//  plugins, supports one-click reinstall of official plugins, .bundle
//  file install, and one-tap install from a marketplace download URL.
//

import SwiftUI
import UniformTypeIdentifiers

struct NativePluginStoreView: View {
    @ObservedObject private var manager = NativePluginManager.shared
    @ObservedObject private var notchStore: NotchCustomizationStore = .shared

    @State private var installURLText: String = ""
    @State private var urlInstallError: String? = nil
    @State private var urlInstalling: Bool = false
    @State private var urlInstallSuccess: Bool = false

    private var theme: ThemeResolver { ThemeResolver(theme: notchStore.customization.theme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Intro / marketplace link
                marketplaceBanner

                // URL install card
                installFromURLSection

                // Plugin list
                HStack {
                    Text("Installed Plugins")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.secondaryText)
                    Spacer()
                    Button {
                        installFromFinder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 12))
                            Text("Install .bundle")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(theme.doneColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)

                let items = manager.pluginListItems
                if items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 28))
                            .foregroundColor(theme.mutedText.opacity(0.55))
                        Text("No plugins installed")
                            .font(.system(size: 12))
                            .foregroundColor(theme.mutedText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    ForEach(items) { item in
                        pluginRow(item)
                    }
                }

                Text("~/.config/codeisland/plugins/")
                    .font(.system(size: 10))
                    .foregroundColor(theme.mutedText)
                    .padding(.top, 4)
            }
            .padding(20)
        }
    }

    // MARK: - Marketplace banner

    private var marketplaceBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundColor(theme.doneColor)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("发现更多插件")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(theme.primaryText.opacity(0.9))
                    Text("MioIsland 插件市场收录了主题、音效、伙伴精灵和各种扩展组件。")
                        .font(.system(size: 11))
                        .foregroundColor(theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("浏览市场后，点击「安装」会生成一个下载地址，复制回来粘贴到下方即可一键安装。")
                        .font(.system(size: 11))
                        .foregroundColor(theme.mutedText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                if let url = URL(string: "https://miomio.chat/plugins") {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "safari.fill")
                        .font(.system(size: 11))
                    Text("打开插件市场")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundColor(theme.inverseText)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.doneColor)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(
                    LinearGradient(
                        colors: [
                            theme.doneColor.opacity(0.08),
                            theme.overlay.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.doneColor.opacity(0.25), lineWidth: 1)
                )
        )
    }

    // MARK: - URL install section

    private var installFromURLSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(theme.doneColor)
                Text("Install from URL")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.primaryText.opacity(0.85))
            }
            Text("Paste a plugin download URL from the marketplace")
                .font(.system(size: 11))
                .foregroundColor(theme.mutedText)

            HStack(spacing: 8) {
                // SwiftUI's TextField.prompt ignores `foregroundColor` on macOS,
                // so we overlay our own placeholder Text in a solid light gray.
                ZStack(alignment: .leading) {
                    if installURLText.isEmpty {
                        Text("https://api.miomio.chat/api/i/...")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(theme.mutedText.opacity(0.9))
                            .padding(.horizontal, 10)
                            .allowsHitTesting(false)
                    }
                    TextField("", text: $installURLText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(theme.primaryText.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(theme.overlay.opacity(0.18)))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.border.opacity(0.24), lineWidth: 1)
                )
                .disabled(urlInstalling)

                Button {
                    if let str = NSPasteboard.general.string(forType: .string) {
                        installURLText = str
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12))
                        .foregroundColor(theme.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 6).fill(theme.overlay.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .help("Paste from clipboard")

                Button {
                    performURLInstall()
                } label: {
                    HStack(spacing: 4) {
                        if urlInstalling {
                            ProgressView()
                                .controlSize(.mini)
                        } else if urlInstallSuccess {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        } else {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(urlInstalling ? "Installing…" : (urlInstallSuccess ? "Installed" : "Install"))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(theme.inverseText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.doneColor)
                    )
                }
                .buttonStyle(.plain)
                .disabled(urlInstalling || installURLText.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let err = urlInstallError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundColor(theme.errorColor)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.overlay.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.doneColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func performURLInstall() {
        let url = installURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        urlInstalling = true
        urlInstallError = nil
        urlInstallSuccess = false
        Task {
            do {
                try await manager.installFromURL(url)
                urlInstalling = false
                urlInstallSuccess = true
                installURLText = ""
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                urlInstallSuccess = false
            } catch {
                urlInstalling = false
                urlInstallError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Plugin row

    private func pluginRow(_ item: NativePluginManager.PluginListItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .font(.system(size: 16))
                .foregroundColor(item.isInstalled ? theme.secondaryText : theme.mutedText)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(item.isInstalled ? theme.primaryText.opacity(0.9) : theme.secondaryText)
                    if item.isOfficial {
                        Text("Official")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(theme.doneColor)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(theme.doneColor.opacity(0.12))
                            )
                    }
                    if !item.isInstalled {
                        Text("Disabled")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(theme.mutedText)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(theme.overlay.opacity(0.16))
                            )
                    }
                }
                Text("v\(item.version)")
                    .font(.system(size: 10))
                    .foregroundColor(theme.mutedText)
            }

            Spacer()

            if item.isInstalled {
                Button {
                    manager.uninstall(id: item.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(theme.errorColor.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(item.isOfficial ? "Disable (slot stays)" : "Uninstall")
            } else {
                Button {
                    manager.reinstallOfficial(id: item.id)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10, weight: .bold))
                        Text("Reinstall")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(theme.doneColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(theme.doneColor.opacity(0.1))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(theme.overlay.opacity(0.16)))
    }

    private func installFromFinder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.bundle]
        panel.message = "Select a MioIsland plugin .bundle"
        panel.prompt = "Install"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? manager.install(bundleURL: url)
    }
}
