//
//  DashboardHomeView.swift
//  LiquidDynamo
//
//  Created for LiquidDynamo
//

import Combine
import Defaults
import SwiftUI

struct DashboardHomeView: View {
    @EnvironmentObject var vm: LiquidViewModel
    @ObservedObject var coordinator = LiquidViewCoordinator.shared
    let albumArtNamespace: Namespace.ID

    var body: some View {
        LiquidOrganicNotchView()
    }
}
