# Design

**One object.** Every state is the same view: an `IslandShape` whose width, height, bottom radius and top "ears" animate together. Content inside uses `matchedGeometryEffect`, so for example the artwork flies from the compact wing into the expanded card, and secondary bubbles become the tabs in the expanded header. There is never a window swap or a fade-out followed by a fade-in.

**Motion.** A single spring (`response 0.44, damping 0.8`, scaled by Animation speed). SwiftUI springs are interruptible and keep their velocity, so quick hover in and out retargets smoothly. With Reduce Motion, this becomes a 0.18 s ease and content simply cross-fades.

**States**

| State | Size | Material |
|---|---|---|
| idle | exactly the notch (invisible) | black |
| compact | notch + two wings | black, so it reads as part of the hardware |
| minimal | notch-height circles to the right | black |
| expanded | ~440 pt wide, content-driven height | Liquid Glass blended by Glass intensity |
| search | ~580 pt wide, grows with results | same |

**Restraint.** Compact states show one glanceable value. Looping animations are avoided (they cost CPU every frame). The only exceptions are the playing-media waveform and progress rings that update on real change. Short-lived events (charging, AirPods, downloads finished) appear for a few seconds and leave.

**Accessibility.** VoiceOver labels describe each activity. The island offers an Expand/Collapse action. Bubbles are buttons. Increase Contrast adds outlines. Reduce Transparency removes glass. Keyboard search supports ↑ ↓ ↩ ⎋.
