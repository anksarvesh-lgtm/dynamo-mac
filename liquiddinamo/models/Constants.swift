//
//  Constants.swift
//  boringNotch
//
//  Created by Richard Kunkli on 2024. 10. 17..
//

import SwiftUI
import Defaults

private let availableDirectories = FileManager
    .default
    .urls(for: .documentDirectory, in: .userDomainMask)
let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let bundleIdentifier = Bundle.main.bundleIdentifier!
let appVersion = "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""))"

let temporaryDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
let spacing: CGFloat = 16

struct CustomVisualizer: Codable, Hashable, Equatable, Defaults.Serializable {
    let UUID: UUID
    var name: String
    var url: URL
    var speed: CGFloat = 1.0
}

enum CalendarSelectionState: Codable, Defaults.Serializable {
    case all
    case selected(Set<String>)
}

enum HideNotchOption: String, Defaults.Serializable {
    case always
    case nowPlayingOnly
    case never
}

// Define notification names at file scope
extension Notification.Name {
    static let mediaControllerChanged = Notification.Name("mediaControllerChanged")
}

// Media controller types for selection in settings
enum MediaControllerType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case nowPlaying = "Now Playing"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case youtubeMusic = "YouTube Music"
    
    var id: String { self.rawValue }
}

// Sneak peek styles for selection in settings
enum SneakPeekStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case standard = "Default"
    case inline = "Inline"
    
    var id: String { self.rawValue }
}

// Action to perform when Option (⌥) is held while pressing media keys
enum OptionKeyAction: String, CaseIterable, Identifiable, Defaults.Serializable {
    case openSettings = "Open System Settings"
    case showHUD = "Show HUD"
    case none = "No Action"

    var id: String { self.rawValue }
}

// Animation style for notch motion
enum AnimationStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case liquidGlassDrop = "Liquid Glass drop"
    case dynamicIsland = "Dynamic Island"
    case simple = "Simple"

    var id: String { self.rawValue }
}

// Side readout selection for left/right ambient drops beside the notch
public enum SideReadoutType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case cpu = "CPU"
    case ram = "RAM"
    case network = "Network Speed"
    case battery = "Battery"
    case temperature = "Temperature"
    case nothing = "Nothing"

    public var id: String { self.rawValue }
}

public enum WingMetric: String, CaseIterable, Codable, Defaults.Serializable, Identifiable {
    case none = "None"
    case cpuUsage = "CPU Usage"
    case cpuTemp = "CPU Temperature"
    case ramUsage = "RAM Usage"
    case ramDetails = "RAM (Used / Total)"
    case netDown = "Download Speed"
    case netUp = "Upload Speed"
    case netDownUp = "Network (Up/Down)"
    case battery = "Mac Battery"
    case bluetoothBattery = "Bluetooth Battery"
    case volume = "Volume"
    case brightness = "Brightness"
    case clock = "Clock"
    case weather = "Weather"
    case mediaPlayback = "Media Controls"
    case mediaTitle = "Now Playing Track"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .netDownUp:
            return "Network Speed (Combined)"
        case .netDown:
            return "Download Speed"
        case .netUp:
            return "Upload Speed"
        case .mediaPlayback:
            return "Media Controls (⏮ ⏯ ⏭)"
        case .mediaTitle:
            return "Now Playing Track"
        case .ramDetails:
            return "RAM (Used / Total)"
        default:
            return rawValue
        }
    }

    public static var selectableCases: [WingMetric] {
        allCases
    }

    public var iconName: String {
        switch self {
        case .none: return "slash.circle"
        case .cpuUsage: return "cpu"
        case .cpuTemp: return "thermometer.medium"
        case .ramUsage: return "memorychip"
        case .ramDetails: return "memorychip.fill"
        case .netDown: return "arrow.down"
        case .netUp: return "arrow.up"
        case .netDownUp: return "network"
        case .battery: return "battery.100"
        case .bluetoothBattery: return "antenna.radiowaves.left.and.right"
        case .volume: return "speaker.wave.2.fill"
        case .brightness: return "sun.max.fill"
        case .clock: return "clock.fill"
        case .weather: return "cloud.sun.fill"
        case .mediaPlayback: return "playpause.fill"
        case .mediaTitle: return "music.note"
        }
    }
}

