//
//  LiquidBuddyService.swift
//  LiquidDynamo
//
//  Interactive dynamic notch buddy companion with tactile animations.
//

import Combine
import SwiftUI

public enum BuddyExpression: String {
    case happy = "􀌪" // smiling face
    case coding = "􀤆" // keyboard / coding
    case alert = "􀌩" // alert / thinking
    case sleeping = "􀌭" // sleeping zzz
}

@MainActor
public final class LiquidBuddyService: ObservableObject {
    public static let shared = LiquidBuddyService()

    @Published public var expression: BuddyExpression = .happy
    @Published public var name: String = "Liquid Buddy"
    @Published public var isVisible: Bool = false

    private var moodTimer: AnyCancellable?

    private init() {
        moodTimer = Timer.publish(every: 8.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.cycleMood()
            }
    }

    private func cycleMood() {
        let moods: [BuddyExpression] = [.happy, .coding, .alert]
        if let random = moods.randomElement() {
            withAnimation(.spring(response: 0.3)) {
                self.expression = random
            }
        }
    }

    public func poke() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) {
            expression = .happy
        }
    }
}

public struct LiquidBuddyView: View {
    @ObservedObject var buddy = LiquidBuddyService.shared

    public init() {}

    public var body: some View {
        Button {
            buddy.poke()
        } label: {
            HStack(spacing: 4) {
                Text(buddy.expression.rawValue)
                    .font(.system(size: 14))
                Text(buddy.name)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
