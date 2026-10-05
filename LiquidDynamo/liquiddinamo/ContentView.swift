//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: LiquidViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = LiquidViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject var batteryAlertManager = BluetoothBatteryAlertManager.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var showcaseCoordinator = DeviceShowcaseCoordinator.shared
    @ObservedObject var island = IslandController.shared
    @ObservedObject var motion = IslandMotion.shared
    @ObservedObject var hub = LiveActivityCenter.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.showCollapsedCPUWing) var showCollapsedCPUWing
    @Default(.showCollapsedNetworkWing) var showCollapsedNetworkWing

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            // 0. Liquid Metaball Gooey Split & Merge Canvas (Active ONLY during animation)
            GooeySplitView()

            // 1. Detached Satellite Bubble (Minimal Multi-Activity)
            if island.isDetachedBubbleVisible {
                ZStack {
                    Circle()
                        .fill(Color.black)
                        .shadow(
                            color: Defaults[.enableShadow] ? Color.black.opacity(0.5) : Color.clear,
                            radius: 4,
                            y: 2
                        )

                    if let secondary = island.secondaryActivity {
                        if let icon = secondary.leadingIcon {
                            Image(systemName: icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(secondary.tintColor)
                        } else {
                            Circle()
                                .fill(secondary.tintColor)
                                .frame(width: 8, height: 8)
                        }
                    } else {
                        Image(systemName: "timer")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .frame(width: island.detachedBubbleSize.width, height: island.detachedBubbleSize.height)
                .offset(
                    x: (island.targetSize.width / 2.0) + island.detachedBubbleGap + (island.detachedBubbleSize.width / 2.0),
                    y: 0
                )
                .transition(.scale(scale: 0.2).combined(with: .opacity))
                .onHover { hovering in
                    if hovering {
                        island.onHoverEntered()
                    } else {
                        island.onHoverExited()
                    }
                }
                .onTapGesture {
                    island.setExpanded()
                }
            }

            // 2. Primary Dynamic Island Shape & Liquid Glass Container
            ZStack(alignment: .top) {
                // Multi-layer Liquid Glass backdrop with real-time blur and ambient lighting
                LiquidGlassContainerBackdrop(
                    topCornerRadius: island.topCornerRadius,
                    bottomCornerRadius: island.bottomCornerRadius,
                    isFloating: island.isFloatingDisplay,
                    isExpanded: island.state == .expanded,
                    ambientColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor) : nil
                )

                // Clipped Layout Content
                NotchLayout()
                    .padding(
                        .horizontal,
                        island.state == .expanded
                        ? (Defaults[.cornerRadiusScaling] ? cornerRadiusInsets.opened.top : cornerRadiusInsets.opened.bottom)
                        : 0
                    )
                    .padding([.horizontal, .bottom], island.state == .expanded ? 12 : 0)
                    .frame(
                        width: island.targetSize.width,
                        height: island.targetSize.height,
                        alignment: .top
                    )
                    .clipped()
                    .clipShape(
                        DynamicIslandShape(
                            topCornerRadius: island.topCornerRadius,
                            bottomCornerRadius: island.bottomCornerRadius,
                            isFloating: island.isFloatingDisplay
                        )
                    )
            }
            .frame(
                width: island.targetSize.width,
                height: island.targetSize.height,
                alignment: .top
            )
            .contentShape(
                DynamicIslandShape(
                    topCornerRadius: island.topCornerRadius,
                    bottomCornerRadius: island.bottomCornerRadius,
                    isFloating: island.isFloatingDisplay
                )
            )
            .onHover { hovering in
                if hovering {
                    island.onHoverEntered()
                } else {
                    island.onHoverExited()
                }
            }
            .onTapGesture {
                island.toggle()
            }
            .conditionalModifier(Defaults[.enableGestures]) { view in
                view
                    .panGesture(direction: .down) { translation, phase in
                        handleDownGesture(translation: translation, phase: phase)
                    }
            }
            .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                view
                    .panGesture(direction: .up) { translation, phase in
                        handleUpGesture(translation: translation, phase: phase)
                    }
            }
            .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                if island.state == .expanded && !island.isHovering && !vm.isBatteryPopoverActive {
                    hoverTask?.cancel()
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            if self.island.state == .expanded && !self.island.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                self.island.transitionTo(self.island.resolveRestingState())
                            }
                        }
                    }
                }
            }
            .onChange(of: vm.notchState) { _, newState in
                updateSystemStatsLifecycle()
                if newState == .closed && isHovering {
                    withAnimation {
                        isHovering = false
                    }
                }
            }
            .onChange(of: coordinator.currentView) { _, _ in
                updateSystemStatsLifecycle()
                updateNetworkLifecycle()
            }
            .onChange(of: showCollapsedCPUWing) { _, _ in
                updateSystemStatsLifecycle()
            }
            .onChange(of: showCollapsedNetworkWing) { _, _ in
                updateNetworkLifecycle()
            }
            .onChange(of: vm.isBatteryPopoverActive) {
                if !vm.isBatteryPopoverActive && !island.isHovering && island.state == .expanded && !SharingStateManager.shared.preventNotchClose {
                    hoverTask?.cancel()
                    hoverTask = Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            if !self.vm.isBatteryPopoverActive && !self.island.isHovering && self.island.state == .expanded && !SharingStateManager.shared.preventNotchClose {
                                self.island.transitionTo(self.island.resolveRestingState())
                            }
                        }
                    }
                }
            }
            .sensoryFeedback(.alignment, trigger: haptics)
            .contextMenu {
                Button("Settings") {
                    DispatchQueue.main.async {
                        SettingsWindowController.shared.showWindow()
                    }
                }
                .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                #if DEBUG
                Divider()
                Toggle("Show Layout Guides", isOn: Binding(
                    get: { NotchSafeAreaEngine.shared.showLayoutGuides },
                    set: { NotchSafeAreaEngine.shared.showLayoutGuides = $0 }
                ))
                Button("Run Notch Safety Tests") {
                    NotchSafetyTester.shared.runAllTests()
                }
                Divider()
                Button("Motion Tuner…") {
                    DispatchQueue.main.async {
                        MotionTuningWindowController.shared.show()
                    }
                }
                .keyboardShortcut("M", modifiers: [.command, .option])
                Button("Liquid Island Engine Inspector…") {
                    DispatchQueue.main.async {
                        LiquidEngineDebugWindowController.shared.show()
                    }
                }
                .keyboardShortcut("L", modifiers: [.command, .option])
                #endif
            }

            // 3. Below-Area Presentations (Alert Pop Droplet/Capsule, Notification Cards, Bluetooth/AirPods, Device Showcase)
            belowAreaPresentations

            // 4. Layout Guides Overlay (DEBUG Mode)
            if NotchSafeAreaEngine.shared.showLayoutGuides {
                NotchLayoutGuidesOverlay()
            }
        }
        .padding(.bottom, 8)
        .frame(maxWidth: windowSize.width, maxHeight: windowSize.height, alignment: .top)
        .coordinateSpace(name: "NotchWindowCoordinateSpace")
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if vm.notchState == .closed {
                    coordinator.currentView = .shelf
                    doOpen()
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
        .onAppear {
            updateSystemStatsLifecycle()
        }
    }

    @ViewBuilder
    private var belowAreaPresentations: some View {
        let notchH = NotchSafeAreaEngine.shared.currentGeometry.notchHeight
        if vm.notchState == .closed {
            if let notif = hub.activeNotification {
                LiveActivityTemplateView(
                    mode: .liquidDropletBloom,
                    tintColor: notif.tint,
                    dwellDuration: notif.duration ?? 4.0,
                    onDismiss: { hub.dismissNotification() }
                ) {
                    NotificationLiveActivityView(activity: notif) {
                        hub.dismissNotification()
                    }
                }
                .offset(y: notchH + 8)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .scale(scale: 0.9).combined(with: .opacity)
                ))
            } else if let alert = island.activeAlert, island.state == .alertPop {
                if alert.id.contains("volume") {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: Color.accentColor,
                        dwellDuration: alert.dwellDuration ?? 2.0,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        VolumeLiveActivityView(onDismiss: { island.dismissAlert() })
                    }
                    .offset(y: notchH + 8)
                } else if alert.id.contains("charging") || alert.id.contains("lowBattery") {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.iconColor ?? Color.green,
                        dwellDuration: alert.dwellDuration ?? 3.5,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        BatteryLiveActivityView(
                            isCriticalOverride: alert.id.contains("Critical") || alert.subtitle?.contains("5%") == true,
                            onDismiss: { island.dismissAlert() }
                        )
                    }
                    .offset(y: notchH + 8)
                } else if alert.id.contains("timer") {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: Color.orange,
                        dwellDuration: alert.dwellDuration ?? 4.0,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        TimerLiveActivityView(onDismiss: { island.dismissAlert() })
                    }
                    .offset(y: notchH + 8)
                } else if alert.id.contains("music") {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.iconColor ?? Color.accentColor,
                        dwellDuration: alert.dwellDuration ?? 4.0,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        MediaLiveActivityView(onDismiss: { island.dismissAlert() })
                    }
                    .offset(y: notchH + 8)
                } else if alert.id.contains("calendar") {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: Color.blue,
                        dwellDuration: alert.dwellDuration ?? 4.0,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        CalendarLiveActivityView(customTitle: alert.title, customSubtitle: alert.subtitle, onDismiss: { island.dismissAlert() })
                    }
                    .offset(y: notchH + 8)
                } else if alert.id.contains("download") || alert.id.contains("shelf") {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: Color.cyan,
                        dwellDuration: alert.dwellDuration ?? 3.5,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        ClipboardShelfLiveActivityView(onDismiss: { island.dismissAlert() })
                    }
                    .offset(y: notchH + 8)
                } else {
                    let cardWidth = alert.customSize?.width ?? 400
                    let cardHeight = alert.customSize?.height ?? 50
                    IslandAlertView(alert: alert)
                        .frame(width: cardWidth, height: cardHeight)
                        .offset(y: notchH + 8)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9).combined(with: .opacity),
                            removal: .scale(scale: 0.85).combined(with: .opacity)
                        ))
                }
            } else if let alert = hub.activeAlert {
                if alert.source == "battery" {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.tint,
                        dwellDuration: alert.duration ?? 3.5,
                        onDismiss: { hub.dismissAlert() }
                    ) {
                        BatteryLiveActivityView(onDismiss: { hub.dismissAlert() })
                    }
                    .offset(y: notchH + 8)
                } else if alert.source == "timer" {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.tint,
                        dwellDuration: alert.duration ?? 4.0,
                        onDismiss: { hub.dismissAlert() }
                    ) {
                        TimerLiveActivityView(onDismiss: { hub.dismissAlert() })
                    }
                    .offset(y: notchH + 8)
                } else if alert.source == "calendar_events" || alert.source == "calendar" {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.tint,
                        dwellDuration: alert.duration ?? 4.0,
                        onDismiss: { hub.dismissAlert() }
                    ) {
                        CalendarLiveActivityView(customTitle: alert.payload.title, customSubtitle: alert.payload.subtitle, onDismiss: { hub.dismissAlert() })
                    }
                    .offset(y: notchH + 8)
                } else if alert.source == "shelf" || alert.source == "download" {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.tint,
                        dwellDuration: alert.duration ?? 3.5,
                        onDismiss: { hub.dismissAlert() }
                    ) {
                        ClipboardShelfLiveActivityView(onDismiss: { hub.dismissAlert() })
                    }
                    .offset(y: notchH + 8)
                } else {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.tint,
                        dwellDuration: alert.duration ?? 3.5,
                        onDismiss: { hub.dismissAlert() }
                    ) {
                        GenericAlertLiveActivityView(activity: alert, onDismiss: { hub.dismissAlert() })
                    }
                    .offset(y: notchH + 8)
                }
            } else if showcaseCoordinator.isShowing,
                      let device = showcaseCoordinator.currentDevice {
                DeviceShowcasePopupView(device: device)
                    .offset(y: notchH + 8)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else if BluetoothBatteryAlertManager.shared.isShowingAlertPopup,
                      let alert = BluetoothBatteryAlertManager.shared.currentAlert {
                BluetoothBatteryAlertPopupView(alert: alert)
                    .offset(y: notchH + 8)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else if let hud = hub.activeHUD {
                if hud.source == "volume" {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: Color.accentColor,
                        dwellDuration: hud.duration ?? 2.0,
                        onDismiss: { hub.dismissHUD() }
                    ) {
                        VolumeLiveActivityView(onDismiss: { hub.dismissHUD() })
                    }
                    .offset(y: notchH + 8)
                } else if hud.source == "brightness" {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: Color.orange,
                        dwellDuration: hud.duration ?? 2.0,
                        onDismiss: { hub.dismissHUD() }
                    ) {
                        BrightnessLiveActivityView(onDismiss: { hub.dismissHUD() })
                    }
                    .offset(y: notchH + 8)
                } else {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: hud.tint,
                        dwellDuration: hud.duration ?? 2.5,
                        onDismiss: { hub.dismissHUD() }
                    ) {
                        LiveActivityHUDView(activity: hud)
                    }
                    .offset(y: notchH + 8)
                }
            } else if let prog = hub.activeProgress {
                LiveActivityProgressView(activity: prog)
                    .offset(y: notchH + 8)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else if vm.notchState == .closed {
                    let geom = NotchSafeAreaEngine.shared.currentGeometry
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && Defaults[.showPowerStatusNotifications]
                    {
                        HStack(spacing: 0) {
                            HStack {
                                Text(batteryModel.statusText)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                            }
                            .frame(width: max(0, geom.wingWidth - 6), alignment: .leading)
                            .padding(.leading, 6)
                            .clipped()
                            .avoidsNotch(id: "BatterySneakLeft")

                            Rectangle()
                                .fill(geom.hasPhysicalNotch ? Color.black : Color.clear)
                                .frame(width: geom.rawNotchWidth, height: geom.notchHeight)

                            HStack {
                                LiquidBatteryView(
                                    batteryWidth: 30,
                                    isCharging: batteryModel.isCharging,
                                    isInLowPowerMode: batteryModel.isInLowPowerMode,
                                    isPluggedIn: batteryModel.isPluggedIn,
                                    levelBattery: batteryModel.levelBattery,
                                    isForNotification: true
                                )
                            }
                            .frame(width: max(0, geom.wingWidth - 6), alignment: .trailing)
                            .padding(.trailing, 6)
                            .clipped()
                            .avoidsNotch(id: "BatterySneakRight")
                        }
                        .frame(width: geom.compactPillWidth, height: geom.notchHeight, alignment: .center)
                      } else if coordinator.expandingView.type == .bluetooth && coordinator.expandingView.show && vm.notchState == .closed {
                          HStack(spacing: 0) {
                              HStack(spacing: 6) {
                                  Image(systemName: "antenna.radiowaves.left.and.right")
                                      .font(.system(size: 11, weight: .semibold))
                                      .foregroundStyle(.blue)
                                  Text(BluetoothService.shared.lastConnectedDeviceName)
                                      .font(.system(size: 11, weight: .medium))
                                      .foregroundStyle(.white)
                                      .lineLimit(1)
                              }
                              .frame(width: max(0, geom.wingWidth - 6), alignment: .leading)
                              .padding(.leading, 6)
                              .clipped()
                              .avoidsNotch(id: "BTSneakLeft")

                              Rectangle()
                                  .fill(geom.hasPhysicalNotch ? Color.black : Color.clear)
                                  .frame(width: geom.rawNotchWidth, height: geom.notchHeight)

                              HStack(spacing: 4) {
                                  Circle()
                                      .fill(Color.green)
                                      .frame(width: 6, height: 6)
                                  Text("Connected")
                                      .font(.system(size: 10, weight: .medium))
                                      .foregroundStyle(.secondary)
                              }
                              .frame(width: max(0, geom.wingWidth - 6), alignment: .trailing)
                              .padding(.trailing, 6)
                              .clipped()
                              .avoidsNotch(id: "BTSneakRight")
                          }
                          .frame(width: geom.compactPillWidth, height: geom.notchHeight, alignment: .center)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                              .islandCompactSwap(id: "\(island.primaryActivity?.id ?? "")-\(musicManager.songTitle)-\(musicManager.artistName)")
                      } else if let primary = island.primaryActivity, primary.kind != .musicPlayback, vm.notchState == .closed && !vm.hideOnClosed {
                          CompactGenericActivityView(activity: primary)
                              .islandCompactSwap(id: "\(primary.id)-\(primary.title ?? "")")
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          liquidFaceAnimation()
                              .islandCompactSwap(id: "faceAnimation")
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (Defaults[.showCollapsedCPUWing] || Defaults[.showCollapsedBluetoothWing] || Defaults[.showCollapsedNetworkWing]) && !vm.hideOnClosed {
                          CollapsedLiveInfoWingsView()
                              .islandCompactSwap(id: "wingsView")
                       } else if vm.notchState == .open {
                           VStack(spacing: 4) {
                               if let notif = hub.activeNotification {
                                   LiveActivityNotificationCardView(activity: notif) {
                                       hub.dismissNotification()
                                   }
                               } else if let alert = hub.activeAlert {
                                   LiveActivityExpandedDetailsView(activity: alert) {
                                       hub.dismissAlert()
                                   }
                               } else if let expandedAlert = island.activeExpandedAlert {
                                   ExpandedAlertBannerView(alert: expandedAlert) {
                                       island.dismissExpandedAlert()
                                   }
                               }
                               LiquidHeader()
                                   .frame(height: max(vm.effectiveClosedNotchHeight, NotchSafeAreaEngine.shared.currentGeometry.exclusionHeight))
                                   .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                           }
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.notchExclusionWidth, height: vm.effectiveClosedNotchHeight)
                       }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .overlay(alignment: .trailing) {
                  if batteryAlertManager.hasActiveLowBatteryDot && Defaults[.keepLowBatteryDot]
                      && vm.notchState == .closed && !batteryAlertManager.isShowingAlertPopup
                  {
                      Button {
                          coordinator.currentView = .bluetooth
                          vm.open()
                          BluetoothBatteryAlertManager.shared.dismissDot()
                      } label: {
                          Circle()
                              .fill(Color.orange)
                              .frame(width: 6, height: 6)
                              .shadow(color: Color.orange.opacity(0.8), radius: 2)
                      }
                      .buttonStyle(.plain)
                      .padding(.trailing, 6)
                      .help(String(localized: "Low battery. Click to view Bluetooth devices."))
                  }
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack {
                    switch coordinator.currentView {
                    case .home:
                        DashboardHomeView(albumArtNamespace: albumArtNamespace)
                    case .stats:
                        SystemStatsView()
                    case .bluetooth:
                        BluetoothDevicesView()
                    case .displaySound:
                        DisplayAndSoundView()
                    case .shelf:
                        ShelfView()
                    case .calendar:
                        CalendarView().environmentObject(vm)
                    case .devices:
                        DeviceLibraryView()
                    case .network:
                        NetworkTabView()
                    }
                }
                .islandContentIn(when: island.isExpandedContentVisible)
                .islandContentOut(when: !island.isExpandedContentVisible)
                .animation(motion.compactSwapAnimation, value: coordinator.currentView)
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open && island.isExpandedContentVisible)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    @ViewBuilder
    func liquidFaceAnimation() -> some View {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        HStack(spacing: 0) {
            if geom.isNotched {
                Rectangle()
                    .fill(.clear)
                    .frame(width: max(0, geom.wingWidth))
                Rectangle()
                    .fill(.black)
                    .frame(width: geom.rawNotchWidth)
                MinimalFaceFeatures()
                    .frame(width: max(0, geom.wingWidth), alignment: .center)
                    .clipped()
                    .avoidsNotch(id: "FaceFeaturesRight")
            } else {
                MinimalFaceFeatures()
                    .padding(.horizontal, 12)
                    .avoidsNotch(id: "FaceFeaturesPill")
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    func CompactGenericActivityView(activity: IslandActivity) -> some View {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        HStack(spacing: 0) {
            if geom.isNotched {
                HStack(spacing: 6) {
                    if let icon = activity.leadingIcon {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(activity.tintColor)
                    }
                    if let title = activity.title {
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(width: max(0, geom.wingWidth - 8), alignment: .leading)
                .clipped()
                .padding(.leading, 8)
                .avoidsNotch(id: "CompactActivityLeft")

                Rectangle()
                    .fill(.black)
                    .frame(width: geom.rawNotchWidth)

                HStack(spacing: 6) {
                    if let trailingText = activity.trailingText {
                        Text(trailingText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if let trailingIcon = activity.trailingIcon {
                        Image(systemName: trailingIcon)
                            .font(.system(size: 12))
                            .foregroundStyle(activity.tintColor)
                    }
                }
                .frame(width: max(0, geom.wingWidth - 8), alignment: .trailing)
                .clipped()
                .padding(.trailing, 8)
                .avoidsNotch(id: "CompactActivityRight")
            } else {
                HStack(spacing: 8) {
                    if let icon = activity.leadingIcon {
                        Image(systemName: icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(activity.tintColor)
                    }
                    if let title = activity.title {
                        Text(title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                    if let trailingText = activity.trailingText {
                        Text(trailingText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } else if let trailingIcon = activity.trailingIcon {
                        Image(systemName: trailingIcon)
                            .font(.system(size: 12))
                            .foregroundStyle(activity.tintColor)
                    }
                }
                .padding(.horizontal, 12)
                .avoidsNotch(id: "CompactActivityPill")
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight)
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        HStack(spacing: 0) {
            if geom.isNotched {
                // Leading wing: album art
                HStack {
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: max(0, vm.effectiveClosedNotchHeight - 12),
                            height: max(0, vm.effectiveClosedNotchHeight - 12)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                        )
                        .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                }
                .frame(width: max(0, geom.wingWidth - 6), alignment: .leading)
                .padding(.leading, 6)
                .clipped()
                .avoidsNotch(id: "MusicLiveLeading")

                // Center: Notch hole (completely empty, black backing only)
                Rectangle()
                    .fill(.black)
                    .frame(width: geom.rawNotchWidth)

                // Trailing wing: visualizer
                HStack {
                    if useMusicVisualizer {
                        Rectangle()
                            .fill(
                                Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor).gradient
                                    : Color.gray.gradient
                            )
                            .frame(width: 32, alignment: .center)
                            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                            .mask {
                                AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                    .frame(width: 16, height: 12)
                            }
                    } else {
                        LottieAnimationContainer()
                            .frame(width: 20, height: 20)
                    }
                }
                .frame(width: max(0, geom.wingWidth - 6), alignment: .trailing)
                .padding(.trailing, 6)
                .clipped()
                .avoidsNotch(id: "MusicLiveTrailing")
            } else {
                HStack(spacing: 10) {
                    Image(nsImage: musicManager.albumArt)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(
                            width: max(0, vm.effectiveClosedNotchHeight - 12),
                            height: max(0, vm.effectiveClosedNotchHeight - 12)
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                        )
                        .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)

                    if useMusicVisualizer {
                        Rectangle()
                            .fill(
                                Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor).gradient
                                    : Color.gray.gradient
                            )
                            .frame(width: 24, height: 12, alignment: .center)
                            .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                            .mask {
                                AudioSpectrumView(isPlaying: $musicManager.isPlaying)
                                    .frame(width: 16, height: 12)
                            }
                    }
                }
                .padding(.horizontal, 10)
                .avoidsNotch(id: "MusicLivePill")
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    private func doOpen() {
        island.setExpanded()
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard island.state != .expanded else { return }

        if phase == .ended {
            withAnimation(motion.collapseSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(motion.expandSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(motion.collapseSpring) {
                gestureProgress = .zero
            }
            island.setExpanded()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard island.state == .expanded && !vm.isHoveringCalendar else { return }

        withAnimation(motion.collapseSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(motion.collapseSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                island.transitionTo(island.resolveRestingState())
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }

    private func updateSystemStatsLifecycle() {
        let shouldRun: Bool
        if vm.notchState == .closed {
            shouldRun = Defaults[.showCollapsedCPUWing]
        } else {
            shouldRun = coordinator.currentView == .stats || coordinator.currentView == .home
        }
        if shouldRun {
            SystemStatsService.shared.start()
        } else {
            SystemStatsService.shared.stop()
        }
    }

    private func updateNetworkLifecycle() {
        let shouldRun: Bool
        if vm.notchState == .closed {
            shouldRun = Defaults[.showCollapsedNetworkWing]
        } else {
            shouldRun = coordinator.currentView == .network
        }
        if shouldRun {
            NetworkThroughputService.shared.start()
        } else {
            NetworkThroughputService.shared.stop()
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool

    func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        return false
    }
}

#Preview {
    let vm = LiquidViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}

// MARK: - Collapsed Live Info Wings

struct CollapsedLiveInfoWingsView: View {
    @EnvironmentObject var vm: LiquidViewModel
    @ObservedObject var statsService = SystemStatsService.shared
    @ObservedObject var bluetoothService = BluetoothService.shared
    @ObservedObject var throughputService = NetworkThroughputService.shared
    @Default(.showCollapsedCPUWing) var showCPUWing
    @Default(.showCollapsedBluetoothWing) var showBTWing
    @Default(.showCollapsedNetworkWing) var showNetworkWing

    var body: some View {
        let geom = NotchSafeAreaEngine.shared.currentGeometry
        HStack(spacing: 0) {
            if geom.isNotched {
                // Left Wing: CPU %
                HStack(spacing: 3) {
                    if showCPUWing {
                        Image(systemName: "cpu")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(cpuColor(statsService.overallCPU))
                        Text("\(Int(statsService.overallCPU))%")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
                .frame(width: max(0, geom.wingWidth - 6), alignment: .leading)
                .padding(.leading, 6)
                .clipped()
                .avoidsNotch(id: "WingsLeft")

                // Center Notch Block (pure black, no text or icons)
                Rectangle()
                    .fill(.black)
                    .frame(width: geom.rawNotchWidth)

                // Right Wing: Live Network Speed or Bluetooth
                HStack(spacing: 3) {
                    if showNetworkWing {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.green)
                            Text(formatCompact(throughputService.downloadBytesPerSecond))
                                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.purple)
                            Text(formatCompact(throughputService.uploadBytesPerSecond))
                                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    } else if showBTWing {
                        if let firstDevice = bluetoothService.connectedDevices.first, let battery = firstDevice.batteryPercentage {
                            Image(systemName: firstDevice.iconName)
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                            Text("\(battery)%")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        } else if !bluetoothService.connectedDevices.isEmpty {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.blue)
                            Text("\(bluetoothService.connectedDevices.count)")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: max(0, geom.wingWidth - 6), alignment: .trailing)
                .padding(.trailing, 6)
                .clipped()
                .avoidsNotch(id: "WingsRight")
            } else {
                HStack(spacing: 8) {
                    if showCPUWing {
                        HStack(spacing: 3) {
                            Image(systemName: "cpu")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(cpuColor(statsService.overallCPU))
                            Text("\(Int(statsService.overallCPU))%")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }
                    if showNetworkWing {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.green)
                            Text(formatCompact(throughputService.downloadBytesPerSecond))
                                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.purple)
                            Text(formatCompact(throughputService.uploadBytesPerSecond))
                                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    } else if showBTWing {
                        if let firstDevice = bluetoothService.connectedDevices.first, let battery = firstDevice.batteryPercentage {
                            Image(systemName: firstDevice.iconName)
                                .font(.system(size: 8))
                                .foregroundStyle(.white)
                            Text("\(battery)%")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .avoidsNotch(id: "WingsPill")
            }
        }
        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
        .onAppear {
            if showCPUWing {
                statsService.start()
            }
            if showNetworkWing {
                throughputService.start()
            }
        }
        .onChange(of: showCPUWing) { _, enabled in
            if enabled {
                statsService.start()
            } else if vm.notchState == .closed {
                statsService.stop()
            }
        }
        .onChange(of: showNetworkWing) { _, enabled in
            if enabled {
                throughputService.start()
            } else if vm.notchState == .closed && LiquidViewCoordinator.shared.currentView != .network {
                throughputService.stop()
            }
        }
    }

    private func formatCompact(_ bytesPerSecond: Double) -> String {
        let b = max(0, bytesPerSecond)
        if b >= 1_000_000 {
            return String(format: "%.1fM", b / 1_000_000.0)
        } else if b >= 1_000 {
            return String(format: "%.0fK", b / 1_000.0)
        } else {
            return "0K"
        }
    }

    private func cpuColor(_ val: Double) -> Color {
        if val >= 80 { return .red }
        if val >= 50 { return .orange }
        return .green
    }
}
