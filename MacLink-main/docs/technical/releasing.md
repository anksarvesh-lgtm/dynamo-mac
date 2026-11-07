# Releasing

How a version of MacLink gets from `main` to people's devices, and how the
apps update themselves afterwards.

## What a release is

A GitHub release with four files:

| File | Built by |
|---|---|
| `MacLink-<version>-x64-setup.exe` | The `windows` job: `scripts/package.ps1`, then `scripts/smoke-installer.ps1` installs and uninstalls it |
| `MacLink-<version>-arm64-setup.exe` | The `windows-arm64` job: cross-compiled and packaged via `scripts/package.ps1 -Arch arm64` |
| `MacLink-<version>-android.apk` | The `android` job: a release build for 64-bit and 32-bit ARM, signed with the release key and checked with `apksigner verify` |
| `SHA256SUMS.txt` | The `publish` job, over all installers and APKs |

Each app's updater needs its own file and `SHA256SUMS.txt`: it only
accepts an installer that `SHA256SUMS.txt` lists with a matching hash.
Each Windows updater picks the installer for its own architecture.

## Steps

1. **Version.** `Cargo.toml` (`[workspace.package] version`) is the only
   place it's set: the Windows app, the installer and the Android app
   (`versionName`, and `versionCode` derived from it) all read it. Use
   `MAJOR.MINOR.PATCH`; a pre-release such as `0.2.0-beta.1` is allowed, and
   `[workspace.metadata.release] name` gives the release a name. The
   README's download table links straight to the files, so change the
   version in its two links too.
2. **Checks.** `./scripts/check.ps1 -Android` locally, and a green CI run on
   the commit to release.
3. **Tag and push.** `git tag v<version>` on that commit and push the tag.
   The `Release` workflow refuses a tag that doesn't match `Cargo.toml`.
4. **Review the draft.** The workflow creates a draft release with generated
   notes. Edit the notes (what's new, anything users must do), check the
   four files are there, then **Publish**. Installed copies see it within a
   day: updaters skip drafts and pre-releases.

## Signing

**Android.** Release builds are signed with the key in the
`ANDROID_KEYSTORE` (base64 of the `.jks`) and `ANDROID_KEYSTORE_PASSWORD`
repository secrets; the key's alias is `maclink`. Android only installs an
update signed with the same key as the installed app, so:

- Keep an offline backup of the keystore and its password. If the key is
  lost, no existing install can ever be updated again; everyone would have to
  uninstall and reinstall.
- Builds signed with the debug key (local `assembleRelease` without
  `MACLINK_KEYSTORE`) can't update to or from official releases.
- To sign locally: set `MACLINK_KEYSTORE` to the `.jks` path and
  `MACLINK_KEYSTORE_PASSWORD`, then `./gradlew assembleRelease`.

**Windows.** The installer and the app aren't Authenticode-signed yet, so
SmartScreen warns on first download until the files build reputation. Options
for open-source projects: [SignPath Foundation](https://signpath.org) (free
certificates for qualifying projects, signing in CI) or Azure Trusted
Signing. Either plugs in after `package.ps1` builds the installer, before
`SHA256SUMS.txt` is written.

## How the apps update

- **Windows** (`desktop/app/src/updater.rs`): checks the latest release 30
  seconds after start and daily. With **Install updates automatically** on,
  it waits until nobody has used the PC for 10 minutes and nothing is in
  progress, then starts the **MacLink Update** task that the installer
  registers (`desktop/installer/update-task.ps1`). The task runs as SYSTEM,
  downloads and checks the installer itself, and runs it silently; a hidden
  relauncher reopens the app afterwards. The task logs to `update.log` in the
  install folder. Details and the security reasoning:
  [security model](security-model.md#automatic-updates-and-release-verification).
- **Android** (`update/AppUpdater.kt`): checks daily from the connection
  service and when the app opens, and installs through `PackageInstaller`.
  Android 12 and later skip the confirmation once MacLink installed the
  running version itself; the first update after a manual install asks once.

## Testing an update before publishing

Updaters only look at the latest published release, so test with two
versions on a test PC and phone: install version N from its draft's files,
publish N+1, and check that both apps update by themselves (`update.log` on
the PC; `adb logcat -s AppUpdater` on the phone).