@MainActor
public func migrateWingMetricsIfNeeded() {
    guard !Defaults[.wingMetricsMigrated] else { return }
    let oldCpu = Defaults[.showCollapsedCPUWing]
    let oldNet = Defaults[.showCollapsedNetworkWing]
    let oldBt = Defaults[.showCollapsedBluetoothWing]

    if oldCpu {
        Defaults[.leftWingMetric] = .cpuUsage
    } else if oldBt {
        Defaults[.leftWingMetric] = .bluetoothBattery
    } else {
        Defaults[.leftWingMetric] = .none
    }

    if oldNet {
        Defaults[.rightWingMetric] = .netDownUp
    } else if oldBt && Defaults[.leftWingMetric] != .bluetoothBattery {
        Defaults[.rightWingMetric] = .bluetoothBattery
    } else {
        Defaults[.rightWingMetric] = .none
    }

    Defaults[.wingMetricsMigrated] = true
}

@MainActor
public func migratePhoneBridgeKeysIfNeeded() {
    guard !Defaults[.migratedPhoneBridgeKeys_v1] else { return }
    let ud = UserDefaults.standard
    let keyMappings = [
        ("filedroidAdbPath", "phonebridgeAdbPath"),
        ("filedroidAutoDetectAdb", "phonebridgeAutoDetectAdb"),
        ("filedroidAutoMountOnConnect", "phonebridgeAutoMountOnConnect"),
        ("filedroidAutoRevealInFinder", "phonebridgeAutoRevealInFinder"),
        ("filedroidDefaultMacFolder", "phonebridgeDefaultMacFolder"),
        ("filedroidTransferConcurrency", "phonebridgeTransferConcurrency"),
        ("filedroidShowHiddenFiles", "phonebridgeShowHiddenFiles"),
        ("filedroidNotifications", "phonebridgeNotifications"),
        ("filedroidBackendType", "phonebridgeBackendType"),
        ("filedroid_custom_adb_path", "phonebridge_custom_adb_path")
    ]
    for (oldKey, newKey) in keyMappings {
        if ud.object(forKey: newKey) == nil, let oldVal = ud.object(forKey: oldKey) {
            ud.set(oldVal, forKey: newKey)
        }
    }
    if let selectedTab = ud.string(forKey: "selectedSettingsSidebarItem"), selectedTab == "FileDroid" {
        ud.set("PhoneBridge", forKey: "selectedSettingsSidebarItem")
    }
    Defaults[.migratedPhoneBridgeKeys_v1] = true
}

extension Defaults.Keys {
    // MARK: General
    static let animationStyle = Key<AnimationStyle>("animationStyle", default: .liquidGlassDrop)
    static let menubarIcon = Key<Bool>("menubarIcon", default: true)
    static let showOnAllDisplays = Key<Bool>("showOnAllDisplays", default: true)
    static let automaticallySwitchDisplay = Key<Bool>("automaticallySwitchDisplay", default: true)
    static let releaseName = Key<String>("releaseName", default: "LiquidDynamo 1.9.3")
    static let setupVersion = Key<Int>("setupVersion", default: 0)
    static let pauseAlertsUntil = Key<Date?>("pauseAlertsUntil", default: nil)
    static let showMedia = Key<Bool>("musicLiveActivityEnabled", default: true)
    static let showLiveActivities = Key<Bool>("showLiveActivities", default: true)
    static let compactMode = Key<Bool>("compactMode", default: false)
    
    // MARK: Behavior
    static let minimumHoverDuration = Key<TimeInterval>("minimumHoverDuration", default: 0.3)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let openNotchOnHover = Key<Bool>("openNotchOnHover", default: true)
    static let openNotchOnDrag = Key<Bool>("openNotchOnDrag", default: true)
    static let extendHoverArea = Key<Bool>("extendHoverArea", default: false)

