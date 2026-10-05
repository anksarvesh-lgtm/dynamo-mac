//
//  LiveActivitySetupView.swift
//  boringNotch
//
//  Created by Agrigence on 2026-10-04.
//  Copyright © 2026 Agrigence. All rights reserved.
//

import SwiftUI

/// First-run setup step for selecting active Live Activity sources.
public struct LiveActivitySetupView: View {
    @ObservedObject private var catalog = ModuleCatalog.shared
    let onContinue: () -> Void

    public init(onContinue: @escaping () -> Void) {
        self.onContinue = onContinue
    }

    public var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.effectiveAccent)

                Text("Choose Your Live Activities")
                    .font(.title2)
                    .bold()

                Text("LiquidDynamo drops helpful live alerts directly from the notch. Select which sources you want enabled:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 16)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(catalog.modules) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.iconName)
                                .font(.system(size: 16))
                                .foregroundColor(catalog.sourceSeverity(for: item.id).color)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(item.displayName)
                                        .font(.system(size: 13, weight: .medium))
                                    if item.isExperimental {
                                        Text("EXPERIMENTAL")
                                            .font(.system(size: 8, weight: .bold))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(Color.purple.opacity(0.2))
                                            .foregroundColor(.purple)
                                            .cornerRadius(3)
                                    }
                                }

                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Toggle("", isOn: Binding(
                                get: { catalog.isSourceEnabled(item.id) },
                                set: { catalog.setSourceEnabled(item.id, enabled: $0) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 20)
            }
            .frame(maxHeight: 280)

            Button("Continue", action: onContinue)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.bottom, 20)
        }
        .frame(width: 440, height: 560)
    }
}
