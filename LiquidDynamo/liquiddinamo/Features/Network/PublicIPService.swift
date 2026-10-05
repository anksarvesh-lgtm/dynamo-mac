//
//  PublicIPService.swift
//  boringNotch
//
//  Created for Boring Notch
//

import Combine
import Foundation

/// Service managing on-demand retrieval of the user's public IP address.
///
/// Principles:
/// - Strictly off by default: Zero network calls until explicitly requested by the user.
/// - Privacy: Exclusively queries `api64.ipify.org` (user-confirmed endpoint).
/// - Reactive: Publishes IP string, loading indicator, and error message on `@MainActor`.
@MainActor
public final class PublicIPService: ObservableObject {
    public static let shared = PublicIPService()

    public static let serviceEndpointName = "api64.ipify.org"
    private static let serviceURL = URL(string: "https://api64.ipify.org")!

    @Published public private(set) var publicIP: String? = nil
    @Published public private(set) var isFetching: Bool = false
    @Published public private(set) var errorMessage: String? = nil
    @Published public var isRevealed: Bool = false

    private init() {}

    /// Fetches the public IP from `api64.ipify.org`.
    public func fetch() {
        isRevealed = true
        isFetching = true
        errorMessage = nil

        var request = URLRequest(url: Self.serviceURL)
        request.timeoutInterval = 5.0

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.isFetching = false

                if let error = error {
                    Logger.log("Failed to fetch public IP: \(error.localizedDescription)", category: .error)
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data = data,
                      let ipString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !ipString.isEmpty else {
                    self.errorMessage = "Empty response from \(Self.serviceEndpointName)"
                    return
                }

                self.publicIP = ipString
                Logger.log("Fetched public IP: \(ipString)", category: .network)
            }
        }.resume()
    }

    /// Hides the public IP display.
    public func hide() {
        isRevealed = false
    }
}
