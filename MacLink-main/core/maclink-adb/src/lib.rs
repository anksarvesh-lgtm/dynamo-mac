// SPDX-License-Identifier: MPL-2.0
//! Pure-Rust client for the local ADB server (`127.0.0.1:5037`) used to detect
//! USB-attached Android devices and set up TCP port forwarding for MacLink's
//! USB QUIC tunnel.

use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4};

use tokio::{
    io::{AsyncReadExt, AsyncWriteExt},
    net::{TcpListener, TcpStream},
};
use tokio_util::sync::CancellationToken;

/// Default local ADB server address (`127.0.0.1:5037`).
pub const DEFAULT_ADB_ADDR: SocketAddr = SocketAddr::V4(SocketAddrV4::new(Ipv4Addr::LOCALHOST, 5037));

/// Returns `true` if `serial` is non-empty and permitted by the optional
/// `MACLINK_ADB_ONLY_SERIAL` filter.
pub fn is_serial_allowed(serial: &str) -> bool {
    let trimmed = serial.trim();
    if trimmed.is_empty() {
        return false;
    }
    if let Ok(only) = std::env::var("MACLINK_ADB_ONLY_SERIAL") {
        let only = only.trim();
        if !only.is_empty() && trimmed != only {
            return false;
        }
    }
    true
}

/// Errors returned by ADB server operations.
#[derive(Debug, thiserror::Error)]
pub enum AdbError {
    #[error("ADB I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("ADB server rejected command: {0}")]
    Remote(String),
    #[error("ADB protocol error: {0}")]
    Protocol(String),
    #[error("ADB serial {0} is blocked by safety guard")]
    BlockedSerial(String),
}

/// An Android device reported by the ADB server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdbDevice {
    pub serial: String,
    pub state: String,
    pub model: Option<String>,
    pub product: Option<String>,
    pub transport_id: Option<String>,
}

impl AdbDevice {
    /// Whether the device is online and authorized (`state == "device"`).
    pub fn is_online(&self) -> bool {
        self.state == "device"
    }
}

/// Parses the output of `host:devices-l` or `host:track-devices`, filtering out
/// any serial rejected by [`is_serial_allowed`].
pub fn parse_devices_l(input: &str) -> Vec<AdbDevice> {
    let mut devices = Vec::new();
    for line in input.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with("List of devices") {
            continue;
        }
        let mut parts = trimmed.split_whitespace();
        let Some(serial) = parts.next() else { continue };
        let Some(state) = parts.next() else { continue };
        if !is_serial_allowed(serial) {
            continue;
        }
        let mut model = None;
        let mut product = None;
        let mut transport_id = None;
        for token in parts {
            if let Some(v) = token.strip_prefix("model:") {
                model = Some(v.to_owned());
            } else if let Some(v) = token.strip_prefix("product:") {
                product = Some(v.to_owned());
            } else if let Some(v) = token.strip_prefix("transport_id:") {
                transport_id = Some(v.to_owned());
            }
        }
        devices.push(AdbDevice {
            serial: serial.to_owned(),
            state: state.to_owned(),
            model,
            product,
            transport_id,
        });
    }
    devices
}

/// Sends a length-prefixed command to the ADB server and reads the 4-byte status.
pub async fn send_command(stream: &mut TcpStream, cmd: &str) -> Result<(), AdbError> {
    let frame = format!("{:04x}{cmd}", cmd.len());
    stream.write_all(frame.as_bytes()).await?;
    stream.flush().await?;
    let mut status = [0u8; 4];
    stream.read_exact(&mut status).await?;
    match &status {
        b"OKAY" => Ok(()),
        b"FAIL" => {
            let reason = read_payload(stream).await.unwrap_or_else(|_| "unknown failure".into());
            Err(AdbError::Remote(reason))
        }
        other => {
            Err(AdbError::Protocol(format!("unexpected ADB status: {}", String::from_utf8_lossy(other))))
        }
    }
}

