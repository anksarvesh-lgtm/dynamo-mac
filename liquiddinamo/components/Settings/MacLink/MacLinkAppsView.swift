//
//  MacLinkAppsView.swift
//  LiquidDynamo
//
//  MacLink Installed Apps Drawer: Remote 1-click app launcher and screen mirror trigger.
//

import AppKit
import SwiftUI

public struct MacLinkAppsView: View {
    @ObservedObject private var bridge = MacLinkBridgeService.shared
    @State private var appSearchQuery: String = ""

    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 140), spacing: 14)
    ]

    public init() {}

    private var filteredApps: [PhoneAppItem] {
        if appSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return bridge.installedApps
        }
        return bridge.installedApps.filter { $0.name.localizedCaseInsensitiveContains(appSearchQuery) }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Search Bar
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Installed Phone Apps")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                    Text("Click any application to launch it remotely on \(bridge.deviceName)")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.5))
                }

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.4))

                    TextField("Search apps…", text: $appSearchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white)
                        .frame(width: 140)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            }
            .padding(18)
            .background(Color(white: 0.10).opacity(0.6))

            Divider().opacity(0.12)

            // Apps Grid
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filteredApps) { app in
                        appButton(app)
                    }
                }
                .padding(20)
            }
        }
    }

    private func appButton(_ app: PhoneAppItem) -> some View {
        Button {
            bridge.launchApp(app)
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.blue.opacity(0.18))
                        .frame(width: 54, height: 54)

                    Image(systemName: app.iconSystemName)
                        .font(.system(size: 24))
                        .foregroundStyle(Color.blue)
                }

                Text(app.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.12).opacity(0.4))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.06), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }
}

