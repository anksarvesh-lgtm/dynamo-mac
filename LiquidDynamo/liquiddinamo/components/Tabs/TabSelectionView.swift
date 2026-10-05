//
//  TabSelectionView.swift
//  boringNotch
//
//  Created by Hugo Persson on 2024-08-25.
//

import Defaults
import SwiftUI

struct TabModel: Identifiable {
    let id = UUID()
    let label: String
    let icon: String
    let view: NotchViews
}

struct TabSelectionView: View {
    @ObservedObject var coordinator = LiquidViewCoordinator.shared
    @Default(.showStatsTab) var showStatsTab
    @Default(.showBluetoothTab) var showBluetoothTab
    @Default(.showNetworkTab) var showNetworkTab
    @Namespace var animation

    private var tabs: [TabModel] {
        var list = [
            TabModel(label: "Home", icon: "house.fill", view: .home),
        ]
        if showStatsTab {
            list.append(TabModel(label: "Stats", icon: "cpu", view: .stats))
        }
        if showBluetoothTab {
            list.append(TabModel(label: "Bluetooth", icon: "antenna.radiowaves.left.and.right", view: .bluetooth))
        }
        if showNetworkTab {
            list.append(TabModel(label: "Network", icon: "network", view: .network))
        }
        list.append(TabModel(label: "Shelf", icon: "tray.fill", view: .shelf))
        return list
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                    TabButton(label: tab.label, icon: tab.icon, selected: coordinator.currentView == tab.view) {
                        withAnimation(.smooth) {
                            coordinator.currentView = tab.view
                        }
                    }
                    .frame(height: 26)
                    .foregroundStyle(tab.view == coordinator.currentView ? .white : .gray)
                    .background {
                        if tab.view == coordinator.currentView {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                        } else {
                            Capsule()
                                .fill(coordinator.currentView == tab.view ? Color(nsColor: .secondarySystemFill) : Color.clear)
                                .matchedGeometryEffect(id: "capsule", in: animation)
                                .hidden()
                        }
                    }
            }
        }
        .clipShape(Capsule())
    }
}

#Preview {
    LiquidHeader().environmentObject(LiquidViewModel())
}
