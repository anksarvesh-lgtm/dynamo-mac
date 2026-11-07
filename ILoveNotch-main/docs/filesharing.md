# Plan: Android file sharing over Quick Share (Wi-Fi), Phase 1

> **Status, 2026-09-26:** built on the branch `android-quick-share` (M1–M4, GitHub build). Where it
> differs from the plan below:
>
> - **No swift-protobuf.** The twenty-odd messages are encoded by hand (`QuickShare/Protobuf.swift`
>   and `Frames.swift`, tested against protobuf's own examples), so there's no new dependency.
> - **A QR code for Mac → phone.** Samsung phones never announce themselves on Wi-Fi without a
>   Bluetooth signal macOS can't send, and most others only after it, so the send window shows the
>   QR code Quick Share uses to skip that step. Scanning it is how the S25 Ultra gets found.
> - **The send picker is a window**, like AirDrop's, not a view in the notch, so it stays up while
>   the notch closes and you point the phone at its QR code.
> - **Section 8's suggestions were taken:** receiving is off until turned on, with the 10-minute
>   mode (also under the shelf); files go to `~/Downloads`; the GitHub build first.
> - **Still to do:** M0's check with the real phone, the manual list in [QA](qa.md#hardware-checks).

## 1. Goal

**Mac → Android:** click **Send to Android** on the shelf. Your S25 Ultra appears in a list; you pick it, accept on the phone, and the files arrive.

**Android → Mac:** on the phone, tap Share → Quick Share → your Mac. The notch shows the request with a 4-digit code and Accept / Decline. The files land in Downloads and appear on the shelf.

It works with no app on the phone, over your home Wi-Fi, and with no internet or server involved.

## 2. How Quick Share works over Wi-Fi

Google has published its Quick Share code (the `google/nearby` repository, Apache-2.0), and NearDrop (Unlicense) is a working Mac version written in Swift. Details below come from those projects. The first milestone confirms each one against your real phone.

1. **Finding devices.** Each device announces itself on the local network using Bonjour (the same service discovery AirPrint uses), under the service type `_FC9F5ED42C8A._tcp`. The announcement's name encodes a random 4-character device ID. A small attached record carries the device name and type ("Niyam's MacBook", laptop).
2. **Connecting.** The sender opens a plain network connection to the receiver. Messages are length-prefixed "protobuf" messages, a compact data format Google defines. The first message is a connection request.
3. **Encryption handshake (called UKEY2).**
   - The two sides agree on shared keys using P-256 elliptic-curve key exchange.
   - Everything after that is encrypted with AES-256 and checked with HMAC-SHA256, with message counters to stop replays.
   - Both screens show a 4-digit code derived from the keys, so you can check nobody is in the middle.
4. **Sharing messages**, sent inside the encrypted channel:
   - an introduction listing file names, sizes and types, or text or a link;
   - the receiver's accept or reject;
   - then the file data in numbered chunks, with a "last chunk" flag.
5. **Keep-alive and disconnect** messages.
6. **Wi-Fi Direct / hotspot upgrade:** the phone may offer to switch to a direct Wi-Fi link. The Mac declines, and the transfer stays on your home network.

## 3. What we build, and where

A **new code module `NotchTransfer`**, set up like the existing `NotchUsage` module. This keeps the new networking code and its one dependency out of the rest of the app, and lets it be tested on its own.

```
Sources/NotchTransfer/
  QuickShare/
    Protos/            ← message definitions from google/nearby (Apache-2.0)
    Framing.swift      ← splitting the connection into length-prefixed messages
    EndpointInfo.swift ← building and reading the Bonjour name and device-info record
    UKEY2.swift        ← the key-exchange handshake (P-256 key agreement, key derivation, code)
    SecureChannel.swift← encrypting and signing each message, with counters
    Payloads.swift     ← putting file chunks back together and writing them straight to disk
    Advertiser.swift   ← announcing the Mac and accepting incoming transfers
    Browser.swift      ← finding phones, only while the send menu is open
    InboundSession.swift / OutboundSession.swift ← the step-by-step logic for receiving and sending
  TransferFeature.swift ← app-facing state: nearby phones, active transfers, incoming requests, settings
  TransferViews.swift   ← device picker, incoming request card, progress row
Tests/NotchTransferTests/
```

**Libraries:**

- **swift-protobuf** (Apache-2.0) for the message format. It's the only new dependency and gets listed in THIRD_PARTY_NOTICES. The alternative is hand-writing the roughly 15 message types we need, which avoids the dependency but is more work.
- **Apple built-ins for the rest:** CryptoKit (key exchange, key derivation, HMAC, SHA-256/512), CommonCrypto for AES-CBC (CryptoKit doesn't include it), and Network.framework for networking and Bonjour.

**Changes to existing code:**

- `ShelfFeature` / `ShelfView`: a "Send to Android" button beside AirDrop, in the per-file menu and in the footer. Received files are added with `shelf.add(urls)`.
- `AppDelegate`: create `TransferFeature`, connect its notch pop-ups, and start or stop announcing the Mac from Settings. The same pattern the volume and battery monitors use.
- Notch pop-ups: the existing pop-up type already supports a 0…1 progress bar, so it can show "Receiving 3 files ▓▓▓░ 62%" without changes to the notch code.
- Settings › Shelf gets an **Android** section:
  - **Receive from Android:** Off / While the notch is open / Always, plus a "visible for 10 minutes" mode.
  - **Device name**, defaulting to the Mac's name.
  - **Save received files to**, defaulting to `~/Downloads`.
  - **Add received files to the shelf**, on by default.

**Permissions and project setup:**

- `project.yml` Info.plist keys:
  - `NSLocalNetworkUsageDescription` — macOS 15 and later asks for local network permission.
  - `NSBonjourServices = ["_FC9F5ED42C8A._tcp"]`.
- App Store edition entitlements: `com.apple.security.network.server` and `com.apple.security.network.client`.
- The GitHub build needs no new entitlements. The macOS firewall may still ask once to allow incoming connections.

## 4. Milestones

**M0 — Prove it works with your phone (1–3 days).** Nothing user-facing: a debug-only screen.

- Announce the Mac and receive one photo from the S25 Ultra: log each message, show the code, write the file.
- Exit criterion: the photo arrives intact and the code matches on both screens.
- This also answers the open questions: what the phone's Bonjour record looks like, and whether it offers the direct Wi-Fi upgrade.

**M1 — Receiving (about 3–4 days)**

- The incoming request card in the notch: phone name, file list, code, and Accept / Decline.
- Received files go straight to disk in 512 KB pieces, never whole into memory, with a progress pop-up. Text and links go to the clipboard, and links get an Open button.
- Received files are added to the shelf, with a "3 files from Galaxy S25 Ultra" pop-up.
- Cancelling works from either side. Partial files are cleaned up.

**M2 — Sending (about 3–4 days)**

- Search for phones only while the picker is open, and stop when it closes.
- Pick a phone, see the code, wait for the phone to accept, then send in chunks with progress.
- Handle the phone declining or not answering (60-second timeout), or disappearing mid-send.

**M3 — Settings, polish, both editions (about 2 days)**

- The settings above, and the "visible for 10 minutes" timer.
- Announcing only runs while it's needed, so idle CPU stays near zero.
- A clear message when local network access is denied, with an "Open Settings" button.
- The App Store edition's permissions, and a check that it works inside Apple's sandbox.

**M4 — Hardening and docs (about 2 days)**

- The security items in section 5, and the tests in section 6.
- README, PRIVACY ("uses your local network only, never the internet"), THIRD_PARTY_NOTICES, the parity checklist, and a "Troubleshooting" section.

**Total: roughly 2–3 weeks part-time.** The riskiest part is M0. If it works, everything after it is ordinary app work.

## 5. Security rules

- **Nothing is received without your consent:** no auto-accept.
- **Filenames are cleaned:**
  - no `../` tricks, slashes, or hidden-file dots;
  - long names are cut short;
  - name clashes get " 2", " 3" suffixes.
- **Size and disk checks:** check free space before accepting, and reject a transfer whose data doesn't match the sizes it announced.
- **Strict message checks:**
  - verify every message's signature and counter;
  - drop the connection on any unexpected or oversized message (cap: about 5 MB per message);
  - time out handshakes that stall after about 10 seconds.
- **Only when chosen:** the Mac announces itself only in the mode you pick, and never searches unless the picker is open.
- **Local network only:** nothing goes to the internet.

## 6. Testing

**Automated (these can run in CI):**

- **Key-exchange and encryption tests with fixed keys:** a round-trip, a tampered message rejected, a wrong counter rejected.
- **Device announcement:** encoding and decoding the Bonjour name and device-info record.
- **Message splitting:** a message broken across several network reads, and an oversized message rejected.
- **Loopback:** our sender sends to our own receiver on the same Mac, for 1 file, 100 files, and a 200 MB file. It checks the files match byte-for-byte and that memory stays flat.
- **Filename cleaning:** a table of hostile names.

**Manual, with your S25 Ultra:**

| #   | Test                               | Expected                                             |
| --- | ---------------------------------- | ---------------------------------------------------- |
| 1   | Phone → Mac: 1 photo               | Code matches, arrives, appears on the shelf          |
| 2   | Phone → Mac: 1–2 GB video          | Speed limited by your Wi-Fi; Mac memory stays flat   |
| 3   | Phone → Mac: 100 photos            | All arrive, one progress bar                         |
| 4   | Phone → Mac: a link or text        | Goes to the clipboard, with an Open button for links |
| 5   | Mac → phone: 1 file and many files | Phone shows the request and the files arrive         |
| 6   | Decline on each side               | Clean message, no leftover files                     |
| 7   | Cancel partway, on each side       | Partial files deleted                                |
| 8   | Phone set to Contacts only         | Mac not visible; the app explains why                |
| 9   | 2.4 GHz vs 5 GHz Wi-Fi             | Note the speeds                                      |
| 10  | Mac asleep, lid closed, locked     | Nothing is announced, then it recovers on wake       |
| 11  | App Store build                    | Works inside Apple's sandbox                         |
| 12  | Local network access denied        | Clear message with a fix button                      |

## 7. Known limits (for the README)

- **Same Wi-Fi network only.** Guest, hotel and office networks that isolate devices from each other will block it.
- **Visibility:** the phone must be set to **"Anyone nearby"** (Everyone). "Contacts" and "Your devices" need Google account certificates, which we can't use.
- **Mac → phone:**
  - The phone may only appear while its Quick Share is visible, and possibly only while its screen is on.
  - Android sometimes uses Bluetooth to wake nearby devices first. Adding that is a research item after M2, because macOS limits what Bluetooth announcements an app can send.
- **Unofficial:** the protocol isn't an official Mac API, so a Google update could break it. The code is kept in one module so it can be fixed quickly.
- **No direct Wi-Fi link:** speed depends on your router rather than a phone-to-Mac link.

## 8. What I need from you

1. **Decisions:**
   - Receiving on by default, or off until you turn it on? I suggest off, with the 10-minute visible mode.
   - The save folder: `~/Downloads`, or `~/Downloads/ILoveNotch`?
   - Include it in the App Store edition from the start, or ship in the GitHub build first? I suggest GitHub first, since App Review may question an unofficial protocol.
   - Branch name: `android-quick-share`, a plain name as you prefer.
2. **Testing on your side:** a Mac to build it (`make check`, then run), the S25 Ultra on the same Wi-Fi with Quick Share set to "Anyone nearby", and screenshots or logs when something fails.
3. **Order:** whether to finish the Tasks/Notes pull request (#25) first. It hasn't been compiled yet, so fixing its build is probably the first step.

If you're happy with this, I'll start M0 on `android-quick-share`, commit locally, and only push when you tell me to.
