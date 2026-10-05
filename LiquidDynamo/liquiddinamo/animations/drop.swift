//
//  drop.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on  04/08/24.
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
