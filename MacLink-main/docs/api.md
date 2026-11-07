# MacLink Local Authenticated Automation API (`docs/api.md`)

MacLink for Windows includes an opt-in, loopback-only HTTP/JSON API (`127.0.0.1:<port>`, default port `53320`) designed for local desktop automation tools:

- **PowerToys Command Palette / PowerToys Run** (`tools/powertoys-extension`)
- **AutoHotkey / Raycast for Windows / Flow Launcher**
- **PowerShell & CLI scripts**

---

## 1. Enabling the API & Discovering the Token

The Local API is **off by default**. Enable it in **Settings → Local automation API** (or set `"localApiEnabled": true` in `%LOCALAPPDATA%\MacLink\desktop-settings.json`).

When enabled, MacLink binds strictly to `127.0.0.1:<localApiPort>` (default `53320`) and writes `<data-dir>\api-token.json` (`%LOCALAPPDATA%\MacLink\api-token.json`):

```json
{
  "port": 53320,
  "token": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
}
```

When disabled, the listener stops immediately and `api-token.json` is removed.

---

## 2. Security Model

1. **Loopback-only binding**: The server binds to `127.0.0.1` and is never exposed to LAN interfaces.
2. **256-bit Bearer Token**: Every request must include:
   ```http
   Authorization: Bearer <64-hex-char-token>
   ```
   Tokens are compared in constant time. Missing or invalid tokens receive `401 Unauthorized` (`{"ok":false,"error":"unauthorized"}`).
3. **Browser Cross-Origin Protection**: Any HTTP request containing an `Origin` header (automatically attached by web browsers on cross-origin `fetch` / `XMLHttpRequest` calls) is rejected before routing with `403 Forbidden` (`{"ok":false,"error":"forbidden"}`).

---

## 3. Endpoints

### `GET /v1/devices`

Lists paired devices with connection state and battery status.

**Response (`200 OK`)**:
```json
{
  "ok": true,
  "devices": [
    {
      "id": "a1b2c3...",
      "name": "Pixel 9 Pro",
      "platform": "android",
      "online": true,
      "link": "lan",
      "battery": {
        "level": 84,
        "charging": false
      }
    }
  ]
}
```

---

### `POST /v1/send`

Sends files, a URL, or text to a paired phone (defaults to the first online or paired phone when `device` is omitted).

**Request Body**:
```json
{
  "device": "Pixel 9 Pro",
  "paths": ["C:\\Users\\Alice\\Pictures\\diagram.png"],
  "url": "https://maclink.app",
  "text": "Meeting notes"
}
```

**Response (`200 OK`)**:
```json
{ "ok": true }
```

---

### `GET /v1/clipboard`

Returns the current PC clipboard text and up to 20 recent clipboard history entries.

**Response (`200 OK`)**:
```json
{
  "ok": true,
  "text": "Current clipboard text",
  "history": [
    {
      "id": "clip-1",
      "preview": "Current clipboard text",
      "mime": "text/plain",
      "sourceDevice": "local",
      "sourceName": "This PC",
      "timestampMs": 1730000000000,
      "pinned": false
    }
  ]
}
```

---

### `POST /v1/clipboard`

Copies `text` to the PC clipboard and pushes it to the target phone.

**Request Body**:
```json
{
  "text": "Copied from script",
  "device": "Pixel 9 Pro"
}
```

**Response (`200 OK`)**:
```json
{ "ok": true }
```

---

### `POST /v1/notify`

Sends a task/alert notification to the paired phone.

**Request Body**:
```json
{
  "title": "Build completed",
  "body": "cargo test finished in 14s",
  "device": "Pixel 9 Pro"
}
```

**Response (`200 OK`)**:
```json
{ "ok": true }
```

---

### `POST /v1/ring`

Rings the paired phone ("Find my phone").

**Request Body**:
```json
{
  "device": "Pixel 9 Pro"
}
```

**Response (`200 OK`)**:
```json
{ "ok": true }
```

---

### `POST /v1/play-on-phone`

Play on phone: what one of this PC's players plays moves to the phone,
streamed from the PC, or for protected streaming services, opened in the
service's app while the PC pauses. The phone shows a notification to tap.

**Request Body** (optional):
```json
{
  "player": "Chrome"
}
```

Without `player`, the player that's playing (else the first one).

**Response (`200 OK`)**:
```json
{ "ok": true, "player": "Chrome" }
```

`404` with `"nothing_playing"` when no player is there, `409` with
`"no_phone"` when no phone is online.

---

### `POST /v1/camera`

Triggers Continuity Camera on the paired phone (`"photo"` or `"scan"`).

**Request Body**:
```json
{
  "mode": "scan",
  "device": "Pixel 9 Pro"
}
```

**Response (`200 OK`)**:
```json
{
  "ok": true,
  "mode": "scan"
}
```

---

### `GET /v1/timeline`

Returns recent cross-device timeline items. Accepts optional query parameters `?limit=20&q=<filter>`.

**Response (`200 OK`)**:
```json
{
  "ok": true,
  "items": [
    {
      "id": "tl-1",
      "kind": "clipboard",
      "direction": "incoming",
      "peerId": "a1b2c3...",
      "peerName": "Pixel 9 Pro",
      "timestampMs": 1730000000000,
      "title": "Copied text",
      "subtitle": "Pixel 9 Pro",
      "payload": "Hello",
      "sizeBytes": 5
    }
  ]
}
```

---

## 4. Examples

### PowerShell

```powershell
$cfg = Get-Content "$env:LOCALAPPDATA\MacLink\api-token.json" | ConvertFrom-Json
$headers = @{ Authorization = "Bearer $($cfg.token)" }

# List paired devices
Invoke-RestMethod -Uri "http://127.0.0.1:$($cfg.port)/v1/devices" -Headers $headers

# Ring your phone
Invoke-RestMethod -Method Post -Uri "http://127.0.0.1:$($cfg.port)/v1/ring" `
  -Headers $headers -ContentType "application/json" -Body '{}'
```

### curl

```bash
TOKEN=$(jq -r .token "$LOCALAPPDATA/MacLink/api-token.json")
PORT=$(jq -r .port "$LOCALAPPDATA/MacLink/api-token.json")

curl -s -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:$PORT/v1/devices"
curl -s -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"mode":"photo"}' "http://127.0.0.1:$PORT/v1/camera"
```
