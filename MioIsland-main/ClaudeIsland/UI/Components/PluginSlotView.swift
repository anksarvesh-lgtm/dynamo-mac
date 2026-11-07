//
//  PluginSlotView.swift
//  ClaudeIsland
//
//  Generic SwiftUI view that renders plugin views for a given slot.
//  Used by the main app to inject plugin UI at predefined positions
//  without knowing anything about specific plugins.
//
//  Slots:
//    "header"      — top-right icon area (small, ~24x24)
//    "footer"      — bottom of notch panel (full width)
//    "overlay"     — center overlay on instances
//    "sessionItem" — per session row badge
//

import SwiftUI

/// Renders all plugin views for a given slot.
/// Header/sessionItem slots use HStack; footer uses VStack.
struct PluginSlotView: View {
    let slot: String
    var context: [String: Any] = [:]

    @ObservedObject private var manager = NativePluginManager.shared

    private var pluginViews: [(id: String, view: NSView)] {
        manager.loadedPlugins.compactMap { plugin in
            guard let view = plugin.viewForSlot(slot, context: context) else { return nil }
            return (id: plugin.id, view: view)
        }
    }

    var body: some View {
        let views = pluginViews
        if !views.isEmpty {
            ForEach(views, id: \.id) { item in
                PluginSlotNSViewWrapper(nsView: item.view, slot: slot)
            }
        }
    }
}

/// Bridges a plugin's slot NSView into SwiftUI with slot-appropriate sizing.
private struct PluginSlotNSViewWrapper: NSViewRepresentable {
    let nsView: NSView
    let slot: String

    func makeNSView(context: Context) -> NSView {
        // Wrap in a container that allows mouse events to pass through
        let container = PluginSlotContainerView()
        container.addSubview(nsView)
        nsView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            nsView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            nsView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            nsView.topAnchor.constraint(equalTo: container.topAnchor),
            nsView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        if slot == "header" || slot == "sessionItem" {
            container.setContentHuggingPriority(.required, for: .horizontal)
            container.setContentHuggingPriority(.required, for: .vertical)
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Container that ensures tracking areas and mouse events work for plugin views.
private class PluginSlotContainerView: NSView {
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
