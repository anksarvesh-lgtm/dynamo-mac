# Releasing

How a signed, notarized ILoveNotch reaches GitHub Releases and installed copies. The scripted part
is `make release VERSION=…` ([`scripts/release.sh`](../scripts/release.sh)); publishing is a
deliberate, manual step.

## One-time setup

1. **A Developer ID Application identity.** Only the Account Holder of the Apple Developer team
   can create one. Either:
   - sign in to Xcode with the Account Holder's Apple ID (Xcode › Settings › Accounts), and the
     export uses a cloud-managed Developer ID certificate; or
   - create a Developer ID Application certificate (Xcode › Settings › Accounts › Manage
     Certificates, or developer.apple.com › Certificates) so it's in the login keychain. With a
     local identity the DMG is signed and notarized too, not just the app.
2. **`release.env`.** Copy `release.env.example` and fill in the App Store Connect team API key
   (key path, key ID, issuer ID) and the team ID. It's git-ignored; never commit it or the key.
   The key notarizes; an Admin or Developer role is enough.
3. **Sparkle's signing key.** `.build/sparkle/bin/generate_keys` created an EdDSA key pair in the
   login keychain; its public half is `SUPublicEDKey` in `App/Info.plist`. Back up the private
   half somewhere safe (`generate_keys -x private-key-file` exports it, `-f` imports it on
   another Mac): without it, installed copies can't verify future updates.
4. **`gh`**, signed in with write access to the repository.

## Cutting a release

The release notes are the version's section of [CHANGELOG.md](../CHANGELOG.md). First, on `dev`,
rename **Unreleased** to the new version with today's date (`## [0.3.0] - 2026-10-02`), open a new,
empty **Unreleased** above it, update the compare links at the bottom, and set `MARKETING_VERSION` in
`project.yml` to the new version. CI fails a pull request whose version has no section
(`make changelog`). Ship that to `main` ([CONTRIBUTING.md](../CONTRIBUTING.md#branches)), then, from a
clean, up-to-date `main`:

```bash
make release VERSION=0.3.0          # or 0.3.0-beta.1 for a beta, with a section of its own
```

The notes appear in Sparkle's update prompt (Markdown, which Sparkle 2.9 and later renders) and at
the top of the GitHub release, above the generated list of pull requests.

It checks the notes and the version, runs lint and tests, archives a Release build (universal, with
no source checkout recorded, so it updates through Sparkle), exports it signed with Developer ID and
the hardened runtime, notarizes and staples it, packages the DMG, adds the release to `appcast.xml`
with its EdDSA signature, and drafts a GitHub release with the DMG and `SHA256SUMS`, tagged on the
commit it built. A version with a suffix (`-beta.1`) becomes a pre-release.

The DMG goes on the release twice: as `ILoveNotch-<version>.dmg`, which the appcast and the Homebrew
cask point to, and as `ILoveNotch.dmg`, so
<https://github.com/niyamvora/ILoveNotch/releases/latest/download/ILoveNotch.dmg> always downloads
the newest release. The README and the website link there.

`main` is often checked out by other work in progress, so run the release from a worktree of it:
`git worktree add ../release main`, with `release.env` linked in (`ln -s "$PWD/release.env" ../release/`).

Run it at the Mac, awake and unlocked:

- **Notarization** usually takes minutes, but a team's first submission can take hours (1.0.0's
  took about five). The script waits.
- **Sparkle's key** is read from the login keychain. The first time, macOS asks whether
  `generate_appcast` may use it: enter the Mac's password and click **Always Allow**. If the Mac is
  asleep or locked, the prompt can't show and signing fails with `-25320`. Finish the script's
  last steps by hand:

  ```bash
  tag=v1.0.1
  .build/sparkle/bin/generate_appcast \
    --download-url-prefix "https://github.com/niyamvora/ILoveNotch/releases/download/$tag/" \
    "build/release/$tag/updates"
  cp "build/release/$tag/updates/appcast.xml" appcast.xml
  cd "build/release/$tag" && cp ILoveNotch-*.dmg ILoveNotch.dmg && shasum -a 256 ILoveNotch*.dmg >SHA256SUMS
  gh release create "$tag" ILoveNotch*.dmg SHA256SUMS --draft --title "ILoveNotch ${tag#v}" \
    --notes-file notes.md --generate-notes --target "$(git rev-parse HEAD)"
  ```

Then:

1. Open the draft on GitHub, check the notes, and publish it. It becomes the latest release, which
   the download links follow.
2. Commit the updated `appcast.xml` on `dev` and ship it to `main`. Installed copies read it from
   `main`, so an update is offered only once both the release and the appcast are public.
3. Update the Homebrew cask in [niyamvora/homebrew-tap](https://github.com/niyamvora/homebrew-tap):
   `version` and the DMG's `sha256` (from `SHA256SUMS`) in `Casks/ilovenotch.rb`. The cask sets
   `auto_updates`, so installed copies still update through Sparkle.

If notarization is slow and people are waiting, the signed `ILoveNotch.zip` the script submitted
(`build/release/v<version>/`) can go on the release early. Until Apple accepts it, macOS asks people
to allow it in System Settings › Privacy & Security; afterwards Gatekeeper finds the ticket online,
so the same download opens normally. 1.0.0 went out this way.

## The App Store edition

The `OpenNotch App Store` scheme builds the sandboxed edition (see the
[plan](plan/implementation-plan.md#app-store-edition) for what it leaves out). The app record is
**ILoveNotch** (Apple ID 6815805975, bundle ID `cafe.opennotch.app`, SKU `ilovenotch-mac`), made on
the App Store Connect website because the API can't create app records. 1.0.0 was submitted for
review on 24 September 2026, rejected, and resubmitted as 1.3.0 on 2 October
([listing](app-store/metadata.md)). Two App Review rules came out of it: the edition must not link
to payments outside In-App Purchase (the Sponsor link is `#if !APP_STORE`), and a button before a
permission prompt says Continue, not Allow.

For each version, from a clean `main`:

```bash
make app-store VERSION=1.0.1
```

It archives the edition, signs it for the App Store with cloud-managed certificates through the
team API key in `release.env`, and uploads it; the icon comes from the build. The build appears in
App Store Connect › TestFlight once processed. Then, in App Store Connect or through its API with
the same key:

1. Add the version (Distribution › **+**), fill in What's New, and pick the build.
2. Keep the listing in step with [docs/app-store](app-store/metadata.md), then **Add for Review**
   and **Submit**.

The listing, screenshots, preview, age rating, price, and availability for 1.0.0 went in through
the API. App Privacy ("Data Not Collected") can only be answered on the website, and carries over
to later versions.

**TestFlight:** the "Public" external group has the link
<https://testflight.apple.com/join/6p3zqhCS>. Add each new build to it; the first build of a
version waits for Beta App Review before testers outside the team can install it.

## Checks before publishing

- `spctl --assess --type execute --verbose` on the exported app says "Notarized Developer ID"
  (the script runs it).
- Install from the DMG on a Mac or user account that has never run ILoveNotch: it opens without a
  Gatekeeper warning.
- Update an installed earlier release through **Check for Updates…**.
- Keep the previous DMG: rolling back is installing it over the new one.
