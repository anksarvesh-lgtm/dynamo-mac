import Foundation

/// What the transport button was just asked to do, and for how long the card
/// may speak for the player.
///
/// A press has to answer immediately — a button that waits for a round trip
/// reads as broken — so the card shows what was asked for before the player
/// has confirmed it. The danger is the other half: the player may refuse, or
/// simply never answer, and the optimistic reading then stands for ever. That
/// is how a refused Play left the card showing Pause with the waves moving
/// over silence, the one reading on that card nobody can check against
/// anything else.
///
/// So optimism carries a deadline. Within it the card speaks; past it the
/// player's own reading wins, including when the player's answer is "nothing
/// changed".
///
/// Pure and clockless, like the rest of this folder: the caller passes `now`.
public struct PlaybackIntent: Equatable, Sendable {

    /// How long the card may speak for the player.
    ///
    /// Two seconds. A local player answers within one — the adapter publishes
    /// on its own poll while playing — and past two a refusal should read as a
    /// flicker rather than a lie that stands.
    public static let grace: TimeInterval = 2

    private var wanted: Bool?
    private var askedAt: TimeInterval = 0

    public init() {}

    /// The button was pressed.
    public mutating func ask(for playing: Bool, at now: TimeInterval) {
        wanted = playing
        askedAt = now
    }

    /// The player said something. Whatever it says is the truth, so the
    /// optimism ends here whether or not it agrees.
    public mutating func reported() {
        wanted = nil
        askedAt = 0
    }

    /// What the card should draw.
    ///
    /// - Parameter reported: the player's own state, as last published.
    public func displayed(reported: Bool, at now: TimeInterval) -> Bool {
        guard let wanted, now - askedAt < Self.grace else { return reported }
        return wanted
    }

    /// Whether the card is currently speaking for the player rather than
    /// repeating it.
    public func isSpeaking(at now: TimeInterval) -> Bool {
        wanted != nil && now - askedAt < Self.grace
    }
}