    // MARK: Dashboard Regions
    static let showDashboardSystemInfo = Key<Bool>("showDashboardSystemInfo", default: true)
    static let showDashboardDropper = Key<Bool>("showDashboardDropper", default: true)
    static let showDashboardClipboard = Key<Bool>("showDashboardClipboard", default: true)
    static let showDashboardDevices = Key<Bool>("showDashboardDevices", default: true)
    static let notchHeightMode = Key<WindowHeightMode>(
        "notchHeightMode",
        default: WindowHeightMode.matchRealNotchSize
    )
    static let nonNotchHeightMode = Key<WindowHeightMode>(
        "nonNotchHeightMode",
        default: WindowHeightMode.matchMenuBar
    )
    static let nonNotchHeight = Key<CGFloat>("nonNotchHeight", default: 32)
    static let notchHeight = Key<CGFloat>("notchHeight", default: 32)
    //static let openLastTabByDefault = Key<Bool>("openLastTabByDefault", default: false)
    static let showOnLockScreen = Key<Bool>("showOnLockScreen", default: false)
    static let hideFromScreenRecording = Key<Bool>("hideFromScreenRecording", default: false)
    
    // MARK: Appearance
    static let showEmojis = Key<Bool>("showEmojis", default: false)
    //static let alwaysShowTabs = Key<Bool>("alwaysShowTabs", default: true)
    static let showMirror = Key<Bool>("showMirror", default: false)
    static let mirrorShape = Key<MirrorShapeEnum>("mirrorShape", default: MirrorShapeEnum.rectangle)
    static let settingsIconInNotch = Key<Bool>("settingsIconInNotch", default: true)
    static let lightingEffect = Key<Bool>("lightingEffect", default: true)
    static let enableShadow = Key<Bool>("enableShadow", default: true)
    static let cornerRadiusScaling = Key<Bool>("cornerRadiusScaling", default: true)

    static let showNotHumanFace = Key<Bool>("showNotHumanFace", default: false)
    static let tileShowLabels = Key<Bool>("tileShowLabels", default: false)
    static let showCalendar = Key<Bool>("showCalendar", default: false)
    static let showStatsTab = Key<Bool>("showStatsTab", default: true)
    static let showBluetoothTab = Key<Bool>("showBluetoothTab", default: true)
    static let showDisplaySoundTab = Key<Bool>("showDisplaySoundTab", default: true)
    static let showCalendarTab = Key<Bool>("showCalendarTab", default: true)
    static let showDevicesTab = Key<Bool>("showDevicesTab", default: true)
    static let showNetworkTab = Key<Bool>("showNetworkTab", default: true)
    static let showCollapsedCPUWing = Key<Bool>("showCollapsedCPUWing", default: true)
    static let showCollapsedBluetoothWing = Key<Bool>("showCollapsedBluetoothWing", default: false)
    static let showCollapsedNetworkWing = Key<Bool>("showCollapsedNetworkWing", default: true)
    static let leftWingMetric = Key<WingMetric>("leftWingMetric", default: .cpuUsage)
    static let rightWingMetric = Key<WingMetric>("rightWingMetric", default: .netDownUp)
    static let wingMetricsMigrated = Key<Bool>("wingMetricsMigrated_v1_9_2", default: false)
    static let enableSideReadouts = Key<Bool>("enableSideReadouts", default: true)
    static let alwaysShowSideReadoutText = Key<Bool>("alwaysShowSideReadoutText", default: true)
    static let leftSideReadout = Key<SideReadoutType>("leftSideReadout", default: .cpu)
    static let rightSideReadout = Key<SideReadoutType>("rightSideReadout", default: .network)
    static let sideReadoutInterval = Key<Double>("sideReadoutInterval", default: 1.0)
    static let wingWidth = Key<CGFloat>("wingWidth", default: 68.0)
    static let autoFitWings = Key<Bool>("autoFitWings", default: true)
    static let hideWingsInFullScreen = Key<Bool>("hideWingsInFullScreen", default: true)
    static let wingsBuiltInDisplayOnly = Key<Bool>("wingsBuiltInDisplayOnly", default: false)
    static let leftWingShowLabel = Key<Bool>("leftWingShowLabel", default: true)
    static let leftWingShowPercentage = Key<Bool>("leftWingShowPercentage", default: true)
    static let leftWingShowMiniGraph = Key<Bool>("leftWingShowMiniGraph", default: true)
    static let rightWingShowIcon = Key<Bool>("rightWingShowIcon", default: true)
    static let rightWingShowTemperature = Key<Bool>("rightWingShowTemperature", default: true)
    static let rightWingShowCondition = Key<Bool>("rightWingShowCondition", default: true)
    static let showWingSeparators = Key<Bool>("showWingSeparators", default: false)
    static let showLayoutGuides = Key<Bool>("showLayoutGuides", default: false)
    static let dockIconStyle = Key<DockIconStyle>("dockIconStyle", default: .threeD)
    