/// Reads a 4-hex-digit length prefix followed by the UTF-8 payload.
pub async fn read_payload(stream: &mut TcpStream) -> Result<String, AdbError> {
    let mut len_hex = [0u8; 4];
    stream.read_exact(&mut len_hex).await?;
    let len_str =
        std::str::from_utf8(&len_hex).map_err(|_| AdbError::Protocol("invalid hex length".into()))?;
    let len = usize::from_str_radix(len_str, 16)
        .map_err(|_| AdbError::Protocol(format!("invalid hex length: {len_str}")))?;
    let mut buf = vec![0u8; len];
    if len > 0 {
        stream.read_exact(&mut buf).await?;
    }
    String::from_utf8(buf).map_err(|_| AdbError::Protocol("invalid UTF-8 payload".into()))
}

/// Lists attached ADB devices via `host:devices-l`.
pub async fn list_devices(server: SocketAddr) -> Result<Vec<AdbDevice>, AdbError> {
    let mut stream = TcpStream::connect(server).await?;
    send_command(&mut stream, "host:devices-l").await?;
    let payload = read_payload(&mut stream).await?;
    Ok(parse_devices_l(&payload))
}

/// Sets up TCP port forwarding (`adb -s <serial> forward tcp:<local> tcp:<remote>`)
/// and returns the bound local TCP port on `127.0.0.1`.
pub async fn forward_tcp(
    server: SocketAddr,
    serial: &str,
    local_port: u16,
    remote_port: u16,
) -> Result<u16, AdbError> {
    if !is_serial_allowed(serial) {
        return Err(AdbError::BlockedSerial(serial.to_owned()));
    }
    let port = if local_port == 0 {
        let listener = TcpListener::bind("127.0.0.1:0").await?;
        listener.local_addr()?.port()
    } else {
        local_port
    };
    let mut stream = TcpStream::connect(server).await?;
    let cmd = format!("host-serial:{serial}:forward:tcp:{port};tcp:{remote_port}");
    send_command(&mut stream, &cmd).await?;
    Ok(port)
}

/// Removes a TCP port forward (`adb -s <serial> forward --remove tcp:<local>`).
pub async fn kill_forward_tcp(server: SocketAddr, serial: &str, local_port: u16) -> Result<(), AdbError> {
    if !is_serial_allowed(serial) {
        return Err(AdbError::BlockedSerial(serial.to_owned()));
    }
    let mut stream = TcpStream::connect(server).await?;
    let cmd = format!("host-serial:{serial}:killforward:tcp:{local_port}");
    send_command(&mut stream, &cmd).await?;
    Ok(())
}

