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

struct NotchContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = max(value, next)
        }
    }
}

struct LeftWingWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

struct RightWingWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 {
            value = next
        }
    }
}

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
    @ObservedObject var sensorMonitor = HardwareSensorMonitor.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.leftWingMetric) var leftWingMetric
    @Default(.rightWingMetric) var rightWingMetric

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        let isExpandedState = (island.state == .expanded || vm.notchState == .open)

        ZStack(alignment: .top) {
            // Liquid Notch Content Presentation (Adaptive Liquid Glass Surface)
            ZStack(alignment: .top) {
                // Multi-layer Liquid Glass backdrop (Only rendered when collapsed; when expanded, background is removed per user request)
                LiquidGlassContainerBackdrop(
                    topCornerRadius: island.topCornerRadius,
                    bottomCornerRadius: island.bottomCornerRadius,
                    isFloating: !vm.geometry.hasPhysicalNotch,
                    isExpanded: isExpandedState,
                    ambientColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor) : nil
                )

                if isExpandedState {
                    // Unclipped layout with dynamic height measurement: adapts area according to content
                    NotchLayout()
                        .frame(width: island.targetSize.width, alignment: .top)
                        .background(
                            GeometryReader { proxy in
                                Color.clear.preference(key: NotchContentHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        )
                } else {
                    // Collapsed resting notch
                    NotchLayout()
                        .frame(
                            width: island.targetSize.width,
                            height: island.targetSize.height,
                            alignment: .top
                        )
                }
            }
            .frame(
                width: island.targetSize.width,
                height: island.targetSize.height,
                alignment: .top
            )
            .animation(motion.expandSpring, value: island.targetSize)
            .onPreferenceChange(NotchContentHeightPreferenceKey.self) { measuredHeight in
                if isExpandedState && measuredHeight > 50 {
                    island.adjustTargetHeightIfNeeded(measuredHeight)
                }
            }
            .conditionalModifier(isExpandedState) { view in
                view.contentShape(Rectangle())
            }
            .conditionalModifier(!isExpandedState) { view in
                view.contentShape(
                    DynamicIslandShape(
                        topCornerRadius: island.topCornerRadius,
                        bottomCornerRadius: island.bottomCornerRadius,
                        isFloating: !vm.geometry.hasPhysicalNotch
                    )
                )
            }
            // Localized Hardware Privacy Indicator Notch Glow (Camera = Green, Mic = Amber, Both = Dual Gradient)
            .overlay {
                privacyIndicatorOverlay(isExpandedState: isExpandedState)
            }
            // Powerload Glowing Download Progress Bar Directly Under Notch (1% Red -> 100% Green)
            .overlay(alignment: .bottom) {
                PowerloadUnderNotchProgressBar(isExpanded: isExpandedState)
                    .offset(y: isExpandedState ? -2 : 0)
            }
            // Dedicated Activation Zone: Aligned strictly inside visible notch bounds
            .overlay(alignment: .top) {
                if island.state != .expanded && vm.notchState != .open {
                    let geom = vm.geometry
                    let notchW = geom.hasPhysicalNotch ? (geom.rawNotchWidth > 0 ? geom.rawNotchWidth : 180.0) : 140.0
                    Color.clear
                        .frame(width: notchW, height: geom.notchHeight)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering {
                                island.onHoverEntered()
                            } else {
                                island.onHoverExited()
                            }
                        }
                        .onTapGesture {
                            island.setExpanded(pin: true)
                        }
                }
            }
            .onHover { hovering in
                // Only monitor expanded hover to pause auto-retraction while user interacts
                if island.state == .expanded || vm.notchState == .open {
                    if hovering {
                        island.onHoverEntered()
                    } else if !island.isPinnedOpen && island.activeOrganicItem == .none {
                        island.onHoverExited()
                    }
                }
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
            .onChange(of: island.state) { _, _ in
                updateSystemStatsLifecycle()
                updateNetworkLifecycle()
            }
            .onChange(of: coordinator.currentView) { _, _ in
                updateSystemStatsLifecycle()
                updateNetworkLifecycle()
            }
            .onChange(of: leftWingMetric) { _, _ in
                updateSystemStatsLifecycle()
                updateNetworkLifecycle()
            }
            .onChange(of: rightWingMetric) { _, _ in
                updateSystemStatsLifecycle()
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
                Button("Step B Multi-Blob Inspector…") {
                    DispatchQueue.main.async {
                        LiquidBlobDebugWindowController.shared.show()
                    }
                }
                .keyboardShortcut("B", modifiers: [.command, .option])
                #endif
            }

            // 3. Below-Area Presentations (Alert Pop Droplet/Capsule, Notification Cards, Bluetooth/AirPods, Device Showcase)
            belowAreaPresentations

            #if DEBUG
            // 4. Layout Guides Overlay (DEBUG Mode Only)
            if NotchSafeAreaEngine.shared.showLayoutGuides {
                NotchLayoutGuidesOverlay()
            }
            #endif
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
        let geom = vm.geometry
        let notchH = geom.notchHeight
        let yOffset = geom.isNotched ? (notchH + 8) : 0
        if vm.notchState == .closed && island.state != .expanded && island.activeExpandedAlert == nil {
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
                .offset(y: yOffset)
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
                    .offset(y: yOffset)
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
                    .offset(y: yOffset)
                } else if alert.id.contains("timer") {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: Color.orange,
                        dwellDuration: alert.dwellDuration ?? 4.0,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        TimerLiveActivityView(onDismiss: { island.dismissAlert() })
                    }
                    .offset(y: yOffset)
                } else if alert.id.contains("music") {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.iconColor ?? Color.accentColor,
                        dwellDuration: alert.dwellDuration ?? 4.0,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        MediaLiveActivityView(onDismiss: { island.dismissAlert() })
                    }
                    .offset(y: yOffset)
                } else if alert.id.contains("calendar") {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: Color.blue,
                        dwellDuration: alert.dwellDuration ?? 4.0,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        CalendarLiveActivityView(customTitle: alert.title, customSubtitle: alert.subtitle, onDismiss: { island.dismissAlert() })
                    }
                    .offset(y: yOffset)
                } else if alert.id.contains("download") || alert.id.contains("shelf") {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: Color.cyan,
                        dwellDuration: alert.dwellDuration ?? 3.5,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        ClipboardShelfLiveActivityView(onDismiss: { island.dismissAlert() })
                    }
                } else if alert.id.contains("display") || alert.deviceIdentity?.kind == .monitor {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: Color.blue,
                        dwellDuration: alert.dwellDuration ?? 6.0,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        DisplayConnectedLiveActivityView(
                            alert: alert,
                            onDismiss: { island.dismissAlert() }
                        )
                    }
                    .offset(y: yOffset)
                } else {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.iconColor,
                        dwellDuration: alert.dwellDuration,
                        onDismiss: { island.dismissAlert() }
                    ) {
                        GenericAlertLiveActivityView(
                            title: alert.title,
                            subtitle: alert.subtitle,
                            icon: alert.iconName,
                            tint: alert.iconColor,
                            onDismiss: { island.dismissAlert() }
                        )
                    }
                    .offset(y: yOffset)
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
                    .offset(y: yOffset)
                } else if alert.source == "timer" {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.tint,
                        dwellDuration: alert.duration ?? 4.0,
                        onDismiss: { hub.dismissAlert() }
                    ) {
                        TimerLiveActivityView(onDismiss: { hub.dismissAlert() })
                    }
                    .offset(y: yOffset)
                } else if alert.source == "calendar_events" || alert.source == "calendar" {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.tint,
                        dwellDuration: alert.duration ?? 4.0,
                        onDismiss: { hub.dismissAlert() }
                    ) {
                        CalendarLiveActivityView(customTitle: alert.payload.title, customSubtitle: alert.payload.subtitle, onDismiss: { hub.dismissAlert() })
                    }
                    .offset(y: yOffset)
                } else if alert.source == "shelf" || alert.source == "download" {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.tint,
                        dwellDuration: alert.duration ?? 3.5,
                        onDismiss: { hub.dismissAlert() }
                    ) {
                        ClipboardShelfLiveActivityView(onDismiss: { hub.dismissAlert() })
                    }
                    .offset(y: yOffset)
                } else {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: alert.tint,
                        dwellDuration: alert.duration ?? 3.5,
                        onDismiss: { hub.dismissAlert() }
                    ) {
                        GenericAlertLiveActivityView(activity: alert, onDismiss: { hub.dismissAlert() })
                    }
                    .offset(y: yOffset)
                }
            } else if showcaseCoordinator.isShowing,
                      let device = showcaseCoordinator.currentDevice {
                DeviceShowcasePopupView(device: device)
                    .offset(y: yOffset)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else if BluetoothBatteryAlertManager.shared.isShowingAlertPopup,
                      let alert = BluetoothBatteryAlertManager.shared.currentAlert {
                BluetoothBatteryAlertPopupView(alert: alert)
                    .offset(y: yOffset)
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
                    .offset(y: yOffset)
                } else if hud.source == "brightness" {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: Color.orange,
                        dwellDuration: hud.duration ?? 2.0,
                        onDismiss: { hub.dismissHUD() }
                    ) {
                        BrightnessLiveActivityView(onDismiss: { hub.dismissHUD() })
                    }
                    .offset(y: yOffset)
                } else {
                    LiveActivityTemplateView(
                        mode: .liquidDropletBloom,
                        tintColor: hud.tint,
                        dwellDuration: hud.duration ?? 2.5,
                        onDismiss: { hub.dismissHUD() }
                    ) {
                        LiveActivityHUDView(activity: hud)
                    }
                    .offset(y: yOffset)
                }
            } else if let prog = hub.activeProgress {
                LiveActivityTemplateView(
                    mode: .liquidDropletBloom,
                    tintColor: prog.tint,
                    dwellDuration: prog.duration ?? 3.5,
                    onDismiss: { hub.dismissProgress() }
                ) {
                    LiveActivityProgressView(activity: prog)
                }
                .offset(y: yOffset)
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
                } else if (island.state == .expanded || vm.notchState == .open) {
                    let geom = vm.geometry
                    let topNotchGap = geom.isNotched ? (geom.notchHeight + 8) : 0
                    VStack(spacing: 4) {
                        if let notif = hub.activeNotification {
                            LiveActivityNotificationCardView(activity: notif) {
                                hub.dismissNotification()
                            }
                            .padding(.top, topNotchGap)
                            .padding(.horizontal, 14)
                        } else if let alert = hub.activeAlert {
                            ExpandedAlertBannerView(
                                alert: AlertPayload(
                                    id: alert.id,
                                    kind: .custom(title: alert.payload.title, subtitle: alert.payload.subtitle, icon: alert.payload.iconName),
                                    title: alert.payload.title,
                                    subtitle: alert.payload.subtitle ?? alert.payload.body,
                                    iconName: alert.payload.iconName,
                                    iconColor: alert.tint,
                                    dwellDuration: alert.duration ?? 3.5,
                                    action: alert.payload.action
                                )
                            ) {
                                hub.dismissAlert()
                            }
                            .padding(.top, topNotchGap)
                            .padding(.horizontal, 14)
                        } else if let expandedAlert = island.activeExpandedAlert {
                            ExpandedAlertBannerView(alert: expandedAlert) {
                                island.dismissExpandedAlert()
                            }
                            .padding(.top, topNotchGap)
                            .padding(.horizontal, 14)
                        } else if coordinator.currentView != .home {
                            LiquidHeader()
                                .frame(height: max(vm.effectiveClosedNotchHeight, vm.geometry.exclusionHeight))
                                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if vm.notchState == .closed {
                    if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && shouldShowSneakPeekHUD(coordinator.sneakPeek.type) {
                        InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                            .transition(.opacity)
                    } else {
                        // ALWAYS show CPU % on left and live Network Speed in text on right side of notch
                        CollapsedLiveInfoWingsView()
                            .islandCompactSwap(id: "wingsView")
                    }
                } else {
                    Rectangle().fill(.clear).frame(width: vm.notchExclusionWidth, height: vm.effectiveClosedNotchHeight)
                }

                       if coordinator.sneakPeek.show {
                           if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && shouldShowSneakPeekHUD(coordinator.sneakPeek.type) && !Defaults[.inlineHUD] && vm.notchState == .closed {
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
               .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                   view
                       .fixedSize()
               }
               .zIndex(2)
            if (island.state == .expanded || vm.notchState == .open) && (island.activeOrganicItem != .none || (island.activeExpandedAlert == nil && hub.activeAlert == nil && hub.activeNotification == nil)) {
                VStack(alignment: .center, spacing: 0) {
                    switch coordinator.currentView {
                    case .home:
                        DashboardHomeView(albumArtNamespace: albumArtNamespace)
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .stats:
                        SystemStatsView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .bluetooth:
                        BluetoothDevicesView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .displaySound:
                        DisplayAndSoundView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .shelf:
                        ShelfView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .calendar:
                        CalendarView().environmentObject(vm)
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .devices:
                        DeviceLibraryView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .network:
                        NetworkTabView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .cleaner:
                        NotchStorageCleanerView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .plexo, .powerload:
                        PowerloadView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .filedroid:
                        FileDroidView()
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .islandContentIn(when: island.isExpandedContentVisible)
                .islandContentOut(when: !island.isExpandedContentVisible)
                .animation(motion.compactSwapAnimation, value: coordinator.currentView)
                .zIndex(1)
                .allowsHitTesting((island.state == .expanded || vm.notchState == .open) && island.isExpandedContentVisible)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting))
    }

    func shouldShowSneakPeekHUD(_ type: SneakContentType) -> Bool {
        switch type {
        case .volume:
            return true
        case .brightness:
            return true
        case .battery:
            return false // Battery for Mac itself is not shown
        case .music, .backlight, .mic:
            return true
        default:
            return true
        }
    }

    @ViewBuilder
    private func privacyIndicatorOverlay(isExpandedState: Bool) -> some View {
        let cameraActive = sensorMonitor.isCameraActive
        let micActive = sensorMonitor.isMicrophoneActive
        if (cameraActive || micActive) && !isExpandedState {
            let colors: [Color] = {
                if cameraActive && micActive {
                    return [Color.green, Color.orange, Color.green]
                } else if cameraActive {
                    return [Color.green.opacity(0.9), Color.green]
                } else {
                    return [Color.orange.opacity(0.9), Color.orange]
                }
            }()
            let shadowCol = cameraActive ? Color.green.opacity(0.7) : Color.orange.opacity(0.7)

            DynamicIslandShape(
                topCornerRadius: island.topCornerRadius,
                bottomCornerRadius: island.bottomCornerRadius,
                isFloating: !vm.geometry.hasPhysicalNotch
            )
            .stroke(
                LinearGradient(
                    colors: colors,
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: 2.0
            )
            .shadow(
                color: shadowCol,
                radius: 5,
                x: 0,
                y: 1
            )
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }

    @ViewBuilder
    func liquidFaceAnimation() -> some View {
        let geom = vm.geometry
        HStack(spacing: 0) {
            if geom.isNotched {
                Rectangle()
                    .fill(.clear)
                    .frame(width: max(0, geom.wingWidth))
                Color.clear
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
        let geom = vm.geometry
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
                .padding(.leading, 8)
                .frame(width: max(0, geom.wingWidth - 8), alignment: .leading)
                .clipped()
                .avoidsNotch(id: "CompactActivityLeft")

                Color.clear
                    .frame(width: geom.rawNotchWidth + 16)

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
                .padding(.trailing, 8)
                .frame(width: max(0, geom.wingWidth - 8), alignment: .trailing)
                .clipped()
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
        .frame(width: geom.compactPillWidth, height: vm.effectiveClosedNotchHeight, alignment: .center)
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        let geom = vm.geometry
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
                .padding(.leading, 6)
                .frame(width: max(0, geom.wingWidth), alignment: .leading)
                .clipped()
                .avoidsNotch(id: "MusicLiveLeading")

                // Center: Notch hole (completely empty, transparent backing)
                Color.clear
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
                .padding(.trailing, 6)
                .frame(width: max(0, geom.wingWidth), alignment: .trailing)
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
        .frame(width: geom.compactPillWidth, height: vm.effectiveClosedNotchHeight, alignment: .center)
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
                island.isPinnedOpen = false
                island.activeOrganicItem = .none
                island.transitionTo(island.resolveRestingState())
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }

    private func updateSystemStatsLifecycle() {
        let isExpanded = (island.state == .expanded || vm.notchState == .open)
        let wingNeedsStats = Defaults[.leftWingMetric] == .cpuUsage || Defaults[.leftWingMetric] == .cpuTemp || Defaults[.leftWingMetric] == .ramUsage || Defaults[.leftWingMetric] == .ramDetails || Defaults[.leftWingMetric] == .battery || Defaults[.leftWingMetric] == .clock
            || Defaults[.rightWingMetric] == .cpuUsage || Defaults[.rightWingMetric] == .cpuTemp || Defaults[.rightWingMetric] == .ramUsage || Defaults[.rightWingMetric] == .ramDetails || Defaults[.rightWingMetric] == .battery || Defaults[.rightWingMetric] == .clock
        let shouldRun = isExpanded || wingNeedsStats
        if shouldRun {
            SystemStatsService.shared.start()
        } else {
            SystemStatsService.shared.stop()
        }
    }

    private func updateNetworkLifecycle() {
        let isExpanded = (island.state == .expanded || vm.notchState == .open)
        let wingNeedsNet = Defaults[.leftWingMetric] == .netDown || Defaults[.leftWingMetric] == .netUp || Defaults[.leftWingMetric] == .netDownUp
            || Defaults[.rightWingMetric] == .netDown || Defaults[.rightWingMetric] == .netUp || Defaults[.rightWingMetric] == .netDownUp
        let shouldRun = isExpanded || wingNeedsNet
        if shouldRun {
            NetworkThroughputService.shared.start()
            NetworkSpeedProvider.shared.start()
            ConnectionStatusService.shared.start()
        } else {
            NetworkThroughputService.shared.stop()
            NetworkSpeedProvider.shared.stop()
            ConnectionStatusService.shared.stop()
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
        return DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let providers = info.itemProviders(for: [.fileURL, .url, .utf8PlainText, .plainText, .data])
        guard !providers.isEmpty else { return false }
        ShelfStateViewModel.shared.load(providers)
        return true
    }
}

#if DEBUG
#Preview {
    let vm = LiquidViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
#endif

// MARK: - Notch-Anchored Liquid Droplet Shapes

struct LeftNotchDropShape: Shape {
    var cornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Top right: flush with notch wall
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        // Down the notch wall to bottom right
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        // Leftward along bottom edge
        path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
        // Rounded droplet tip on left
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - cornerRadius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        // Top edge back to notch wall
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct RightNotchDropShape: Shape {
    var cornerRadius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Top left: flush with notch wall
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Top edge outward to the right
        path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
        // Rounded droplet tip on right
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + cornerRadius),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        // Bottom edge back inward toward notch wall
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        // Up the notch wall to top left
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct CollapsedLiveInfoWingsView: View {
    @EnvironmentObject var vm: LiquidViewModel
    @ObservedObject var statsService = SystemStatsService.shared
    @ObservedObject var throughputService = NetworkThroughputService.shared
    @ObservedObject var speedProvider = NetworkSpeedProvider.shared
    @ObservedObject var connectionService = ConnectionStatusService.shared
    @ObservedObject var island = IslandController.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var deviceMonitor = DeviceMonitor.shared
    @ObservedObject var musicManager = MusicManager.shared

    @Default(.enableSideReadouts) var enableSideReadouts
    @Default(.leftWingMetric) var leftWingMetric: WingMetric
    @Default(.rightWingMetric) var rightWingMetric: WingMetric
    @Default(.hideWingsInFullScreen) var hideWingsInFullScreen
    @Default(.wingsBuiltInDisplayOnly) var wingsBuiltInDisplayOnly
    @Default(.islandTransparency) var islandTransparency
    @Default(.alwaysShowSideReadoutText) var alwaysShowSideReadoutText
    @Default(.wingWidth) var wingWidth: CGFloat
    @Default(.autoFitWings) var autoFitWings: Bool

    @State private var isLeftDetailExpanded: Bool = false
    @State private var isRightDetailExpanded: Bool = false
    @State private var isLeftHovering: Bool = false
    @State private var isRightHovering: Bool = false
    @State private var autoCollapseTask: Task<Void, Never>? = nil

    @State private var measuredLeftWingWidth: CGFloat = 46.0
    @State private var measuredRightWingWidth: CGFloat = 46.0

    private let minWingFloor: CGFloat = 36.0

    private var currentLeftWingWidth: CGFloat {
        guard leftWingMetric != .none else { return 0 }
        return autoFitWings ? max(minWingFloor, measuredLeftWingWidth) : max(minWingFloor, wingWidth)
    }

    private var currentRightWingWidth: CGFloat {
        guard rightWingMetric != .none else { return 0 }
        return autoFitWings ? max(minWingFloor, measuredRightWingWidth) : max(minWingFloor, wingWidth)
    }

    private var maxWingWidth: CGFloat {
        max(currentLeftWingWidth, currentRightWingWidth)
    }

    private var showLeftDetails: Bool {
        alwaysShowSideReadoutText || isLeftHovering || isLeftDetailExpanded || island.state == .expanded
    }

    private var showRightDetails: Bool {
        alwaysShowSideReadoutText || isRightHovering || isRightDetailExpanded || island.state == .expanded
    }

    private func scheduleAutoCollapse() {
        autoCollapseTask?.cancel()
        guard isLeftDetailExpanded || isRightDetailExpanded else { return }
        autoCollapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                self.isLeftDetailExpanded = false
                self.isRightDetailExpanded = false
            }
        }
    }

    private func reportDynamicWidth(geom: NotchGeometry) {
        let leftW = currentLeftWingWidth
        let rightW = currentRightWingWidth
        let maxW = max(leftW, rightW)
        let totalW: CGFloat = {
            if geom.isNotched {
                return geom.rawNotchWidth + 14.0 + (2.0 * maxW)
            } else {
                let leftPart = (leftWingMetric != .none) ? (leftW + 8.0) : 0
                let rightPart = (rightWingMetric != .none) ? (rightW + 8.0) : 0
                return 160.0 + leftPart + rightPart
            }
        }()
        IslandController.shared.adjustTargetWidthForWingsIfNeeded(totalW, wingWidth: maxW, leftWidth: leftW, rightWidth: rightW)
    }

    @ViewBuilder
    private func centralFloatingIslandPill(geom: NotchGeometry) -> some View {
        let centralPillW: CGFloat = 160.0
        ZStack {
            Capsule()
                .fill(Color.black)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.75)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.white.opacity(0.25))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().fill(Color.black).frame(width: 3, height: 3))

                if musicManager.isPlaying && !musicManager.songTitle.isEmpty {
                    Image(systemName: "music.note")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor) : .green)
                    Text(musicManager.songTitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("LiquidDynamo")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 10)
        }
        .frame(width: centralPillW, height: vm.effectiveClosedNotchHeight)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                vm.open(pinned: true)
            }
        }
        .onHover { hovering in
            if Defaults[.openNotchOnHover] && hovering {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    vm.open()
                }
            }
        }
    }

    var body: some View {
        let geom = vm.geometry
        let maxW = maxWingWidth

        Group {
            if !isFullScreenHidden && isDisplayAllowed(geom: geom) {
                if geom.isNotched {
                    if enableSideReadouts && (leftWingMetric != .none || rightWingMetric != .none) {
                        HStack(spacing: 0) {
                            // Left Drop Container: Anchored flush to the notch left edge
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                if leftWingMetric != .none {
                                    leftDropView(geom: geom, wingW: currentLeftWingWidth)
                                }
                            }
                            .frame(width: maxW, height: vm.effectiveClosedNotchHeight, alignment: .trailing)

                            // Center Hardware Notch Area (Clear hole matching hardware cutout)
                            Color.clear
                                .frame(width: geom.rawNotchWidth + 14)

                            // Right Drop Container: Anchored flush to the notch right edge
                            HStack(spacing: 0) {
                                if rightWingMetric != .none {
                                    rightDropView(geom: geom, wingW: currentRightWingWidth)
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(width: maxW, height: vm.effectiveClosedNotchHeight, alignment: .leading)
                        }
                        .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                        .onPreferenceChange(LeftWingWidthPreferenceKey.self) { w in
                            guard w > 0 else { return }
                            if abs(self.measuredLeftWingWidth - w) >= 1.5 {
                                self.measuredLeftWingWidth = w
                                self.reportDynamicWidth(geom: geom)
                            }
                        }
                        .onPreferenceChange(RightWingWidthPreferenceKey.self) { w in
                            guard w > 0 else { return }
                            if abs(self.measuredRightWingWidth - w) >= 1.5 {
                                self.measuredRightWingWidth = w
                                self.reportDynamicWidth(geom: geom)
                            }
                        }
                    } else {
                        EmptyView()
                    }
                } else {
                    // Non-notched display: Always show central Dynamic Island capsule, flanked by wings if enabled
                    HStack(spacing: 8) {
                        if enableSideReadouts && leftWingMetric != .none {
                            leftDropContent
                                .padding(.leading, 8)
                                .padding(.trailing, 9)
                                .padding(.vertical, 3)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: currentLeftWingWidth)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(key: LeftWingWidthPreferenceKey.self, value: proxy.size.width)
                                    }
                                )
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.75))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.75))
                                )
                                .onHover { hovering in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isLeftHovering = hovering
                                    }
                                }
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        isLeftDetailExpanded.toggle()
                                    }
                                    scheduleAutoCollapse()
                                }
                        }

                        // Central Floating Dynamic Island Pill
                        centralFloatingIslandPill(geom: geom)

                        if enableSideReadouts && rightWingMetric != .none {
                            rightDropContent
                                .padding(.leading, 8)
                                .padding(.trailing, 9)
                                .padding(.vertical, 3)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(minWidth: currentRightWingWidth)
                                .background(
                                    GeometryReader { proxy in
                                        Color.clear.preference(key: RightWingWidthPreferenceKey.self, value: proxy.size.width)
                                    }
                                )
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.75))
                                        .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 0.75))
                                )
                                .onHover { hovering in
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isRightHovering = hovering
                                    }
                                }
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                        isRightDetailExpanded.toggle()
                                    }
                                    scheduleAutoCollapse()
                                }
                        }
                    }
                    .frame(height: vm.effectiveClosedNotchHeight, alignment: .center)
                    .onPreferenceChange(LeftWingWidthPreferenceKey.self) { w in
                        guard w > 0 else { return }
                        if abs(self.measuredLeftWingWidth - w) >= 1.5 {
                            self.measuredLeftWingWidth = w
                            self.reportDynamicWidth(geom: geom)
                        }
                    }
                    .onPreferenceChange(RightWingWidthPreferenceKey.self) { w in
                        guard w > 0 else { return }
                        if abs(self.measuredRightWingWidth - w) >= 1.5 {
                            self.measuredRightWingWidth = w
                            self.reportDynamicWidth(geom: geom)
                        }
                    }
                }
            }
        }
        .onChange(of: leftWingMetric) { _ in
            self.reportDynamicWidth(geom: geom)
        }
        .onChange(of: rightWingMetric) { _ in
            self.reportDynamicWidth(geom: geom)
        }
        .onChange(of: autoFitWings) { _ in
            self.reportDynamicWidth(geom: geom)
        }
        .onChange(of: wingWidth) { _ in
            self.reportDynamicWidth(geom: geom)
        }
        .onReceive(NotificationCenter.default.publisher(for: .toggleSideReadoutDetails)) { notif in
            if let target = notif.object as? String {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    if target == "left" {
                        self.isLeftDetailExpanded.toggle()
                    } else if target == "right" {
                        self.isRightDetailExpanded.toggle()
                    }
                }
                self.scheduleAutoCollapse()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sideReadoutHoverChanged)) { notif in
            if let dict = notif.object as? [String: Bool] {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    if let left = dict["left"], self.isLeftHovering != left {
                        self.isLeftHovering = left
                    }
                    if let right = dict["right"], self.isRightHovering != right {
                        self.isRightHovering = right
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .resetSideReadoutDetails)) { _ in
            self.autoCollapseTask?.cancel()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                self.isLeftDetailExpanded = false
                self.isRightDetailExpanded = false
            }
        }
        .onChange(of: island.state) { newState in
            if newState == .expanded {
                self.autoCollapseTask?.cancel()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.isLeftDetailExpanded = false
                    self.isRightDetailExpanded = false
                }
            }
        }
        .onAppear {
            startActiveServices()
        }
    }

    private func isDisplayAllowed(geom: NotchGeometry) -> Bool {
        return true
    }

    private var isFullScreenHidden: Bool {
        if !hideWingsInFullScreen { return false }
        if let screen = vm.currentScreen {
            return screen.visibleFrame.height == screen.frame.height
        }
        return false
    }

    private func startActiveServices() {
        let needsStats = leftWingMetric == .cpuUsage || leftWingMetric == .cpuTemp || leftWingMetric == .ramUsage || leftWingMetric == .ramDetails || leftWingMetric == .battery || leftWingMetric == .clock
            || rightWingMetric == .cpuUsage || rightWingMetric == .cpuTemp || rightWingMetric == .ramUsage || rightWingMetric == .ramDetails || rightWingMetric == .battery || rightWingMetric == .clock
        if needsStats { statsService.start() }

        let needsNet = leftWingMetric == .netDown || leftWingMetric == .netUp || leftWingMetric == .netDownUp
            || rightWingMetric == .netDown || rightWingMetric == .netUp || rightWingMetric == .netDownUp
        if needsNet {
            speedProvider.start()
            connectionService.start()
        }
    }

    // MARK: - Left Drop
    @ViewBuilder
    private func leftDropView(geom: NotchGeometry, wingW: CGFloat) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            leftDropContent
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .padding(.vertical, 3)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: LeftWingWidthPreferenceKey.self, value: proxy.size.width)
                    }
                )
        }
        .frame(width: wingW, height: vm.effectiveClosedNotchHeight, alignment: .trailing)
        .background(
            LeftNotchDropShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.black.opacity(max(0.20, 1.0 - islandTransparency)), location: 0.0),
                            .init(color: Color.black.opacity(0.92), location: 0.85),
                            .init(color: Color.black, location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    LeftNotchDropShape()
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.white.opacity(0.22), location: 0.0),
                                    .init(color: Color.white.opacity(0.08), location: 0.80),
                                    .init(color: Color.clear, location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 0.75
                        )
                )
        )
        .contentShape(LeftNotchDropShape())
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isLeftHovering = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isLeftDetailExpanded.toggle()
            }
            scheduleAutoCollapse()
        }
    }

    // MARK: - Right Drop
    @ViewBuilder
    private func rightDropView(geom: NotchGeometry, wingW: CGFloat) -> some View {
        HStack(spacing: 0) {
            rightDropContent
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .padding(.vertical, 3)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: RightWingWidthPreferenceKey.self, value: proxy.size.width)
                    }
                )
            Spacer(minLength: 0)
        }
        .frame(width: wingW, height: vm.effectiveClosedNotchHeight, alignment: .leading)
        .background(
            RightNotchDropShape()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color.black, location: 0.0),
                            .init(color: Color.black.opacity(0.92), location: 0.15),
                            .init(color: Color.black.opacity(max(0.20, 1.0 - islandTransparency)), location: 1.0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .overlay(
                    RightNotchDropShape()
                        .stroke(
                            LinearGradient(
                                stops: [
                                    .init(color: Color.clear, location: 0.0),
                                    .init(color: Color.white.opacity(0.08), location: 0.20),
                                    .init(color: Color.white.opacity(0.22), location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 0.75
                        )
                )
        )
        .contentShape(RightNotchDropShape())
        .onHover { hovering in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isRightHovering = hovering
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isRightDetailExpanded.toggle()
            }
            scheduleAutoCollapse()
        }
    }

    // MARK: - Readout Content Helpers
    @ViewBuilder
    private var leftDropContent: some View {
        if let alert = island.activeAlert {
            liveActivityBrief(alert: alert)
        } else {
            wingMetricView(for: leftWingMetric, showDetails: showLeftDetails)
        }
    }

    @ViewBuilder
    private var rightDropContent: some View {
        if let alert = island.activeAlert {
            liveActivityBrief(alert: alert)
        } else {
            wingMetricView(for: rightWingMetric, showDetails: showRightDetails)
        }
    }

    @ViewBuilder
    private func liveActivityBrief(alert: AlertPayload) -> some View {
        HStack(spacing: 4) {
            Image(systemName: alert.iconName ?? "bell.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(alert.iconColor ?? .accentColor)
            if let sub = alert.subtitle {
                Text(sub)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(.white)
                    .fixedSize()
            }
        }
    }

    @ViewBuilder
    private func wingMetricView(for metric: WingMetric, showDetails: Bool) -> some View {
        switch metric {
        case .none:
            EmptyView()

        case .cpuUsage:
            HStack(spacing: 3.5) {
                Image(systemName: "cpu")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(cpuColor(statsService.overallCPU))
                if showDetails {
                    Text("\(Int(statsService.overallCPU))%")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(cpuColor(statsService.overallCPU))
                        .fixedSize()
                }
            }

        case .cpuTemp:
            HStack(spacing: 3.5) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(statsService.thermalStateColor)
                if showDetails {
                    Text(statsService.formattedCPUTemperature)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }

        case .ramUsage:
            HStack(spacing: 3.5) {
                Image(systemName: "memorychip")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.purple)
                if showDetails {
                    Text("\(Int(statsService.memoryPercentage))%")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }

        case .ramDetails:
            HStack(spacing: 3.5) {
                Image(systemName: "memorychip.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.purple)
                if showDetails {
                    Text("\(statsService.formattedMemoryUsed) / \(statsService.formattedMemoryTotal)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }

        case .netDown:
            HStack(spacing: 3.5) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.green)
                if showDetails {
                    Text(speedProvider.formattedDownload)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }

        case .netUp:
            HStack(spacing: 3.5) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.cyan)
                if showDetails {
                    Text(speedProvider.formattedUpload)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }

        case .netDownUp:
            HStack(spacing: 3.5) {
                Image(systemName: "network")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.cyan)
                if showDetails {
                    Text(speedProvider.formattedCombined)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }

        case .battery:
            HStack(spacing: 3.5) {
                Image(systemName: statsService.isBatteryCharging ? "battery.100.bolt" : "battery.100")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(statsService.batteryPercentage <= 20 ? Color.red : Color.green)
                if showDetails {
                    Text("\(statsService.batteryPercentage)%")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }

        case .bluetoothBattery:
            let btDevice = deviceMonitor.activeDevices.values.first(where: { $0.batteryPercentage != nil })
            HStack(spacing: 3.5) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.blue)
                if showDetails {
                    if let pct = btDevice?.batteryPercentage {
                        Text("\(pct)%")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .lineLimit(1)
                            .foregroundStyle(.white)
                            .fixedSize()
                    } else {
                        Text("—")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
            }

        case .volume:
            HStack(spacing: 3.5) {
                Image(systemName: volumeManager.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(volumeManager.isMuted ? Color.red : Color.accentColor)
                if showDetails {
                    Text("\(Int(volumeManager.rawVolume * 100))%")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }

        case .brightness:
            HStack(spacing: 3.5) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.yellow)
                if showDetails {
                    Text("\(Int(brightnessManager.rawBrightness * 100))%")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }

        case .clock:
            HStack(spacing: 3.5) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.85))
                if showDetails {
                    Text(statsService.formattedTime.isEmpty ? "--:--" : statsService.formattedTime)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }

        case .weather:
            let w = AmbientWeatherService.shared
            HStack(spacing: 3.5) {
                Image(systemName: w.condition.iconName)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.orange)
                if showDetails {
                    Text(w.condition.rawValue)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }

        case .mediaPlayback:
            HStack(spacing: 6) {
                Button(action: {
                    MusicManager.shared.previousTrack()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)

                Button(action: {
                    MusicManager.shared.togglePlay()
                }) {
                    Image(systemName: musicManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Button(action: {
                    MusicManager.shared.nextTrack()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 2)

        case .mediaTitle:
            let title = musicManager.songTitle.isEmpty ? "No Media" : musicManager.songTitle
            let artist = musicManager.artistName
            HStack(spacing: 4) {
                Image(systemName: "music.note")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                if showDetails {
                    Text(artist.isEmpty ? title : "\(title) • \(artist)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                        .fixedSize()
                }
            }
        }
    }

    private func cpuColor(_ val: Double) -> Color {
        if val >= 95 {
            return Color(red: 0.95, green: 0.22, blue: 0.22)
        } else if val >= 80 {
            return Color(red: 0.98, green: 0.65, blue: 0.12)
        } else if val >= 50 {
            return Color(red: 0.95, green: 0.82, blue: 0.18)
        } else {
            return Color(red: 0.18, green: 0.85, blue: 0.42)
        }
    }
}