    // MARK: Water Bottom (Deprecated - Pure Apple Glossy Glass Island)
    static let enableWaterBottom = Key<Bool>("enableWaterBottom", default: false)
    static let waterIntensity = Key<Double>("waterIntensity", default: 0.0)
    static let waterSagAmount = Key<Double>("waterSagAmount", default: 0.0)
    static let waterSeedLock = Key<Bool>("waterSeedLock", default: false)
    static let lockedWaterSeed = Key<Double>("lockedWaterSeed", default: 42.0)

    // MARK: Transparency & Liquid Glass
    static let islandTransparency = Key<Double>("islandTransparency", default: 0.50) // 50% transparency with liquid glass 3D effects
    static let enableWindowTransparency = Key<Bool>("enableWindowTransparency", default: true) // Translucent frosted-glass window materials for Settings/Onboarding

    static let enableBluetoothDeviceShowcase = Key<Bool>("enableBluetoothDeviceShowcase", default: true)
    static let enableStorageDeviceShowcase = Key<Bool>("enableStorageDeviceShowcase", default: true)
    static let enableUSBDeviceShowcase = Key<Bool>("enableUSBDeviceShowcase", default: true)
    static let enableDeviceShowcasePopup = Key<Bool>("enableDeviceShowcasePopup", default: true)
    static let deviceModelCacheLimitMB = Key<Int>("deviceModelCacheLimitMB", default: 150)
    static let googleSearchAPIKey = Key<String>("googleSearchAPIKey", default: "")
    static let googleSearchEngineID = Key<String>("googleSearchEngineID", default: "")
    static let monthlyCloudGenerationCap = Key<Int>("monthlyCloudGenerationCap", default: 10)
    static let monthlyCloudGenerationsUsed = Key<Int>("monthlyCloudGenerationsUsed", default: 0)
    static let monthlyCloudGenerationsPeriod = Key<String>("monthlyCloudGenerationsPeriod", default: "")
    static let hideCompletedReminders = Key<Bool>("hideCompletedReminders", default: true)
    static let sliderColor = Key<SliderColorEnum>(
        "sliderUseAlbumArtColor",
        default: SliderColorEnum.white
    )
    static let playerColorTinting = Key<Bool>("playerColorTinting", default: true)
    static let useMusicVisualizer = Key<Bool>("useMusicVisualizer", default: true)
    static let customVisualizers = Key<[CustomVisualizer]>("customVisualizers", default: [])
    static let selectedVisualizer = Key<CustomVisualizer?>("selectedVisualizer", default: nil)
    
    // MARK: Gestures
    static let enableGestures = Key<Bool>("enableGestures", default: true)
    static let closeGestureEnabled = Key<Bool>("closeGestureEnabled", default: true)
    static let gestureSensitivity = Key<CGFloat>("gestureSensitivity", default: 200.0)
    
    // MARK: Media playback
    static let coloredSpectrogram = Key<Bool>("coloredSpectrogram", default: true)
    static let enableSneakPeek = Key<Bool>("enableSneakPeek", default: false)
    static let sneakPeekStyles = Key<SneakPeekStyle>("sneakPeekStyles", default: .standard)
    static let waitInterval = Key<Double>("waitInterval", default: 3)
    static let showShuffleAndRepeat = Key<Bool>("showShuffleAndRepeat", default: false)
    static let enableLyrics = Key<Bool>("enableLyrics", default: false)
    static let musicControlSlots = Key<[MusicControlButton]>(
        "musicControlSlots",
        default: MusicControlButton.defaultLayout
    )
    static let musicControlSlotLimit = Key<Int>(
        "musicControlSlotLimit",
        default: MusicControlButton.defaultLayout.count
    )
    
    // MARK: Battery
    static let showPowerStatusNotifications = Key<Bool>("showPowerStatusNotifications", default: true)
    static let showBatteryIndicator = Key<Bool>("showBatteryIndicator", default: true)
    static let showBatteryPercentage = Key<Bool>("showBatteryPercentage", default: true)
    static let showPowerStatusIcons = Key<Bool>("showPowerStatusIcons", default: true)
    
