// SPDX-License-Identifier: MIT

/// Which provider's mark to show. OpenUsage's providers name their mark this way; OpenNotch draws
/// it with its own provider logos (`ProviderLogo`), so only the identifier crosses over.
struct IconSource: Hashable, Sendable {
    let providerID: String

    static func providerMark(_ providerID: String) -> IconSource {
        IconSource(providerID: providerID)
    }
}
