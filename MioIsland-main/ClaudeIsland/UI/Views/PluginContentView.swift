//
//  PluginContentView.swift
//  ClaudeIsland
//
//  Wraps a native plugin's NSView for display in the notch panel.
//  Includes a back button to return to instances view.
//

import SwiftUI

struct PluginContentView: View {
    let pluginId: String
    let viewModel: NotchViewModel
    private var theme: ThemeResolver {
        ThemeResolver(theme: NotchCustomizationStore.shared.customization.theme)
    }

    var body: some View {
        // Plugin fills the entire panel. The back button becomes a
        // floating pill in the top-left so plugins can paint their own
        // theme color all the way to the top edge (no unthemed chrome
        // band above the plugin's card). Plugins are responsible for
        // adding their own top inset (~40pt) so content doesn't sit
        // under the floating pill.
        ZStack(alignment: .topLeading) {
            if let plugin = NativePluginManager.shared.plugin(for: pluginId) {
                PluginNSViewWrapper(plugin: plugin)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Plugin not found")
                    .font(.system(size: 12))
                    .foregroundColor(theme.mutedText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Back button — icon-only circular chip. Dropped the
            // redundant plugin name label ("Music Player", "Pair
            // iPhone", etc.): the user already knows where they are
            // from the visible plugin UI, and the extra text was
            // cramping the plugin's content area. Tooltip still shows
            // full name for accessibility.
            Button {
                viewModel.exitChat()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(theme.overlay.opacity(0.88)))
                    .overlay(
                        Circle().strokeBorder(theme.border.opacity(0.75), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("Back to \(pluginName)")
            .padding(.leading, 10)
            .padding(.top, 12)
        }
    }

    private var pluginName: String {
        NativePluginManager.shared.plugin(for: pluginId)?.name ?? pluginId
    }
}

/// Bridges a plugin's NSView into SwiftUI via NSViewRepresentable.
struct PluginNSViewWrapper: NSViewRepresentable {
    let plugin: NativePluginManager.LoadedPlugin

    func makeNSView(context: Context) -> NSView {
        plugin.makeView() ?? NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