    // MARK: Bluetooth Battery Alerts
    static let enableLowBatteryAlerts = Key<Bool>("enableLowBatteryAlerts", default: true)
    static let lowBatteryWarningThreshold = Key<Int>("lowBatteryWarningThreshold", default: 15)
    static let enableCriticalBatteryAlert = Key<Bool>("enableCriticalBatteryAlert", default: true)
    static let playLowBatteryAlertSound = Key<Bool>("playLowBatteryAlertSound", default: false)
    static let keepLowBatteryDot = Key<Bool>("keepLowBatteryDot", default: false)
    static let mutedBatteryAlertDeviceIDs = Key<[String]>("mutedBatteryAlertDeviceIDs", default: [])
    
    // MARK: AirPods Settings
    static let enableAirPodsFollowHead = Key<Bool>("enableAirPodsFollowHead", default: false)
    static let showAirPodsNoiseControl = Key<Bool>("showAirPodsNoiseControl", default: true)
    static let showAirPodsAdaptiveLevel = Key<Bool>("showAirPodsAdaptiveLevel", default: true)
    static let showAirPodsConversationAwareness = Key<Bool>("showAirPodsConversationAwareness", default: true)
    static let showAirPodsOneBudANC = Key<Bool>("showAirPodsOneBudANC", default: true)
    static let showAirPodsVolume = Key<Bool>("showAirPodsVolume", default: true)
    
    // MARK: Downloads
    static let enableDownloadListener = Key<Bool>("enableDownloadListener", default: true)
    static let enableSafariDownloads = Key<Bool>("enableSafariDownloads", default: true)
    static let selectedDownloadIndicatorStyle = Key<DownloadIndicatorStyle>("selectedDownloadIndicatorStyle", default: DownloadIndicatorStyle.progress)
    static let selectedDownloadIconStyle = Key<DownloadIconStyle>("selectedDownloadIconStyle", default: DownloadIconStyle.onlyAppIcon)
    
    // MARK: OSD / HUD
    static let showNotchOSD = Key<Bool>("showNotchOSD", default: true)
    static let hideSystemOSD = Key<Bool>("hideSystemOSD", default: false)
    static let hudReplacement = Key<Bool>("hudReplacement", default: false)
    static let inlineHUD = Key<Bool>("inlineHUD", default: false)
    static let enableGradient = Key<Bool>("enableGradient", default: false)
    static let systemEventIndicatorShadow = Key<Bool>("systemEventIndicatorShadow", default: false)
    static let systemEventIndicatorUseAccent = Key<Bool>("systemEventIndicatorUseAccent", default: false)
    static let showOpenNotchHUD = Key<Bool>("showOpenNotchHUD", default: true)
    static let showOpenNotchHUDPercentage = Key<Bool>("showOpenNotchHUDPercentage", default: true)
    static let showClosedNotchHUDPercentage = Key<Bool>("showClosedNotchHUDPercentage", default: false)
    // Option key modifier behaviour for media keys
    static let optionKeyAction = Key<OptionKeyAction>("optionKeyAction", default: OptionKeyAction.openSettings)
    
    // MARK: Shelf
    static let liquidShelf = Key<Bool>("liquidShelf", default: true)
    static let openShelfByDefault = Key<Bool>("openShelfByDefault", default: true)
    static let shelfTapToOpen = Key<Bool>("shelfTapToOpen", default: true)
    static let quickShareProvider = Key<String>("quickShareProvider", default: QuickShareProvider.defaultProvider.id)
    static let copyOnDrag = Key<Bool>("copyOnDrag", default: false)
    static let autoRemoveShelfItems = Key<Bool>("autoRemoveShelfItems", default: false)
    static let expandedDragDetection = Key<Bool>("expandedDragDetection", default: true)
    
    // MARK: Calendar
    static let calendarSelectionState = Key<CalendarSelectionState>("calendarSelectionState", default: .all)
    static let hideAllDayEvents = Key<Bool>("hideAllDayEvents", default: false)
    static let showFullEventTitles = Key<Bool>("showFullEventTitles", default: false)
    static let autoScrollToNextEvent = Key<Bool>("autoScrollToNextEvent", default: true)
    
    // MARK: Fullscreen Media Detection
    static let hideNotchOption = Key<HideNotchOption>("hideNotchOption", default: .nowPlayingOnly)
    
    // MARK: Media Controller
    static let mediaController = Key<MediaControllerType>("mediaController", default: defaultMediaController)
    
