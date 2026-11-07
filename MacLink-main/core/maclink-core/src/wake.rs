// SPDX-License-Identifier: MPL-2.0
//! Relayed Wake-on-LAN (`wake.relay`) magic packet broadcaster.

use std::net::{Ipv4Addr, SocketAddrV4, UdpSocket};

use crate::Result;

/// Broadcasts a 102-byte Wake-on-LAN magic packet (`6 * 0xFF` followed by 16
/// repetitions of `mac`) on UDP ports 9 and 7 to `broadcast` (or
/// `255.255.255.255` when `None`).
pub fn send_magic_packet(mac: [u8; 6], broadcast: Option<Ipv4Addr>) -> Result<()> {
    let pkt = maclink_protocol::messages::magic_packet(&mac);
    let sock = UdpSocket::bind(SocketAddrV4::new(Ipv4Addr::UNSPECIFIED, 0))?;
    let _ = sock.set_broadcast(true);
    let target = broadcast.unwrap_or(Ipv4Addr::BROADCAST);
    for port in maclink_protocol::messages::wake::DEFAULT_PORTS {
        let _ = sock.send_to(&pkt, SocketAddrV4::new(target, *port));
        if target != Ipv4Addr::BROADCAST {
            let _ = sock.send_to(&pkt, SocketAddrV4::new(Ipv4Addr::BROADCAST, *port));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn send_magic_packet_succeeds_on_loopback() {
        let mac = [0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc];
        send_magic_packet(mac, Some(Ipv4Addr::LOCALHOST)).expect("loopback magic packet succeeds");
    }
}
