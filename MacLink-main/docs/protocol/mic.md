# Phone as microphone (v1)

> Status: **draft.** Builds on [protocol v0](v0.md); breaking changes are
> allowed until v1. License: CC BY 4.0.

Uses a paired phone's microphone on a PC. Control messages travel on the
session's control stream ([protocol v0](v0.md) §4); the sound travels on a
dedicated bidirectional QUIC stream (`{ svc: "mic", op: "pcm", v: 1 }`).

This is the streaming half of GitHub #7. The PC plays the sound into an
output device; played into a virtual audio cable, the cable's other end is
a microphone every app can pick. A virtual microphone of MacLink's own
needs an audio driver and is a separate step.

## 1. Capabilities and toggle

| Capability | Offered by | Meaning |
|---|---|---|
| `mic.stream` | Phone | Streams its microphone when its user agrees (it asks for the microphone permission then, if needed) |
| `mic.listen` | PC | Takes a phone's microphone stream |

Both devices have a `mic` per-device toggle (on by default). When it's off
for a peer, `mic.start` is refused with `DENIED`, incoming `mic` streams are
reset with code `13`, and a running stream with that peer stops.

A phone **never** turns its microphone on silently: it streams only after
its user taps Start on the PC's request, or turns it on for a PC on the
phone itself (as with the [webcam](webcam.md) §2), and shows an ongoing
notification with a **Stop** button the whole time. A PC takes a stream
it didn't ask for the same way, while `mic` is on for that phone. Android only lets the microphone
start from the foreground, which the tap provides.

## 2. Starting and stopping

```
t = "mic.start"  id = n            // PC to phone
t = "ok"         re = n
t = "mic.stop"   [id = n]          // either way
t = "ok"         re = n            // when it had an id
```

**`mic.start`** asks the phone to ask its user. The phone answers `ok` once
it has asked (not when the user agrees): the stream follows if the user
taps Start. Errors: `DENIED` when the microphone is off for the PC,
`UNSUPPORTED` without `mic.stream`.

**`mic.stop`** ends it: from the PC, the phone stops recording; from the
phone (its user tapped Stop), the PC stops listening. Ending the stream
itself (either side) means the same. A phone whose user declines the
request (Not now, or dismissing it) sends `mic.stop` too, before any
sound, so the PC stops waiting.

## 3. The sound stream

The phone opens a bidirectional stream with the header
`{ svc: "mic", op: "pcm", v: 1 }`, then writes the framed packets of the
[webcam stream](webcam.md) §3:

| `kind` | Name | Payload |
|---|---|---|
| `0` | `Config` | CBOR `{ codec: "pcm_s16le", rate: uint, channels: uint }` (as mirroring's sound, [mirror.md](mirror.md) §5): first, and again if the format changes |
| `1` | `Frame` | 16-bit little-endian PCM in that format, interleaved |

Phones send 48 kHz mono, 10 ms a packet, recorded for voice calls (echo
cancellation and noise suppression where the phone has them). The PC keeps
a short jitter buffer (about 40 ms) and drops the oldest sound rather than
fall behind. The PC writes nothing; it stops reading to end the stream.