/// Streams device list changes from `host:track-devices` until `cancel` is
/// triggered or the ADB server closes the connection.
pub async fn track_devices<F>(
    server: SocketAddr,
    cancel: CancellationToken,
    mut on_change: F,
) -> Result<(), AdbError>
where
    F: FnMut(Vec<AdbDevice>),
{
    let mut stream = tokio::select! {
        _ = cancel.cancelled() => return Ok(()),
        res = TcpStream::connect(server) => res?,
    };
    send_command(&mut stream, "host:track-devices").await?;
    loop {
        let payload = tokio::select! {
            _ = cancel.cancelled() => return Ok(()),
            res = read_payload(&mut stream) => res?,
        };
        on_change(parse_devices_l(&payload));
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};

    #[test]
    fn empty_serial_is_rejected_and_valid_serials_are_allowed() {
        assert!(!is_serial_allowed(""));
        assert!(!is_serial_allowed("   "));
        assert!(is_serial_allowed("emulator-5554"));
        assert!(is_serial_allowed("SYNTH_SERIAL_001"));
    }

    #[test]
    fn parse_devices_l_parses_metadata() {
        let sample = "\
List of devices attached
SYNTH_SERIAL_001       device product:dm1q model:Test_Phone device:dm1q transport_id:1
emulator-5554          device product:sdk_gphone64_x86_64 model:Pixel_9 device:emu64x transport_id:2
192.168.1.40:5555      offline transport_id:3
";
        let devices = parse_devices_l(sample);
        assert_eq!(devices.len(), 3);
        assert_eq!(
            devices[0],
            AdbDevice {
                serial: "SYNTH_SERIAL_001".into(),
                state: "device".into(),
                model: Some("Test_Phone".into()),
                product: Some("dm1q".into()),
                transport_id: Some("1".into()),
            }
        );
        assert!(devices[0].is_online());
        assert_eq!(
            devices[1],
            AdbDevice {
                serial: "emulator-5554".into(),
                state: "device".into(),
                model: Some("Pixel_9".into()),
                product: Some("sdk_gphone64_x86_64".into()),
                transport_id: Some("2".into()),
            }
        );
        assert!(devices[1].is_online());
        assert_eq!(
            devices[2],
            AdbDevice {
                serial: "192.168.1.40:5555".into(),
                state: "offline".into(),
                model: None,
                product: None,
                transport_id: Some("3".into()),
            }
        );
        assert!(!devices[2].is_online());
    }

    #[tokio::test]
    async fn mock_adb_server_forward_killforward_and_track_devices() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        let commands = Arc::new(Mutex::new(Vec::<String>::new()));
        let commands_srv = commands.clone();

        let srv = tokio::spawn(async move {
            loop {
                let Ok((mut socket, _)) = listener.accept().await else { break };
                let commands_srv = commands_srv.clone();
                tokio::spawn(async move {
                    let Ok(cmd) = read_payload(&mut socket).await else { return };
                    commands_srv.lock().unwrap().push(cmd.clone());
                    if cmd == "host:track-devices" {
                        let _ = socket.write_all(b"OKAY").await;
                        let update1 = "emulator-5554\tdevice\n";
                        let frame1 = format!("{:04x}{update1}", update1.len());
                        let _ = socket.write_all(frame1.as_bytes()).await;
                        let _ = socket.flush().await;
                        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
                    } else if cmd.starts_with("host-serial:") {
                        let _ = socket.write_all(b"OKAY").await;
                        let _ = socket.flush().await;
                    } else if cmd == "host:devices-l" {
                        let _ = socket.write_all(b"OKAY").await;
                        let body =
                            "List of devices attached\nemulator-5554 device model:Pixel_9 transport_id:4\n";
                        let frame = format!("{:04x}{body}", body.len());
                        let _ = socket.write_all(frame.as_bytes()).await;
                        let _ = socket.flush().await;
                    }
                });
            }
        });

        // Empty serial must be rejected before even connecting.
        let blocked_res = forward_tcp(addr, "   ", 0, 53319).await;
        assert!(matches!(blocked_res, Err(AdbError::BlockedSerial(_))));
        let blocked_kill = kill_forward_tcp(addr, "", 12345).await;
        assert!(matches!(blocked_kill, Err(AdbError::BlockedSerial(_))));

        let devs = list_devices(addr).await.unwrap();
        assert_eq!(devs.len(), 1);
        assert_eq!(devs[0].serial, "emulator-5554");

        let port = forward_tcp(addr, "emulator-5554", 0, 53319).await.unwrap();
        assert_ne!(port, 0);
        kill_forward_tcp(addr, "emulator-5554", port).await.unwrap();

        let cancel = CancellationToken::new();
        let cancel_clone = cancel.clone();
        let mut tracked = Vec::new();
        track_devices(addr, cancel_clone, |list| {
            tracked = list;
            cancel.cancel();
        })
        .await
        .unwrap();

        assert_eq!(tracked.len(), 1);
        assert_eq!(tracked[0].serial, "emulator-5554");
        assert!(tracked[0].is_online());

        let recorded = commands.lock().unwrap().clone();
        assert!(recorded.iter().any(|c| c == "host:devices-l"));
        assert!(
            recorded.iter().any(|c| c == &format!("host-serial:emulator-5554:forward:tcp:{port};tcp:53319"))
        );
        assert!(recorded.iter().any(|c| c == &format!("host-serial:emulator-5554:killforward:tcp:{port}")));
        assert!(recorded.iter().any(|c| c == "host:track-devices"));

        srv.abort();
    }
}
