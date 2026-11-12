//
//  OpenNotchHUD.swift
//  LiquidDynamo
//
//  LiquidDynamo Core Team
//

import SwiftUI
import Defaults

struct OpenNotchHUD: View {
    @EnvironmentObject var vm: LiquidViewModel
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Default(.showOpenNotchHUDPercentage) var showPercentage
    
    private var isInteractive: Bool {
        switch type {
        case .volume:
            return VolumeManager.shared.hasVolumeControl
        case .brightness:
            return BrightnessManager.shared.isBrightnessAvailable
        case .backlight:
            return KeyboardBacklightManager.shared.isKeyboardBacklightAvailable
        default:
            return false
        }
    }

    private var isMutedState: Bool {
        type == .volume && (VolumeManager.shared.isMuted || value <= 0.001)
    }

    var body: some View {
        HStack(spacing: 8) {
            // Icon
            Group {
                switch type {
                case .volume:
                    if icon.isEmpty {
                        Image(systemName: SpeakerSymbol(value))
                            .contentTransition(.interpolate)
                    } else {
                        Image(systemName: icon)
                            .contentTransition(.interpolate)
                    }
                case .brightness:
                    Image(systemName: "sun.max.fill")
                        .contentTransition(.symbolEffect)
                case .backlight:
                    Image(systemName: value > 0.5 ? "light.max" : "light.min")
                        .contentTransition(.interpolate)
                case .mic:
                    Image(systemName: "mic")
                        .symbolVariant(value > 0 ? .none : .slash)
                        .contentTransition(.interpolate)
                default:
                    EmptyView()
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: 20, alignment: .center)
            
            // Slider or Status Text
            if type != .mic {
                DraggableProgressBar(
                    value: $value,
                    isInteractive: isInteractive,
                    onChange: { newVal in
                        updateSystemValue(newVal)
                    }
                )
                .frame(width: showPercentage ? 65 : 108) // Fixed width for consistency
                .opacity(isInteractive ? 1.0 : 0.55)
            } else {
                Text(value > 0 ? "Unmuted" : "Muted")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .fixedSize()
            }
            
            // Percentage / Muted Readout
            if type != .mic && showPercentage {
                Text(HUDLogic.percentText(level: Double(value), isMuted: isMutedState))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isMutedState ? .red.opacity(0.9) : .white.opacity(0.85))
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                    .monospacedDigit()
                    .frame(minWidth: 42, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            OrganicFluidShape(
                blobs: [
                    FluidLobe(center: CGPoint(x: 60, y: 15), radiusX: 55, radiusY: 14)
                ],
                irregularity: 0.15
            )
            .fill(Color.white.opacity(0.12))
        )
    }
    
    func SpeakerSymbol(_ value: CGFloat) -> String {
        if VolumeManager.shared.isMuted || value <= 0.001 {
            return "speaker.slash"
        }
        switch value {
        case ..<0.33: return "speaker.wave.1"
        case ..<0.66: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }
    
    func updateSystemValue(_ newVal: CGFloat) {
        switch type {
        case .volume:
            VolumeManager.shared.setAbsolute(Float32(newVal))
        case .brightness:
            BrightnessManager.shared.setAbsolute(value: Float32(newVal))
        case .backlight:
            KeyboardBacklightManager.shared.setAbsolute(value: Float32(newVal))
        default:
            break
        }
    }
}

#if DEBUG
#Preview {
    OpenNotchHUD(type: .constant(.volume), value: .constant(0.5), icon: .constant(""))
        .environmentObject(LiquidViewModel())
        .padding()
        .background(Color.gray)
}
#endif
