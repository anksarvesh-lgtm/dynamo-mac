// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS audio output streaming player.

#[derive(Debug)]
pub struct Player;

impl Player {
    pub fn start(rate: u32, channels: u16) -> std::io::Result<Player> {
        Self::start_on(None, rate, channels)
    }

    pub fn start_on(_device: Option<String>, _rate: u32, _channels: u16) -> std::io::Result<Player> {
        Err(std::io::Error::new(
            std::io::ErrorKind::Unsupported,
            "streamed audio playback is not yet implemented on macOS",
        ))
    }

    pub fn push(&self, _data: Vec<u8>) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn audio_out_reports_unsupported() {
        assert_eq!(Player::start(48000, 2).unwrap_err().kind(), std::io::ErrorKind::Unsupported);
        assert_eq!(Player::start_on(None, 48000, 2).unwrap_err().kind(), std::io::ErrorKind::Unsupported);
    }
}
