// SPDX-License-Identifier: MPL-2.0
//! Play on phone: how to move what a PC is playing to a phone.
//!
//! Most playback is streamed from the PC as it plays (its picture and its
//! sound), so whatever the PC does to it carries over: a browser's ad
//! blocker on YouTube, for one. Streaming services protect their video
//! (captured, it comes out black), so for those the phone opens the same
//! page, which Android hands to the service's app, and the PC pauses.

use crate::handoff::with_video_timestamp;

/// What Play on phone does for what's playing.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PlayOnPhone {
    /// Stream the PC's playback to the phone; the PC keeps playing it.
    Stream {
        /// The page can also be opened on the phone instead (in its app),
        /// at this URL: the PC's page with its position, when known.
        open_instead: Option<String>,
    },
    /// Open this URL on the phone (the service's app takes it) and pause
    /// the PC.
    Open {
        url: String,
        /// The service, for the PC to say where it went ("Netflix").
        service: &'static str,
    },
}

/// Services whose video is protected: (host, or a host it ends with, name).
const PROTECTED: &[(&str, &str)] = &[
    ("netflix.com", "Netflix"),
    ("primevideo.com", "Prime Video"),
    ("hotstar.com", "JioHotstar"),
    ("jiohotstar.com", "JioHotstar"),
    ("disneyplus.com", "Disney+"),
    ("max.com", "Max"),
    ("hbomax.com", "Max"),
    ("tv.apple.com", "Apple TV"),
    ("hulu.com", "Hulu"),
    ("peacocktv.com", "Peacock"),
    ("paramountplus.com", "Paramount+"),
    ("sonyliv.com", "Sony LIV"),
    ("zee5.com", "ZEE5"),
    ("crunchyroll.com", "Crunchyroll"),
];

/// Decides for a page at `url` (the browser's address, when the player is
/// a browser tab and the PC could read it), playing at `position_secs`.
#[must_use]
pub fn plan(url: Option<&str>, position_secs: Option<u32>) -> PlayOnPhone {
    let Some(url) = url.map(str::trim).filter(|u| is_web(u)) else {
        return PlayOnPhone::Stream { open_instead: None };
    };
    let host = host_of(url);
    if let Some(service) = protected_service(&host, url) {
        return PlayOnPhone::Open { url: url.to_owned(), service };
    }
    let open_instead = match position_secs {
        Some(secs) if is_youtube(&host) => with_video_timestamp(url, secs),
        _ => url.to_owned(),
    };
    PlayOnPhone::Stream { open_instead: Some(open_instead) }
}

fn is_web(url: &str) -> bool {
    let lower = url.to_ascii_lowercase();
    lower.starts_with("https://") || lower.starts_with("http://")
}

/// The lowercase host of a web URL, without a port, user info or "www.".
fn host_of(url: &str) -> String {
    let rest = url.split_once("://").map_or(url, |(_, rest)| rest);
    let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
    let host = authority.rsplit_once('@').map_or(authority, |(_, host)| host);
    let host = host.split(':').next().unwrap_or("").to_ascii_lowercase();
    host.strip_prefix("www.").map(str::to_owned).unwrap_or(host)
}

fn is_host(host: &str, domain: &str) -> bool {
    host == domain || host.strip_suffix(domain).is_some_and(|sub| sub.ends_with('.'))
}

fn is_youtube(host: &str) -> bool {
    is_host(host, "youtube.com") || host == "youtu.be"
}

fn protected_service(host: &str, url: &str) -> Option<&'static str> {
    if let Some(&(_, name)) = PROTECTED.iter().find(|(domain, _)| is_host(host, domain)) {
        return Some(name);
    }
    // Prime Video also plays on Amazon's own sites (amazon.com/gp/video).
    let amazon = host.split('.').next() == Some("amazon") || host.starts_with("amazon.");
    let path = url.split_once("://").map_or(url, |(_, rest)| rest);
    let path = path.find('/').map_or("", |i| &path[i..]).to_ascii_lowercase();
    (amazon && path.starts_with("/gp/video")).then_some("Prime Video")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stream(open: Option<&str>) -> PlayOnPhone {
        PlayOnPhone::Stream { open_instead: open.map(str::to_owned) }
    }

    #[test]
    fn youtube_streams_from_the_pc_and_can_open_at_the_same_second() {
        assert_eq!(
            plan(Some("https://www.youtube.com/watch?v=abc"), Some(90)),
            stream(Some("https://www.youtube.com/watch?v=abc&t=90"))
        );
        assert_eq!(
            plan(Some("https://m.youtube.com/watch?v=abc&t=5"), Some(42)),
            stream(Some("https://m.youtube.com/watch?v=abc&t=42"))
        );
        assert_eq!(plan(Some("https://youtu.be/abc"), None), stream(Some("https://youtu.be/abc")));
    }

    #[test]
    fn protected_services_open_in_their_app() {
        assert_eq!(
            plan(Some("https://www.netflix.com/watch/8118?trackId=1"), Some(600)),
            PlayOnPhone::Open {
                url: "https://www.netflix.com/watch/8118?trackId=1".into(),
                service: "Netflix"
            }
        );
        for (url, service) in [
            ("https://www.primevideo.com/detail/0ABC", "Prime Video"),
            ("https://www.amazon.co.uk/gp/video/detail/B0X", "Prime Video"),
            ("https://www.amazon.com/gp/video/detail/B0X", "Prime Video"),
            ("https://www.hotstar.com/in/shows/x/123", "JioHotstar"),
            ("https://www.jiohotstar.com/movies/y/456", "JioHotstar"),
            ("https://www.disneyplus.com/video/1", "Disney+"),
            ("https://play.max.com/video/watch/1", "Max"),
            ("https://tv.apple.com/us/show/x", "Apple TV"),
        ] {
            assert_eq!(plan(Some(url), None), PlayOnPhone::Open { url: url.into(), service }, "{url}");
        }
    }

    #[test]
    fn lookalike_hosts_are_not_the_service() {
        assert!(matches!(plan(Some("https://notnetflix.com/watch/1"), None), PlayOnPhone::Stream { .. }));
        assert!(matches!(plan(Some("https://netflix.com.example.org/"), None), PlayOnPhone::Stream { .. }));
        assert!(matches!(plan(Some("https://www.amazon.com/dp/B0X"), None), PlayOnPhone::Stream { .. }));
        assert!(matches!(plan(Some("https://climax.com/"), None), PlayOnPhone::Stream { .. }));
    }

    #[test]
    fn the_host_ignores_case_ports_and_user_info() {
        assert!(matches!(plan(Some("HTTPS://WWW.NETFLIX.COM:443/watch/1"), None), PlayOnPhone::Open { .. }));
        assert!(matches!(
            plan(Some("https://user@www.netflix.com/watch/1"), None),
            PlayOnPhone::Open { service: "Netflix", .. }
        ));
    }

    #[test]
    fn anything_else_streams() {
        // An app, not a browser tab: there's no page to open.
        assert_eq!(plan(None, Some(30)), stream(None));
        assert_eq!(plan(Some("file:///C:/Videos/a.mp4"), None), stream(None));
        assert_eq!(
            plan(Some("https://vimeo.com/123"), Some(30)),
            stream(Some("https://vimeo.com/123")),
            "only YouTube's position is put in the link"
        );
    }
}
