# Security-Scoped File Shelf & Lazy Permission Companion Specification

This behavioral specification defines LiquidDynamo's Sandbox-safe File Shelf policies, security-scoped bookmark lifecycle, in-process archive and conversion staging, and lazy, Sandbox-honest system permission checks.

---

## 1. Pure Shelf Collection & Filename Policies (`ShelfCore`)

All collection transformations operate over any item conforming to a minimal metadata protocol exposing:
- `identityKey: String` (canonical deduplication key, e.g., resolved file URL path or normalized text/web URL hash)
- `isTemporary: Bool`
- `createdAt: Date`

### 1.1 List Ordering, Deduplication, and Capacity Eviction

Let `defaultMaxItems = 24`.

1. **Inserting a Single Item (`inserting(_ item:, into items:, maxItems:)`)**:
   - Place `item` at index `0` (newest first).
   - Remove any existing item in `items` sharing the same `identityKey` (re-adding an already-staged item moves it to the front instead of creating duplicates or leaving it buried).
   - If `maxItems > 0` and the resulting count exceeds `maxItems`:
     - Keep prefix `0 ..< maxItems`.
     - Return trailing items (`maxItems...`) as `evicted` so the storage layer can delete temporary staged copies and clean up associated bookmarks.
   - If `maxItems <= 0`, treat capacity as unbounded (`evicted = []`).

2. **Inserting a Batch (`inserting(contentsOf newItems:, into items:, maxItems:)`)**:
   - Deduplicate `newItems` internally keeping the latest entry for each `identityKey`, then insert into `items` preserving batch order near the front and accumulating all evicted items across the operation.

3. **Move to Front & Removal**:
   - `moveToFront(identityKey:, in:)`: moves matching item to index `0`; no-op if absent.
   - `removing(identityKey:, from:)`: filters out matching items.

4. **Temporary Item Expiry (`expiredItems(in items:, now:, ttl:)`)**:
   - With default `ttl = 3600` seconds (1 hour):
   - Any item with `isTemporary == true` and `now.timeIntervalSince(item.createdAt) >= ttl` is marked expired so temporary conversions, pasted snippets, and archives are automatically reclaimed without disturbing user-referenced bookmarks.

### 1.2 Filename Sanitization (`sanitizeFilename(_:fallback:)`)

