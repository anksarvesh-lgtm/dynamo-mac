//
//  LiquidHeader.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 04/08/24.
//

import Defaults
import SwiftUI

struct LiquidHeader: View {
    @EnvironmentObject var vm: LiquidViewModel
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var coordinator = LiquidViewCoordinator.shared
    @ObservedObject var engine = NotchSafeAreaEngine.shared
    @StateObject var tvm = ShelfStateViewModel.shared

    var body: some View {
        let geom = engine.currentGeometry
        let leftSlotWidth = geom.windowLeftSlot(windowWidth: openNotchSize.width).width
        let rightSlotWidth = geom.windowRightSlot(windowWidth: openNotchSize.width).width

        HStack(spacing: 0) {
            // Left Slot: Tab and Dock Icons
            HStack {
                if vm.notchState == .open {
                    DashboardDockView()
                        .avoidsNotch(id: "ExpandedDockIcons")
                }
            }
            .frame(width: leftSlotWidth, alignment: .leading)
            .clipped()
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)

            // Center: Physical Notch Cutout Mask (Zero on non-notched screens)
            if vm.notchState == .open && geom.hasPhysicalNotch {
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 14,
                    bottomTrailingRadius: 14,
                    style: .continuous
                )
                .fill(Color.black)
                .frame(width: geom.rawNotchWidth, height: geom.notchHeight)
                .allowsHitTesting(false)
            }

            // Right Slot: Battery, Settings, Status
            HStack(spacing: 4) {
                if vm.notchState == .open {
                    if isHUDType(coordinator.sneakPeek.type) && coordinator.sneakPeek.show && Defaults[.showOpenNotchHUD] {
                        OpenNotchHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon)
                            .transition(.scale(scale: 0.8).combined(with: .opacity))
                    } else {
                        if Defaults[.showMirror] {
                            LiquidGlassButton(action: {
                                vm.toggleCameraPreview()
                            }) {
                                Premium3DIconView(.camera, size: 15)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        if Defaults[.settingsIconInNotch] {
                            LiquidGlassButton(action: {
                                DispatchQueue.main.async {
                                    SettingsWindowController.shared.showWindow()
                                }
                            }) {
                                Premium3DIconView(.settings, size: 15)
                                    .frame(width: 16, height: 16)
                            }
                        }
                        if Defaults[.showBatteryIndicator] {
                            LiquidBatteryView(
                                batteryWidth: 30,
                                isCharging: batteryModel.isCharging,
                                isInLowPowerMode: batteryModel.isInLowPowerMode,
                                isPluggedIn: batteryModel.isPluggedIn,
                                levelBattery: batteryModel.levelBattery,
                                maxCapacity: batteryModel.maxCapacity,
                                timeToFullCharge: batteryModel.timeToFullCharge,
                                isForNotification: false
                            )
                        }
                    }
                }
            }
            .font(.system(.headline, design: .rounded))
            .frame(width: rightSlotWidth, alignment: .trailing)
            .clipped()
            .avoidsNotch(id: "ExpandedRightStatus")
            .opacity(vm.notchState == .closed ? 0 : 1)
            .blur(radius: vm.notchState == .closed ? 20 : 0)
            .zIndex(2)
        }
        .frame(height: geom.notchHeight, alignment: .center)
        .foregroundColor(.gray)
        .environmentObject(vm)
    }

    func isHUDType(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume, .brightness, .backlight, .mic:
            return true
        default:
            return false
        }
    }
}

#Preview {
    LiquidHeader().environmentObject(LiquidViewModel())
}
