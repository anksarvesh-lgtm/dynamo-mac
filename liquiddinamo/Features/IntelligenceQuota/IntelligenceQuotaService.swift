//
//  IntelligenceQuotaService.swift
//  LiquidDynamo
//
//  AI model intelligence rate limit and quota usage tracking rings.
//  Merged from ILoveNotch.
//

import Combine
import SwiftUI

public struct ModelQuotaStatus: Identifiable {
    public let id = UUID()
    public let modelName: String
    public var percentUsed: Double // 0.0 to 1.0
    public var resetTimeString: String
    public var color: Color
}

@MainActor
public final class IntelligenceQuotaService: ObservableObject {
    public static let shared = IntelligenceQuotaService()

    @Published public private(set) var quotas: [ModelQuotaStatus] = [
        ModelQuotaStatus(modelName: "Claude 3.5 Sonnet", percentUsed: 0.42, resetTimeString: "Resets in 3h", color: .purple),
        ModelQuotaStatus(modelName: "OpenAI o1 / Codex", percentUsed: 0.28, resetTimeString: "Resets in 5h", color: .green),
        ModelQuotaStatus(modelName: "GitHub Copilot", percentUsed: 0.65, resetTimeString: "Monthly cap", color: .blue)
    ]

    private init() {}
}

public struct IntelligenceQuotaView: View {
    @ObservedObject var quotaService = IntelligenceQuotaService.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(quotaService.quotas) { q in
                VStack(spacing: 3) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: CGFloat(q.percentUsed))
                            .stroke(q.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(q.percentUsed * 100))%")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .frame(width: 32, height: 32)

                    Text(q.modelName.components(separatedBy: " ").first ?? "")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.06))
        .cornerRadius(8)
    }
}

