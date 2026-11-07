# Deployment & Build Guide

## 1. Mac Companion Build
Requirements:
- macOS 14.0+
- Swift 5.9+ / Xcode 15+

Build command:
```bash
cd MacCompanion
swift build -c release
```

Run test suite:
```bash
cd MacCompanion
swift run protocol-test
```

## 2. Android Companion Build
Requirements:
- Android SDK 34+
- JDK 17+ / Gradle 8.5+

Build command:
```bash
cd AndroidCompanion
./gradlew assembleDebug
```

Run test suite:
```bash
cd nectarlink/android
./gradlew testDebugUnitTest --tests "app.maclink.android.touchpad.*"
```

