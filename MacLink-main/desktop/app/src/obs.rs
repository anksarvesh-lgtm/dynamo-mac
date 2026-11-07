// SPDX-License-Identifier: GPL-3.0-or-later
//! OBS Studio control for Deck tiles (`obs:record`, `obs:scene:<name>`, ...) over the
//! obs-websocket v5 protocol that ships with OBS 28 and later.
//!
//! The exchange: OBS greets (`Hello`, op 0), possibly with a login challenge; we identify
//! (op 1), with the answer if OBS asked for one; OBS confirms (`Identified`, op 2); we send
//! one request (op 6) and read its result (op 7). OBS turns authentication on by default,
//! so the password from Settings is needed in most setups. It's stored encrypted with
//! Windows DPAPI, like the device key.

use crate::i18n::tr;
use std::{
    io::{Read, Write},
    net::{SocketAddr, TcpStream},
    time::Duration,
};

use data_encoding::BASE64;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

/// obs-websocket's default port.
pub const DEFAULT_PORT: u16 = 4455;

const TIMEOUT: Duration = Duration::from_millis(1500);
/// obs-websocket closes with this code when the password is wrong or missing.
const CLOSE_AUTH_FAILED: u16 = 4009;
/// The largest message we accept from OBS (responses to our requests are small).
const MAX_MESSAGE: u64 = 1 << 20;

/// Runs one Deck OBS command against the OBS on this PC.
pub fn run(command: &str, port: u16, password: Option<&str>) -> Result<(), String> {
    let (request_type, request_data) = request_for(command);
    let mut ws = Socket::connect(port)?;

    let hello = ws.read_json()?;
    if hello["op"] != 0 {
        return Err("OBS sent an unexpected greeting.".into());
    }
    let mut identify = json!({ "rpcVersion": 1, "eventSubscriptions": 0 });
    if let Some(auth) = hello["d"].get("authentication") {
        let (Some(challenge), Some(salt)) = (auth["challenge"].as_str(), auth["salt"].as_str()) else {
            return Err("OBS sent an unreadable login challenge.".into());
        };
        let Some(password) = password.filter(|p| !p.is_empty()) else {
            return Err(
                "OBS asks for a password. Add it in Settings › Shortcuts & Rules › OBS Studio.".into()
            );
        };
        identify["authentication"] = json!(auth_response(password, salt, challenge));
    }
    ws.write_json(&json!({ "op": 1, "d": identify }))?;

    let identified = ws.read_json()?;
    if identified["op"] != 2 {
        return Err("OBS didn't accept the connection.".into());
    }

    ws.write_json(&json!({
        "op": 6,
        "d": { "requestType": request_type, "requestId": "maclink-deck", "requestData": request_data },
    }))?;
    let response = ws.read_json()?;
    let status = &response["d"]["requestStatus"];
    if response["op"] == 7 && status["result"] == true {
        Ok(())
    } else {
        let detail = status["comment"].as_str().unwrap_or("the request failed");
        Err(tr!("Obs", "OBS: %1", detail))
    }
}

/// The obs-websocket request for a Deck command.
fn request_for(command: &str) -> (String, Value) {
    if let Some(scene) = command.strip_prefix("scene:") {
        return ("SetCurrentProgramScene".into(), json!({ "sceneName": scene.trim() }));
    }
    let request = match command.to_ascii_lowercase().as_str() {
        "record" | "togglerecord" => "ToggleRecord",
        "stream" | "togglestream" => "ToggleStream",
        "replay" | "savereplaybuffer" => "SaveReplayBuffer",
        "virtualcam" | "togglevirtualcam" => "ToggleVirtualCam",
        "pause" | "togglerecordpause" => "ToggleRecordPause",
        _ => command,
    };
    (request.to_owned(), json!({}))
}

/// obs-websocket's login answer: base64(sha256(base64(sha256(password + salt)) + challenge)).
fn auth_response(password: &str, salt: &str, challenge: &str) -> String {
    let secret = BASE64.encode(&Sha256::digest(format!("{password}{salt}").as_bytes()));
    BASE64.encode(&Sha256::digest(format!("{secret}{challenge}").as_bytes()))
}

/// A minimal WebSocket client: one connection, text messages only.
struct Socket {
    stream: TcpStream,
}

