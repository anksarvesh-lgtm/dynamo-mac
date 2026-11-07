# Updates

ILoveNotch has two ways to stay current: builds made from a local checkout rebuild themselves
from it, and public releases update through Sparkle.

## Builds from a checkout (today)

`make run` and `make install` record the checkout and commit a build came from in its
`Info.plist` (`OpenNotchSourceDirectory`, `OpenNotchCommit`). When that checkout is still on
the Mac, the menu bar item shows the running version and commit, for example
`ILoveNotch 0.2.0 (8b4da5e)`, with a `+` when the checkout had uncommitted changes. Beside it is
**Update ILoveNotch**, which is also in **Settings › About** and available as `make update`.

**Update ILoveNotch** runs [`scripts/update.sh`](../scripts/update.sh), which:

1. fast-forwards `main` from GitHub when the checkout is on `main` with no local changes (any
   other branch, or uncommitted work, is built as it is and never touched);
2. builds a Release app, replaces `/Applications/ILoveNotch.app`, and relaunches it.

The new build quits the running one when it takes its place. If the pull or the build fails,
the running app stays put and the menu offers **Update Failed: Show Log**. The log is at
`~/Library/Logs/OpenNotch/update.log`.

### Permissions across rebuilds

macOS ties Calendar, Reminders, and folder access to an app's code signature. An ad-hoc
signature changes with every build, so each rebuild would ask again. When the keychain has an
**Apple Development** certificate (Xcode › Settings › Accounts › Manage Certificates), `make`
signs with it instead. The app then keeps the same identity across rebuilds, and access
granted once stays granted. Pass `SIGNING_IDENTITY=` to force ad-hoc signing, as CI does by
having no certificate.

## Public releases

Downloaded copies have no checkout, so they update through [Sparkle 2](https://sparkle-project.org)
(MIT):

| Piece | How |
|-------|-----|
| In-app updates | `SPUStandardUpdaterController`, behind **Check for Updates…** in the menu bar item and Settings › About |
| Feed | `appcast.xml` on `main` (`SUFeedURL`), updated by each release |
| Trust | Every update's DMG is signed with an EdDSA (ed25519) key; its public half is `SUPublicEDKey` in `App/Info.plist`, and Sparkle also checks the Developer ID signature |
| Distribution | A signed, notarized DMG on [GitHub Releases](https://github.com/niyamvora/ILoveNotch/releases/latest), and `brew install --cask niyamvora/tap/ilovenotch` from [niyamvora/homebrew-tap](https://github.com/niyamvora/homebrew-tap). The cask sets `auto_updates`, so Homebrew leaves updating to Sparkle |
| Automatic checks | Off until the user agrees: Sparkle asks on the second launch |

Release builds record no source checkout (`OPENNOTCH_SOURCE` is empty), so they use Sparkle;
builds from a checkout keep **Update ILoveNotch**. [Releasing](releasing.md) covers cutting a
release with `make release`, which signs with Developer ID, notarizes, builds the DMG, updates the
appcast, and drafts the GitHub release.

Releases are cut on a maintainer's Mac rather than in CI, so the Developer ID identity, the
account-wide App Store Connect key, and Sparkle's private key never leave it. A CI release
workflow can follow once there's a key scoped to this app.