    // MARK: Advanced Settings
    static let useCustomAccentColor = Key<Bool>("useCustomAccentColor", default: false)
    static let customAccentColorData = Key<Data?>("customAccentColorData", default: nil)
    // Show or hide the title bar
    static let hideTitleBar = Key<Bool>("hideTitleBar", default: true)
    
    // Helper to determine the default media controller based on NowPlaying deprecation status
    static var defaultMediaController: MediaControllerType {
        if MusicManager.shared.isNowPlayingDeprecated {
            return .appleMusic
        } else {
            return .nowPlaying
        }
    }

    static let didClearLegacyURLCacheV1 = Key<Bool>("didClearLegacyURLCache_v1", default: false)

    // MARK: Control Center Redesign & Appearance
    static let selectedLiquidTheme = Key<LiquidTheme>("selectedLiquidTheme", default: .liquidGlass)
    static let islandBlurAmount = Key<Double>("islandBlurAmount", default: 24.0)
    static let islandReflectionStrength = Key<Double>("islandReflectionStrength", default: 0.65)
    static let islandAnimationSpeed = Key<Double>("islandAnimationSpeed", default: 1.0)
    static let islandCornerRadius = Key<Double>("islandCornerRadius", default: 22.0)

    // MARK: Hydration Reminder Module
    static let hydrationEnabled = Key<Bool>("hydrationEnabled", default: true)
    static let hydrationIntervalMinutes = Key<Int>("hydrationIntervalMinutes", default: 45)
    static let hydrationSoundEnabled = Key<Bool>("hydrationSoundEnabled", default: true)
    static let hydrationAnimationEnabled = Key<Bool>("hydrationAnimationEnabled", default: true)
    static let hydrationCharacterStyle = Key<String>("hydrationCharacterStyle", default: "Hydro")

    // MARK: Privacy Indicators
    static let privacyIndicatorsEnabled = Key<Bool>("privacyIndicatorsEnabled", default: true)
    static let cameraNotchGlowEnabled = Key<Bool>("cameraNotchGlowEnabled", default: true)
    static let micNotchGlowEnabled = Key<Bool>("micNotchGlowEnabled", default: true)

    // MARK: Storage Cleaner
    static let enableStorageCleanerModule = Key<Bool>("enableStorageCleanerModule", default: true)
    static let storageCleanerStartupScan = Key<Bool>("storageCleanerStartupScan", default: true)

    // MARK: Phone Bridge (ADB & MTP)
    static let phonebridgeAdbPath = Key<String>("phonebridgeAdbPath", default: "")
    static let phonebridgeAutoDetectAdb = Key<Bool>("phonebridgeAutoDetectAdb", default: true)
    static let phonebridgeAutoMountOnConnect = Key<Bool>("phonebridgeAutoMountOnConnect", default: true)
    static let phonebridgeAutoRevealInFinder = Key<Bool>("phonebridgeAutoRevealInFinder", default: false)
    static let phonebridgeDefaultMacFolder = Key<String>("phonebridgeDefaultMacFolder", default: (FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? (NSHomeDirectory() + "/Downloads")) + "/Android")
    static let phonebridgeTransferConcurrency = Key<Int>("phonebridgeTransferConcurrency", default: 2)
    static let phonebridgeShowHiddenFiles = Key<Bool>("phonebridgeShowHiddenFiles", default: false)
    static let phonebridgeNotifications = Key<Bool>("phonebridgeNotifications", default: true)
    static let phonebridgeBackendType = Key<String>("phonebridgeBackendType", default: "auto")
    static let migratedPhoneBridgeKeys_v1 = Key<Bool>("migratedPhoneBridgeKeys_v1", default: false)

    // Backward-compatibility aliases for filedroid*
    static var filedroidAdbPath: Key<String> { phonebridgeAdbPath }
    static var filedroidAutoDetectAdb: Key<Bool> { phonebridgeAutoDetectAdb }
    static var filedroidAutoMountOnConnect: Key<Bool> { phonebridgeAutoMountOnConnect }
    static var filedroidAutoRevealInFinder: Key<Bool> { phonebridgeAutoRevealInFinder }
    static var filedroidDefaultMacFolder: Key<String> { phonebridgeDefaultMacFolder }
    static var filedroidTransferConcurrency: Key<Int> { phonebridgeTransferConcurrency }
    static var filedroidShowHiddenFiles: Key<Bool> { phonebridgeShowHiddenFiles }
    static var filedroidNotifications: Key<Bool> { phonebridgeNotifications }
    static var filedroidBackendType: Key<String> { phonebridgeBackendType }