impl Socket {
    fn connect(port: u16) -> Result<Self, String> {
        let addr = SocketAddr::from(([127, 0, 0, 1], port));
        let mut stream = TcpStream::connect_timeout(&addr, TIMEOUT)
            .map_err(|_| tr!("Obs", "OBS isn't reachable on port %1. Turn on its WebSocket server.", port))?;
        let _ = stream.set_read_timeout(Some(TIMEOUT));
        let _ = stream.set_write_timeout(Some(TIMEOUT));
        let _ = stream.set_nodelay(true);

        let key = BASE64.encode(&nonce());
        let handshake = format!(
            "GET / HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\
             Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\
             Sec-WebSocket-Protocol: obswebsocket.json\r\n\r\n"
        );
        stream.write_all(handshake.as_bytes()).map_err(|e| e.to_string())?;

        // Read the HTTP response up to the blank line, one byte at a time so no frame
        // bytes that follow are consumed.
        let mut head = Vec::new();
        let mut byte = [0u8; 1];
        while !head.ends_with(b"\r\n\r\n") {
            if head.len() > 8192 || stream.read(&mut byte).map_err(|e| e.to_string())? == 0 {
                return Err("OBS closed the connection.".into());
            }
            head.push(byte[0]);
        }
        let head = String::from_utf8_lossy(&head);
        if !head.starts_with("HTTP/1.1 101") {
            return Err("OBS refused the connection.".into());
        }
        let expected = BASE64.encode(&sha1(format!("{key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11").as_bytes()));
        let accepted = head.lines().any(|l| {
            l.split_once(':').is_some_and(|(k, v)| {
                k.trim().eq_ignore_ascii_case("sec-websocket-accept") && v.trim() == expected
            })
        });
        if !accepted {
            return Err(tr!("Obs", "The service on that port isn't OBS."));
        }
        Ok(Self { stream })
    }

    fn write_json(&mut self, value: &Value) -> Result<(), String> {
        let frame = encode_text_frame(&value.to_string());
        self.stream.write_all(&frame).and_then(|()| self.stream.flush()).map_err(|e| e.to_string())
    }

    /// Reads the next text message, answering pings; a close frame becomes an error.
    fn read_json(&mut self) -> Result<Value, String> {
        loop {
            let (opcode, payload) = self.read_frame()?;
            match opcode {
                0x1 => {
                    return serde_json::from_slice(&payload).map_err(|_| "OBS sent unreadable data.".into());
                }
                0x8 => {
                    let code = payload.get(..2).map(|b| u16::from_be_bytes([b[0], b[1]]));
                    return Err(if code == Some(CLOSE_AUTH_FAILED) {
                        "OBS rejected the password. Check it in Settings › Shortcuts & Rules › OBS Studio."
                            .into()
                    } else {
                        "OBS closed the connection.".into()
                    });
                }
                0x9 => {
                    let pong = encode_frame(0xA, &payload);
                    self.stream.write_all(&pong).map_err(|e| e.to_string())?;
                }
                _ => {}
            }
        }
    }

    fn read_frame(&mut self) -> Result<(u8, Vec<u8>), String> {
        let mut head = [0u8; 2];
        self.read_exact(&mut head)?;
        let opcode = head[0] & 0x0F;
        let masked = head[1] & 0x80 != 0;
        let mut len = u64::from(head[1] & 0x7F);
        if len == 126 {
            let mut b = [0u8; 2];
            self.read_exact(&mut b)?;
            len = u64::from(u16::from_be_bytes(b));
        } else if len == 127 {
            let mut b = [0u8; 8];
            self.read_exact(&mut b)?;
            len = u64::from_be_bytes(b);
        }
        if len > MAX_MESSAGE {
            return Err("OBS sent an oversized message.".into());
        }
        let mut mask = [0u8; 4];
        if masked {
            self.read_exact(&mut mask)?;
        }
        let mut payload = vec![0u8; len as usize];
        self.read_exact(&mut payload)?;
        if masked {
            for (i, b) in payload.iter_mut().enumerate() {
                *b ^= mask[i & 3];
            }
        }
        Ok((opcode, payload))
    }

    fn read_exact(&mut self, buf: &mut [u8]) -> Result<(), String> {
        self.stream.read_exact(buf).map_err(|_| "OBS didn't answer in time.".to_owned())
    }
}

fn encode_text_frame(text: &str) -> Vec<u8> {
    encode_frame(0x1, text.as_bytes())
}

/// A final, client-masked frame (clients must mask, RFC 6455 §5.3).
fn encode_frame(opcode: u8, bytes: &[u8]) -> Vec<u8> {
    let mut frame = Vec::with_capacity(bytes.len() + 14);
    frame.push(0x80 | opcode);
    let len = bytes.len();
    if len < 126 {
        frame.push(0x80 | len as u8);
    } else if len <= usize::from(u16::MAX) {
        frame.push(0x80 | 126);
        frame.extend_from_slice(&(len as u16).to_be_bytes());
    } else {
        frame.push(0x80 | 127);
        frame.extend_from_slice(&(len as u64).to_be_bytes());
    }
    let mask: [u8; 4] = nonce()[..4].try_into().unwrap_or([0x37, 0xFA, 0x21, 0x3D]);
    frame.extend_from_slice(&mask);
    frame.extend(bytes.iter().enumerate().map(|(i, b)| b ^ mask[i & 3]));
    frame
}

