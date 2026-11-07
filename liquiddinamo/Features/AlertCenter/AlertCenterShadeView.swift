//
//  AlertCenterShadeView.swift
//  LiquidDynamo
//
//  Pull-down unified notification shade with grouped application alerts.
//

import SwiftUI

public struct AlertCenterShadeView: View {
    @ObservedObject var alertCenter = AlertCenterService.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 12))
                Text("Liquid Alert Center")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                if !alertCenter.alerts.isEmpty {
                    Button("Clear All") {
                        alertCenter.clearAll()
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            if alertCenter.alerts.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No Notifications")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(alertCenter.alerts) { alert in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.cyan)
                                    .frame(width: 20, height: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(alert.appName)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white.opacity(0.7))
                                        Spacer()
                                        Text(alert.timestamp, style: .time)
                                            .font(.system(size: 9))
                                            .foregroundColor(.white.opacity(0.4))
                                    }
                                    if !alert.title.isEmpty {
                                        Text(alert.title)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                    Text(alert.body.isEmpty ? alert.subtitle : alert.body)
                                        .font(.system(size: 10))
                                        .foregroundColor(.white.opacity(0.85))
                                        .lineLimit(2)
                                }

                                Button {
                                    alertCenter.dismissAlert(id: alert.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.06))
                            .cornerRadius(8)
                        }
                    }
                    .padding(.horizontal, 14)
                }
                .frame(maxHeight: 120)
            }
        }
        .padding(.bottom, 6)
    }
}
