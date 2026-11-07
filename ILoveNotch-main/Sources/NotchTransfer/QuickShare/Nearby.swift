// SPDX-License-Identifier: MIT
import Foundation
import Network
import NotchCore
import os

/// Makes this Mac visible to Quick Share on the local network: a TCP listener announced over
/// Bonjour. Each phone that connects is handed on; nothing is saved until the user accepts.
@MainActor
final class Advertiser {
    /// Each phone that connects.
    var onConnection: ((NWConnection) -> Void)?
    /// Called with true when macOS refuses local network access, and false once it's allowed.
    var onDenied: ((Bool) -> Void)?
    private var listener: NWListener?
    private var retry: Task<Void, Never>?

    var isRunning: Bool { listener != nil || retry != nil }

    func start(endpointID: String, info: EndpointInfo) {
        stop()
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(
                name: ServiceName.make(endpointID: endpointID), type: ServiceName.type,
                txtRecord: NWTXTRecord(["n": info.encoded.base64URL]))
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.onConnection?(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                MainActor.assumeIsolated { self?.changed(state, endpointID: endpointID, info: info) }
            }
            listener.start(queue: .main)
            self.listener = listener
            Log.transfer.info("Visible to Quick Share as \(info.name ?? "", privacy: .private)")
        } catch {
            Log.transfer.error("Couldn't listen for Quick Share: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        retry?.cancel()
        retry = nil
        guard let listener else { return }
        listener.cancel()
        self.listener = nil
        Log.transfer.info("No longer visible to Quick Share")
    }

    private func changed(_ state: NWListener.State, endpointID: String, info: EndpointInfo) {
        switch state {
        case .ready:
            onDenied?(false)
        case .waiting(let error):
            Log.transfer.error("Quick Share listener waiting: \(error.localizedDescription, privacy: .public)")
            if QuickShareError(error) == .localNetworkDenied { onDenied?(true) }
        case .failed(let error):
            // A failed listener doesn't come back by itself, say after the network changes: try again
            // shortly, for as long as the Mac should be visible.
            Log.transfer.error("Quick Share listener failed: \(error.localizedDescription, privacy: .public)")
            if QuickShareError(error) == .localNetworkDenied { onDenied?(true) }
            listener?.cancel()
            listener = nil
            retry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.start(endpointID: endpointID, info: info)
            }
        default:
            break
        }
    }
}

/// A phone, tablet, or computer announcing Quick Share on the local network.
struct NearbyDevice: Identifiable, Hashable {
    let id: String
    var name: String
    var kind: EndpointInfo.Kind
    /// What it put in its announcement after scanning a QR code, if it did.
    var qrData: Data?
    let endpoint: NWEndpoint

    init(id: String, name: String, kind: EndpointInfo.Kind, qrData: Data? = nil, endpoint: NWEndpoint) {
        self.id = id
        self.name = name
        self.kind = kind
        self.qrData = qrData
        self.endpoint = endpoint
    }

    init?(_ result: NWBrowser.Result, excluding own: String) {
        guard case .service(let service, _, _, _) = result.endpoint, let id = ServiceName.endpointID(service),
            id != own,
            case .bonjour(let record) = result.metadata, let encoded = record["n"],
            let info = Data(base64URL: encoded).flatMap(EndpointInfo.init)
        else { return nil }
        self.id = id
        // A hidden device's name is only known once it answers a QR code.
        name = info.name ?? ""
        kind = info.kind
        qrData = info.qrData
        endpoint = result.endpoint
    }
}

/// Finds devices announcing Quick Share, only while the send window is open.
@MainActor
final class Browser {
    var onChange: (([NearbyDevice]) -> Void)?
    var onDenied: ((Bool) -> Void)?
    private var browser: NWBrowser?

    func start(excluding own: String) {
        stop()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: ServiceName.type, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated { self?.onChange?(results.compactMap { NearbyDevice($0, excluding: own) }) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .ready: self?.onDenied?(false)
                case .waiting(let error), .failed(let error):
                    Log.transfer.error("Quick Share browser: \(error.localizedDescription, privacy: .public)")
                    if QuickShareError(error) == .localNetworkDenied { self?.onDenied?(true) }
                default: break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
    }
}

extension Log {
    /// Quick Share: who connected, each stage, and why a transfer ended. Names are private.
    static let transfer = Logger(subsystem: subsystem, category: "transfer")
}