/// 16 unpredictable bytes for the handshake key and frame masks.
fn nonce() -> [u8; 16] {
    let mut hasher = blake3::Hasher::new();
    let now = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap_or_default();
    hasher.update(&now.as_nanos().to_le_bytes());
    hasher.update(&std::process::id().to_le_bytes());
    let local = 0u8;
    hasher.update(&(std::ptr::from_ref(&local) as usize).to_le_bytes());
    let mut out = [0u8; 16];
    out.copy_from_slice(&hasher.finalize().as_bytes()[..16]);
    out
}

/// SHA-1, only for the WebSocket handshake check (RFC 6455 §4.2.2 requires it).
fn sha1(data: &[u8]) -> [u8; 20] {
    let mut h: [u32; 5] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0];
    let mut msg = data.to_vec();
    let bit_len = (data.len() as u64).wrapping_mul(8);
    msg.push(0x80);
    while msg.len() % 64 != 56 {
        msg.push(0);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());
    for chunk in msg.as_chunks::<64>().0 {
        let mut w = [0u32; 80];
        for (i, word) in chunk.as_chunks::<4>().0.iter().enumerate() {
            w[i] = u32::from_be_bytes(*word);
        }
        for i in 16..80 {
            w[i] = (w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]).rotate_left(1);
        }
        let [mut a, mut b, mut c, mut d, mut e] = h;
        for (i, wi) in w.iter().enumerate() {
            let (f, k) = match i {
                0..=19 => ((b & c) | (!b & d), 0x5A82_7999),
                20..=39 => (b ^ c ^ d, 0x6ED9_EBA1),
                40..=59 => ((b & c) | (b & d) | (c & d), 0x8F1B_BCDC),
                _ => (b ^ c ^ d, 0xCA62_C1D6),
            };
            let temp = a.rotate_left(5).wrapping_add(f).wrapping_add(e).wrapping_add(k).wrapping_add(*wi);
            e = d;
            d = c;
            c = b.rotate_left(30);
            b = a;
            a = temp;
        }
        for (hv, v) in h.iter_mut().zip([a, b, c, d, e]) {
            *hv = hv.wrapping_add(v);
        }
    }
    let mut out = [0u8; 20];
    for (i, v) in h.iter().enumerate() {
        out[i * 4..i * 4 + 4].copy_from_slice(&v.to_be_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn auth_response_matches_the_obs_websocket_reference() {
        // From the obs-websocket v5 protocol documentation's authentication example.
        assert_eq!(
            auth_response(
                "supersecretpassword",
                "lM1GncleQOaCu9lT1yeUZhFYnqhsLLP1G5lAGo3ixaI=",
                "+IxH4CnCiqpX1rM9scsNynZzbOe4KhDeYcTNS3PDaeY="
            ),
            "1Ct943GAT+6YQUUX47Ia/ncufilbe6+oD6lY+5kaCu4="
        );
    }

    #[test]
    fn handshake_accept_uses_rfc_6455_sha1() {
        // RFC 6455 §1.3 example.
        let accept = BASE64.encode(&sha1(b"dGhlIHNhbXBsZSBub25jZQ==258EAFA5-E914-47DA-95CA-C5AB0DC85B11"));
        assert_eq!(accept, "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=");
    }

    #[test]
    fn commands_map_to_obs_requests() {
        assert_eq!(request_for("record").0, "ToggleRecord");
        assert_eq!(request_for("Stream").0, "ToggleStream");
        let (kind, data) = request_for("scene: Gameplay ");
        assert_eq!(kind, "SetCurrentProgramScene");
        assert_eq!(data["sceneName"], "Gameplay");
    }

    #[test]
    fn frames_are_masked_and_sized() {
        let small = encode_text_frame("hi");
        assert_eq!(small[0], 0x81);
        assert_eq!(small[1], 0x80 | 2);
        assert_eq!(small.len(), 2 + 4 + 2);
        let medium = encode_text_frame(&"x".repeat(300));
        assert_eq!(medium[1], 0x80 | 126);
        assert_eq!(u16::from_be_bytes([medium[2], medium[3]]), 300);
    }
}
