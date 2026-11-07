# Files service (protocol v0)

> Status: **draft.** Builds on [protocol v0](v0.md); breaking changes are
> allowed until v1. License: CC BY 4.0.

Sends files and folders between paired devices, in either direction, with
progress, cancellation and resuming after a dropped connection.

## 1. Capability

| ID | Offered by | Meaning |
|---|---|---|
| `files.transfer` | both | Sends and receives files |

## 2. A transfer

Each transfer runs on its own bidirectional stream (v0 §4), so it never
holds up the control stream. The sender opens it and writes the stream
header, then an offer:

```
t = "stream"        b = { svc: "files", op: "send", v: 1 }
t = "files.offer"   b = {
  id:    text,             // Transfer ID: 16 to 64 bytes of [A-Za-z0-9_-], the same on every retry
  files: [ {
    name:    text,         // The file's name
    size:    uint,
    ? folder: text,        // Only for files in a sent folder (see below)
    ? blake3: text,        // Optional 64-character hex BLAKE3 digest of the full file
  } ],                     // 1 to 5,000 files, in order
  ? open_on_arrival: bool, // True when handing off a single document to open on arrival
}
```

`name` is a file name only (no path), 1 to 255 bytes, without `/`, `\`, NUL
or control characters, and not `.` or `..`. When `blake3` is present, it is
64 ASCII hexadecimal characters representing the 256-bit BLAKE3 digest of
the complete file.

**Folders.** A sent folder is its files, each with `folder`: where the file
is, as names joined by `/`, starting with the sent folder's own (`Trip`,
`Trip/Day 1`). Each name follows the rules for `name`; there are at most 32
of them, in at most 1,024 bytes. A folder's files are listed together.
Empty folders aren't sent.

**Voice recordings.** When a phone sends a voice recording
([`recorder.md`](recorder.md)), `files.offer` sets `"recording": true` on a
single-file offer (without `folder`) and may include `"markers"`: up to 256
entries `{ at_ms: uint, label?: text }`.

**Handoff documents.** When a sender hands off a single safe document (`pdf`,
`txt`, `md`, `rtf`, `csv`, `json`, `html`, `epub`, or Office/OpenDocument files)
to open immediately on the other device, `files.offer` sets
`"open_on_arrival": true` on a single-file offer (without `folder` or
`recording`). Receivers **MUST** check the received file's extension against a
safe document allowlist and never automatically execute binaries or scripts.

Receivers **MUST** reject an offer that breaks these rules with
`BAD_MESSAGE`, and still pick their own safe names for writing (see §4). The
whole offer is one frame (v0 §3), which limits how many files with long
names fit in it.

The receiver answers on the same stream:

```
t = "files.accept"  b = { have: [uint] }   // bytes already received, per file
```

or `error` (`DENIED`: the user turned files or recordings off for this
device; `UNSUPPORTED`: a recording was offered to a device without
`recorder`; `BUSY`: not enough space or too many transfers) and closes the
stream.

The sender then writes the files' bytes, raw and back to back: for each
file, from `have[i]` to its `size`. A file whose `have` equals its `size`
contributes nothing. The sender then finishes its side of the stream.

When the receiver has every byte, it verifies each file's `blake3` digest (if
provided, hashing any resumed `.part` prefix together with the newly received
bytes). If any file's digest does not match, the receiver keeps the partial
directory on disk (so a retry can inspect or overwrite the corrupted `.part`
file), answers with `error` (`BAD_MESSAGE`, `"blake3 integrity check failed"`),
and closes the stream without moving files into the destination folder.
Otherwise, the receiver stores the files and answers:

```
t = "files.done"
```

The transfer has succeeded once the sender reads `files.done`. Anything
else (a reset, a closed connection, a missing `done`) means it didn't.

## 3. Cancelling, pausing and resuming

- Either side cancels an active stream by resetting it (QUIC `RESET_STREAM`
  or `STOP_SENDING`, application code 10, "cancelled"). While a transfer is
  paused (no active stream), either side cancels by sending a control message
  `t = "files.cancel", b = { id: text }` so the receiver deletes its staged
  `.part` directory.
- Either side manually pauses an active transfer by resetting the stream with
  application code 11 (`files::PAUSED`). Both sides keep the transfer in the
  `Paused` state and the receiver preserves all `.part` files on disk.
- Either side resumes a paused transfer: the sender re-offers the transfer with
  the same `id` on a new stream; if the receiver initiates resume, it sends a
  control message `t = "files.resume", b = { id: text }` prompting the sender
  to immediately re-offer from the saved byte offset.
- A transfer interrupted any other way (the connection dropped) is resumed
  by offering it again with the **same `id`** when the devices reconnect.
  The receiver keeps partly received files for a transfer for at least an
  hour and reports their length in `have` (if a `.part` file's length already
  equals `size` and `blake3` is present, the receiver verifies its digest
  before reporting `have[i] = size`, reporting `0` on mismatch so the file is
  re-sent). A sender **MUST** use a new `id` if any file changed in between.

## 4. Receiving safely

- Files are written to a private folder first and moved to where the user
  finds them (the Downloads folder) only once complete.
- A name that already exists there gets a number: `photo (2).jpg`. A sent
  folder gets a new folder of its own the same way (`Trip (2)`); nothing
  is ever added to a folder that was already there.
- Names the receiving system can't store (on Windows: `CON`, `NUL`, `?`,
  trailing dots…) are changed to ones it can.
- A device accepts files only from paired devices with the `files` toggle
  on. A receiver that runs out of space resets the stream.
- Implementations **MUST NOT** log file names (v0 §11).
