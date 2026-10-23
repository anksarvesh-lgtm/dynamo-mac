//
//  AirPodsDashboardView.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import SwiftUI

// MARK: - Unified AirPods Dashboard View

@MainActor
public struct AirPodsDashboardView: View {
    @ObservedObject private var service = AirPodsService.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Header: Model name & connection badge
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "airpodspro")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)

                    Text(service.state.modelName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(service.state.isConnected ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 7, height: 7)

                    Text(service.state.isConnected ? "Connected" : "Disconnected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.65))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                )
            }
            .padding(.horizontal, 4)

            // Top: Space-themed 3D AirPods Scene
            AirPodsSceneView()
                .frame(height: 200)

            // Bottom: Interactive Controls Panel
            AirPodsControlsPanelView()
        }
        .padding(14)
        .frame(minWidth: 420)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
