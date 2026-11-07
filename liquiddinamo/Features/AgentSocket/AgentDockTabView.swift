//
//  AgentDockTabView.swift
//  LiquidDynamo
//
//  In-Notch AI Developer Agent Tab — interactive permission prompt, tool streamer,
//  and terminal session controller. Merged from MioIsland.
//

import SwiftUI

public struct AgentDockTabView: View {
    @ObservedObject var agentService = AgentSocketService.shared
    @State private var showingLogs: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 12) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(agentService.isConnected ? Color.green : Color.white.opacity(0.6))

                Text(agentService.activeAgentName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                // State Badge
                HStack(spacing: 4) {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 6, height: 6)
                    Text(agentService.state.rawValue)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.85))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())

                if agentService.activeSessionCost > 0 {
                    Text(String(format: "$%.2f", agentService.activeSessionCost))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.green.opacity(0.9))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)

            // Main Content Area
            if let request = agentService.pendingRequest {
                // Interactive Permission Prompt
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text("Permission Required")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Text(request.toolName)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.2))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }

                    Text(request.summary)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.white.opacity(0.85))

                    if !request.command.isEmpty {
                        Text(request.command)
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(Color.green.opacity(0.95))
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)
                    }

                    // Action Buttons
                    HStack(spacing: 8) {
                        Button {
                            agentService.respondToPermission(allowed: false)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "xmark")
                                Text("Deny")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.35))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)

                        Button {
                            agentService.respondToPermission(allowed: true)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark")
                                Text("Allow")
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.45))
                            .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
                .padding(10)
                .background(Color.white.opacity(0.08))
                .cornerRadius(10)
                .padding(.horizontal, 14)
            } else {
                // Live Activity Status & Quick Action
                VStack(alignment: .leading, spacing: 6) {
                    Text("ACTIVE ACTIVITY")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.45))

                    Text(agentService.currentActivity)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(2)

                    HStack {
                        Button {
                            showingLogs.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showingLogs ? "chevron.up" : "chevron.down")
                                Text(showingLogs ? "Hide Terminal Output" : "Show Terminal Output")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        if !agentService.isConnected {
                            Button {
                                agentService.simulateDemoRequest()
                            } label: {
                                Text("Simulate Request")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.white.opacity(0.6))
                                    .underline()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)

                    if showingLogs {
                        ScrollView(.vertical, showsIndicators: true) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(agentService.recentLogs, id: \.self) { log in
                                    Text(log)
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.75))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 70)
                        .padding(6)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(6)
                    }
                }
                .padding(10)
                .background(Color.white.opacity(0.06))
                .cornerRadius(10)
                .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 10)
    }

    private var stateColor: Color {
        switch agentService.state {
        case .idle: return Color.gray
        case .thinking: return Color.blue
        case .toolUse: return Color.green
        case .awaitingPermission: return Color.orange
        case .finished: return Color.green
        case .error: return Color.red
        }
    }
}