When dropping raw data blobs, text snippets, or URLs without an on-disk path:
1. Trim surrounding whitespace and newlines.
2. Replace path separators (`/`, `\`, `:`) and ASCII control characters with `-`.
3. Reject empty names, `.` / `..`, or strings consisting solely of dots; substitute `fallback` (default `"item.dat"`).
4. Clamp overly long filenames to at most 180 UTF-8 characters while preserving any extension.

---

## 2. App Sandbox Security-Scoped Bookmark & Staging Lifecycle

LiquidDynamo runs with `com.apple.security.app-sandbox = true`, `com.apple.security.files.bookmarks.app-scope = true`, `com.apple.security.files.bookmarks.document-scope = true`, and `com.apple.security.files.user-selected.read-write = true`.

### 2.1 Balanced Security Scope Around All File Operations

Every access to a file referenced outside the app's Sandbox container MUST occur inside a balanced `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` scope:

1. **Bookmark Creation (`Bookmark.init(url:)`)**:
   - Execute `FileManager.fileExists(atPath:)` and `url.bookmarkData(options: .withSecurityScope)` inside `url.accessSecurityScopedResource`.
   - On failure (e.g., transient file promises), gracefully fall back inside the same scope or throw a descriptive error without leaving an unbalanced access reference.

2. **Stale Bookmark Refresh (`Bookmark.resolve()`)**:
   - Resolve with `[.withSecurityScope, .withoutUI]`.
   - If `isStale == true`, refresh bookmark bytes with `url.bookmarkData(options: [.withSecurityScope])` **inside** `url.accessSecurityScopedResource`.
   - Persist refreshed bookmark data when available.

3. **Shelf Metadata Reads (`ShelfItem`)**:
   - `isMissing`, `typeDescription`, `formattedFileSize`, `displayName`, and `icon` MUST acquire security scope via the item's `Bookmark.withAccess` before reading `fileExists`, `resourceValues`, `Data(contentsOf:)`, or `NSWorkspace.shared.icon(forFile:)`.
   - `isMissing` returns `true` only if the bookmark fails to resolve OR `fileExists` returns `false` *while* security scope is active.

### 2.2 Sandbox-Safe Archive Creation & Format Conversion

1. **No Subprocesses for Archiving**:
   - `TemporaryFileStorageService.createZip` MUST NOT spawn `/usr/bin/zip`.
   - **Single item (file or folder)**: resolve its security-scoped URL and invoke `NSFileCoordinator().coordinate(readingItemAt: targetURL, options: [.forUploading])` inside `accessSecurityScopedResource`, copying the coordinated `.zip` artifact into temporary shelf storage (`LiquidDynamo/Temp` or `NSTemporaryDirectory()`).
   - **Multiple items**: create an isolated staging folder `<NSTemporaryDirectory()>/LiquidDynamoArchive-<uuid>/`, copy each item into the staging folder while holding `[URL].accessSecurityScopedResources`, coordinate reading that staging folder with `[.forUploading]` to produce a clean `.zip` archive in-process, copy the result to shelf storage, and delete the staging folder immediately.

2. **Sandbox-Safe Conversion Output**:
   - Conversions (`Image -> PNG/JPEG/PDF`) MUST hold `[URL].accessSecurityScopedResources` while reading inputs.
   - Write converted output files into `FileManager.default.temporaryDirectory.appendingPathComponent("LiquidDynamoConverted/<uuid>", isDirectory: true)` (inside the app's Sandbox container) rather than writing next to source files where only single-file bookmark permission exists.
   - Stage resulting files onto the shelf as temporary `ShelfItem` records using `Bookmark(url:)` + `isTemporary = true`.

3. **Explicit User Selection Grant**:
   - Provide an explicit `+` ("Add Files") action in the File Shelf header launching an `NSOpenPanel` configured for files and folders so users can grant `user-selected.read-write` Sandbox access cleanly via click as well as drag-and-drop.

---

## 3. Lazy, Sandbox-Honest Permission Companion

### 3.1 Strict Lazy Evaluation

- Passive launch or settings-open status evaluation MUST NEVER trigger modal OS prompts (`AXIsProcessTrustedWithOptions` prompt = `true`, `CGRequestScreenCaptureAccess()`, `CGRequestListenEventAccess()`, or `askUserIfNeeded = true`).
- Prompts run **only** in response to an explicit user click on a feature toggle or a "Grant Access" button in Permissions Settings or Onboarding.

### 3.2 Sandbox-Truthful Checks & Status Mapping (`PermissionCompanionPolicy`)

1. **Sandbox Detection**:
   - `isSandboxed` checks whether `APP_SANDBOX_CONTAINER_ID` is present in the process environment.

2. **Full Disk Access (`probeFullDiskAccess()`)**:
   - MUST resolve the real user home directory (`getpwuid(getuid())?.pointee.pw_dir`), never `FileManager.default.homeDirectoryForCurrentUser` (which maps to the app's own Sandbox container and returns false positives).
   - Inside App Sandbox, macOS blocks blanket container-external `~/Library/Safari` enumeration unless explicitly granted by the system; when ungranted inside Sandbox:
     - `probeFullDiskAccess()` returns `false` so storage/dev-cache cleanup selects its honest "Limited Access" fallback instead of assuming Full Disk Access.
     - UI status evaluates via `PermissionCompanionPolicy.fullDiskAccessStatus(isSandboxed:probeGranted:)`: `.allowed` if `probeGranted`, `.notNeeded` if `isSandboxed && !probeGranted`, `.needsPermission` if `!isSandboxed && !probeGranted`.

3. **Music / Media Automation (`checkMusicAutomationStatus()`)**:
   - Target `"com.apple.Music"` (declared in `com.apple.security.temporary-exception.apple-events`), never `"System Events"`.
   - Query TCC silently via `AEDeterminePermissionToAutomateTarget(&desc, typeWildCard, typeWildCard, false)`.
   - Map `OSStatus` via `PermissionCompanionPolicy.automationStatus(for:)`:
     - `0` (`noErr`): `.allowed`
     - `-1743`, `-1744`, `-10004`: `.needsPermission`
     - `-600` (`procNotFound` — Music not running): `.unknown` (do not falsely report `.allowed` when target process is closed)
     - other non-zero errors: `.unknown`

4. **Accessibility Repair (`repairAccessibilityPermission()`)**:
   - Never invoke `/usr/bin/tccutil` synchronously on `@MainActor`, and never spawn `tccutil` at all when `isSandboxed == true`.
   - In App Sandbox: log clear repair guidance ("Toggle LiquidDynamo off and back on in Privacy & Security -> Accessibility"), open Accessibility settings, and re-run the standard prompt if requested.
   - Outside App Sandbox (non-sandboxed builds only): execute `tccutil reset Accessibility <bundleID>` on a detached background task before re-prompting.
