//
//  drop.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//

import Foundation
import SwiftUI


@available(*, deprecated, message: "Use IslandMotion.shared instead.")
@MainActor
public class LiquidAnimations {
    @Published var notchStyle: Style = .notch
    
    init() {
        self.notchStyle = .notch
    }
    
    var animation: Animation {
        IslandMotion.shared.expandSpring
    }
}
