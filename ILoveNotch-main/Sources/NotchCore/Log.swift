// SPDX-License-Identifier: MIT
import os

/// Typed log channels and signposts. Stream them with:
///
///     log stream --level debug --predicate 'subsystem == "cafe.opennotch.app"'
///
/// Signposts land in Instruments' Points of Interest track, where event handling and feature
/// phase changes can be measured against the performance budgets.
public enum Log {
    public static let subsystem = "cafe.opennotch.app"

    /// Presentation transitions.
    public static let state = Logger(subsystem: subsystem, category: "state")
    /// Feature lifecycle changes.
    public static let features = Logger(subsystem: subsystem, category: "features")
    /// Panel and display work.
    public static let surface = Logger(subsystem: subsystem, category: "surface")
    /// Per-app volume: which apps play, and their taps.
    public static let mixer = Logger(subsystem: subsystem, category: "mixer")
    /// Intervals around event handling and feature phase changes.
    public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
