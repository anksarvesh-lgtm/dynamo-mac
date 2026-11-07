# Notch Customization QA Checklist

Manual QA pass for the v1.10.0 notch customization feature. Source
spec: `docs/superpowers/specs/2026-04-08-notch-customization-design.md`
(Section 7.3).

## Live edit mode

- [ ] Enter edit mode → arrow buttons (◀ ▶) resize symmetrically
      in 2pt steps → Save → close & relaunch app → width is
      preserved across the restart.
- [ ] Enter edit mode → ⌘+click arrow → resize step is 10pt.
- [ ] Enter edit mode → ⌥+click arrow → resize step is 1pt.
- [ ] Enter edit mode → drag an edge → Cancel → width reverts to
      the pre-edit value.
- [ ] Enter edit mode → Notch Preset button on a MacBook with a
      hardware notch → width snaps to hardware notch width + 20pt
      → dashed marker flashes (fade in over 0.2s, hold 1.6s, fade
      out over 0.2s, gone after ~2s).
- [ ] On a MacBook Air without a hardware notch (OR with Hardware
      Notch set to Force Virtual) → Notch Preset button is
      disabled with the "Your device doesn't have a hardware
      notch" help tooltip.
- [ ] Drag Mode → click → notch flashes (opacity 1 → 0.4 → 1 over
      0.3s easeInOut) → dragging moves the notch horizontally
      only, y pinned to top.
- [ ] Enter edit mode → toggle Drag Mode → drag horizontally to
      offset the notch → Cancel → horizontal offset AND any width
      changes revert to pre-edit values.

## Themes

- [ ] Switch between all 6 themes (Classic, Paper, Neon Lime,
      Cyber, Mint, Sunset) → the transition animates ≤ 0.3s with
      no flicker, no geometry re-trigger.
- [ ] Each theme renders the notch, primary text, and secondary
      (dimmer) text in its intended palette.
- [ ] Status colors (success / warning / error) are unaffected
      by theme switches — they preserve semantic meaning.

## Font scaling

- [ ] Change font size to S → all text scales to 0.85×.
- [ ] Change font size to M → all text is 1.0×.
- [ ] Change font size to L → all text scales to 1.15×.
- [ ] Change font size to XL → all text scales to 1.3×, no
      layout breakage, no crash.
- [ ] At XL, if the content exceeds the user's maxWidth, the
      notch pins at maxWidth and the text truncates with a
      trailing ellipsis rather than auto-bumping the max.

## Visibility toggles

- [ ] Disable Show Buddy → pet disappears from the notch and
      surrounding layout collapses cleanly without gaps.
- [ ] Disable Show Usage Bar → usage bar disappears and the
      idle-state notch becomes narrower.

## Auto-width

- [ ] Idle state with only icon + time visible → notch
      auto-shrinks tight around content (screenshot case).
- [ ] A very long Claude message → notch expands up to the
      configured maxWidth, then truncates with an ellipsis.

## External monitor

- [ ] Plug in an external monitor → notch migrates per Hardware
      Notch Mode setting without restart.
- [ ] Enter edit mode → plug or unplug an external monitor →
      live edit auto-cancels, the NotchLiveEditPanel tears down,
      and the draft reverts.

## Accessibility

- [ ] VoiceOver reads "Shrink notch" / "Grow notch" for the
      arrow buttons with a hint about ⌘ and ⌥ modifiers.
- [ ] VoiceOver reads theme picker rows as
      "\<Theme Name\> theme".
- [ ] VoiceOver reads the font size picker segments with their
      full localized names ("Small", "Default", "Large",
      "Extra Large").
- [ ] VoiceOver reads Save / Cancel as "Save notch
      customization" / "Cancel notch customization".
- [ ] VoiceOver reads Drag Mode with an accessibility value of
      "On" / "Off".
