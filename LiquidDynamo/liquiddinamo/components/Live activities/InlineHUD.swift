//
//  InlineHUDs.swift
//  boringNotch
//
//  Created by Richard Kunkli on 14/09/2024.
//

import Defaults
import SwiftUI

struct InlineHUD: View {
    @EnvironmentObject var vm: LiquidViewModel
    @ObservedObject var engine = NotchSafeAreaEngine.shared
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat

    var body: some View {
        let geom = engine.currentGeometry
        let wingW = geom.wingWidth

        Group {
            if geom.hasPhysicalNotch {
                // Notched Mac layout: icon in leftSlot, rawNotchWidth hole, level bar in rightSlot
                HStack(spacing: 0) {
                    // Left Slot: Icon & Label (Max width = wingWidth, clipped to prevent spill)
                    HStack(spacing: 5) {
                        hudIconView
                        Text(Type2Name(type))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(width: max(0, wingW - 6), alignment: .leading)
                    .clipped()
                    .padding(.leading, 6)
                    .avoidsNotch(id: "HUDLeftSlot")

                    // Center: Physical Notch Cutout Hole (Black barrier shape only)
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: geom.rawNotchWidth, height: geom.notchHeight)
                        .allowsHitTesting(false)

                    // Right Slot: Draggable Progress Bar & Percentage
                    HStack(spacing: 4) {
                        hudRightContent
                    }
                    .frame(width: max(0, wingW - 6), alignment: .trailing)
                    .clipped()
                    .padding(.trailing, 6)
                    .avoidsNotch(id: "HUDRightSlot")
                }
                .frame(width: geom.compactPillWidth, height: geom.notchHeight, alignment: .center)
            } else {
                // Non-notched Mac & external displays: layouts center in the pill with no hole
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        hudIconView
                        Text(Type2Name(type))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 80, alignment: .leading)
                    .clipped()

                    hudRightContent
                }
                .padding(.horizontal, 10)
                .frame(height: geom.notchHeight, alignment: .center)
                .avoidsNotch(id: "HUDPillNoHole")
            }
        }
    }

    @ViewBuilder
    private var hudIconView: some View {
        Group {
            switch type {
            case .volume:
                if icon.isEmpty {
                    Image(systemName: SpeakerSymbol(value))
                        .contentTransition(.interpolate)
                        .symbolVariant(value > 0 ? .none : .slash)
                        .frame(width: 16, height: 14, alignment: .leading)
                } else {
                    Image(systemName: icon)
                        .contentTransition(.interpolate)
                        .opacity(value.isZero ? 0.6 : 1)
                        .scaleEffect(value.isZero ? 0.85 : 1)
                        .frame(width: 16, height: 14, alignment: .leading)
                }
            case .brightness:
                Image(systemName: BrightnessSymbol(value))
                    .contentTransition(.interpolate)
                    .frame(width: 16, height: 14, alignment: .center)
            case .backlight:
                Image(systemName: value > 0.5 ? "light.max" : "light.min")
                    .contentTransition(.interpolate)
                    .frame(width: 16, height: 14, alignment: .center)
            case .mic:
                Image(systemName: "mic")
                    .symbolRenderingMode(.hierarchical)
                    .symbolVariant(value > 0 ? .none : .slash)
                    .contentTransition(.interpolate)
                    .frame(width: 16, height: 14, alignment: .center)
            default:
                EmptyView()
            }
        }
        .foregroundStyle(.white)
        .symbolVariant(.fill)
    }

    @ViewBuilder
    private var hudRightContent: some View {
        if type == .mic {
            Text(value.isZero ? "muted" : "unmuted")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.gray)
                .lineLimit(1)
                .multilineTextAlignment(.trailing)
        } else {
            HStack(spacing: 4) {
                DraggableProgressBar(value: $value, onChange: { v in
                    if type == .volume {
                        VolumeManager.shared.setAbsolute(Float32(v))
                    } else if type == .brightness {
                        BrightnessManager.shared.setAbsolute(value: Float32(v))
                    }
                })
                .frame(maxWidth: 55)

                if type == .volume && value.isZero {
                    Text("muted")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                } else if Defaults[.showClosedNotchHUDPercentage] {
                    Text("\(Int(value * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .frame(minWidth: 26, alignment: .trailing)
                }
            }
        }
    }

    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch value {
        case 0:
            return "speaker"
        case 0...0.3:
            return "speaker.wave.1"
        case 0.3...0.8:
            return "speaker.wave.2"
        case 0.8...1:
            return "speaker.wave.3"
        default:
            return "speaker.wave.2"
        }
    }

    func BrightnessSymbol(_ value: CGFloat) -> String {
        switch value {
        case 0...0.6:
            return "sun.min"
        case 0.6...1:
            return "sun.max"
        default:
            return "sun.min"
        }
    }

    func Type2Name(_ type: SneakContentType) -> String {
        switch type {
        case .volume:
            return "Volume"
        case .brightness:
            return "Brightness"
        case .backlight:
            return "Backlight"
        case .mic:
            return "Mic"
        default:
            return ""
        }
    }
}

#Preview {
    InlineHUD(
        type: .constant(.brightness),
        value: .constant(0.4),
        icon: .constant(""),
        hoverAnimation: .constant(false),
        gestureProgress: .constant(0)
    )
    .padding(.horizontal, 8)
    .background(Color.black)
    .padding()
    .environmentObject(LiquidViewModel())
}
