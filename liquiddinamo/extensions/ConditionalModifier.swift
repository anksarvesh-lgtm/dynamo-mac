//
//  ConditionalModifier.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//

import SwiftUI

extension View {
    @ViewBuilder func conditionalModifier<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
