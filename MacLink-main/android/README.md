# MacLink for Android

Kotlin + Jetpack Compose (Material 3) on top of the shared Rust core,
called through UniFFI (`core/maclink-ffi`).

## Build

Needs the Android SDK (platform 34/35/37, NDK 30.0.16248370), Rust with the
Android targets, and `cargo-ndk`:

```bash
rustup target add aarch64-linux-android x86_64-linux-android
cargo install cargo-ndk
```

Then, from `android/`:

```bash
./gradlew assembleDebug                          # phones (ARM64) + x86_64 emulator
./gradlew assembleDebug -Pmaclink.abis=arm64-v8a # phones only (faster)
./gradlew testDebugUnitTest
```

Gradle builds the core with cargo-ndk (cargo profile `android`: release
optimizations, symbols kept for UniFFI and stripped when packaging) and
generates the Kotlin bindings from the built library.

## Layout

- `core/`: the bridge to the Rust core. `Core` owns the node and folds its
  events into `CoreState` (a pure reducer, unit-tested); `KeystoreKeyProtector`
  encrypts the identity key with a non-exportable Android Keystore key;
  `Ringer` rings on the alarm stream; battery and network monitors feed the
  core.
- `notifications/`: the notification listener that hands notifications to the
  core for mirroring to Mac, and reads replies and actions.
- `clipboard/`: sending and receiving clipboard content between Mac and phone.
- `files/`: high-speed file transfers with progress, pause, and resume.
- `media/`: media controls and player status shared with the Mac.
- `service/ConnectionService`: background foreground service keeping the phone
  reachable over Wi-Fi and holding the multicast lock for local discovery.
- `ui/`: modern Jetpack Compose UI with Material You dynamic wallpaper colors,
  QR pairing, and nearby code comparison.

`maclink://pair?...` links open the app and pair with your Mac.