    // MARK: Android File Manager
    static let androidFilesAdbPath = Key<String>("android_files_custom_adb_path", default: "")
    static let androidFilesDefaultDownloadFolder = Key<String>("android_files_default_download_folder", default: "")
    static let androidFilesThumbnailCacheSizeMB = Key<Int>("android_files_thumbnail_cache_size_mb", default: 200)
    static let androidFilesStopAdbOnQuit = Key<Bool>("android_files_stop_adb_on_quit", default: false)

    // MARK: Powerload Multi-Network Downloader
    static let powerloadDefaultFolder = Key<String>("powerloadDefaultFolder", default: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? (NSHomeDirectory() + "/Downloads"))
    static let powerloadChunkSizeMB = Key<Int>("powerloadChunkSizeMB", default: 8)
    static let powerloadMaxConnectionsPerFile = Key<Int>("powerloadMaxConnectionsPerFile", default: 8)
    static let powerloadMaxParallelDownloads = Key<Int>("powerloadMaxParallelDownloads", default: 3)
    static let powerloadBandwidthLimitMbps = Key<Double>("powerloadBandwidthLimitMbps", default: 0.0)
    static let powerloadClipboardAutoDetect = Key<Bool>("powerloadClipboardAutoDetect", default: true)
    static let powerloadCompletionAlert = Key<Bool>("powerloadCompletionAlert", default: true)
    static let powerloadTorrentAutoStart = Key<Bool>("powerloadTorrentAutoStart", default: true)

    // MARK: Privacy & Security Network Opt-Ins
    static let clipboardShieldDuringScreenRecording = Key<Bool>("clipboardShieldDuringScreenRecording", default: true)
    static let autoCheckUpdates = Key<Bool>("autoCheckUpdates", default: true)
    static let autoDownloadAndInstallUpdates = Key<Bool>("autoDownloadAndInstallUpdates", default: true)
    static let privacyPublicIPLookup = Key<Bool>("privacyPublicIPLookup", default: false)
    static let privacyMeshyUploadEnabled = Key<Bool>("privacyMeshyUploadEnabled", default: false)

    // MARK: Plexo Turbo Downloader (Backward Compatibility)
    static let plexoDefaultFolder = powerloadDefaultFolder
    static let plexoChunkSizeMB = powerloadChunkSizeMB
    static let plexoMaxConnectionsPerFile = powerloadMaxConnectionsPerFile
    static let plexoMaxParallelDownloads = powerloadMaxParallelDownloads
    static let plexoBandwidthLimitMbps = powerloadBandwidthLimitMbps
    static let plexoClipboardAutoDetect = powerloadClipboardAutoDetect
    static let plexoCompletionAlert = powerloadCompletionAlert
    static let plexoTorrentAutoStart = powerloadTorrentAutoStart

    // MARK: Watcher AI Agent Monitor
    static let enableWatcherIntegration = Key<Bool>("enableWatcherIntegration", default: false)
    static let watcherAutoApproveReads = Key<Bool>("watcherAutoApproveReads", default: false)
    static let watcherNotificationOnFinished = Key<Bool>("watcherNotificationOnFinished", default: true)

    // MARK: NetMerge Multi-Network Bonding
    static let netMergeEnabled = Key<Bool>("netMergeEnabled", default: false)
    static let netMergeAutoStart = Key<Bool>("netMergeAutoStart", default: false)
    static let netMergeSocksPort = Key<Int>("netMergeSocksPort", default: 10888)
    static let netMergeIPv6Mode = Key<String>("netMergeIPv6Mode", default: "auto")
    static let netMergeShowNotchWidget = Key<Bool>("netMergeShowNotchWidget", default: true)
    static let powerloadUseNetMergeEngine = Key<Bool>("powerloadUseNetMergeEngine", default: true)
}

public enum LiquidTheme: String, CaseIterable, Defaults.Serializable {
    case liquidGlass = "Liquid Glass"
    case liquidDark = "Liquid Dark"
    case ocean = "Ocean"
    case aurora = "Aurora"
    case midnight = "Midnight"
    case crystal = "Crystal"
}
