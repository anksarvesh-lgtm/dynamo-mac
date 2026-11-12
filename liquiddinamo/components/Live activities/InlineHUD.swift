//
//  InlineHUDs.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
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

                    // Center: Physical Notch Cutout Hole (Completely empty space)
                    Color.clear
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
                            .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: 80, alignment: .leading)
                    .clipped()

                    hudRightContent
                }
                .padding(.horizontal, 10)
                .background(
                    LiquidGlassSurface(
                        shape: OrganicFluidShape(progress: 1.0, wavePhase: 0.0),
                        isNotchAnchored: false,
                        scrimFloor: 0.35
                    )
                )
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
            let isMutedState = type == .volume && (VolumeManager.shared.isMuted || value <= 0.001)
            let isInteractive: Bool = {
                switch type {
                case .volume: return VolumeManager.shared.hasVolumeControl
                case .brightness: return BrightnessManager.shared.isBrightnessAvailable
                case .backlight: return KeyboardBacklightManager.shared.isKeyboardBacklightAvailable
                default: return false
                }
            }()
            let levelColor: Color = HUDLogic.glowStage(level: Double(value), isMuted: isMutedState) == .hot ? .orange : .accentColor
            HStack(spacing: 4) {
                OrganicFluidLevelView(
                    value: $value,
                    tintColor: levelColor,
                    height: 6.0,
                    onChange: isInteractive ? { v in
                        if type == .volume {
                            VolumeManager.shared.setAbsolute(Float32(v))
                        } else if type == .brightness {
                            BrightnessManager.shared.setAbsolute(value: Float32(v))
                        } else if type == .backlight {
                            KeyboardBacklightManager.shared.setAbsolute(value: Float32(v))
                        }
                    } : nil
                )
                .frame(maxWidth: 55)
                .allowsHitTesting(isInteractive)
                .opacity(isInteractive ? 1.0 : 0.55)

                if isMutedState {
                    Text(HUDLogic.percentText(level: Double(value), isMuted: true))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.red.opacity(0.9))
                        .lineLimit(1)
                } else if Defaults[.showClosedNotchHUDPercentage] {
                    Text(HUDLogic.percentText(level: Double(value), isMuted: false))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .frame(minWidth: 28, alignment: .trailing)
                }
            }
        }
    }

    func SpeakerSymbol(_ value: CGFloat) -> String {
        if VolumeManager.shared.isMuted || value <= 0.001 {
            return "speaker.slash"
        }
        switch value {
        case ..<0.3:
            return "speaker.wave.1"
        case ..<0.8:
            return "speaker.wave.2"
        default:
            return "speaker.wave.3"
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

#if DEBUG
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
#endif
