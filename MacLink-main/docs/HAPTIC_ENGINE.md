# Android Haptic Engine

## 1. Principles
- **Immediate Local Feedback:** Tactile sensation must trigger instantaneously upon gesture classification without waiting for Mac network acknowledgement.
- **Hardware-Aware Degradation:** Automatically utilizes Android API 30+ (R) `VibrationEffect.Composition` primitives where supported, falling back cleanly to waveform or single-shot vibrations.
- **Rate-Limiting:** Enforces minimum 30ms inter-haptic interval for ticks to eliminate buzzer chatter during scrolling.

## 2. Haptic Profiles
1. **Natural:**
   - 0.4x amplitude scalar.
   - 10ms click duration.
   - Subtle tactile tick suitable for silent environments.
2. **Standard:**
   - 0.7x amplitude scalar.
   - 15ms click duration.
   - Distinct double-click and right-click differentiation.
3. **Enhanced:**
   - 1.0x amplitude scalar.
   - 20ms duration with rich multi-stage composition primitives.

