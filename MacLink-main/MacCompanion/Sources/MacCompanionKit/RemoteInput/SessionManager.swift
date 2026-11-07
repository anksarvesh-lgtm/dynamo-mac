// SPDX-License-Identifier: MIT
import Foundation

public struct PairedDevice: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let sharedSecret: String
    public let pairedAt: Date

    public init(id: String, name: String, sharedSecret: String, pairedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.sharedSecret = sharedSecret
        self.pairedAt = pairedAt
    }
}

public final class SessionManager: @unchecked Sendable {
    private let lock = NSLock()
    private var pairedDevices: [String: PairedDevice] = [:]
    private var activeSessions: [String: String] = [:] // SessionId -> DeviceId
    private var lastActivityTimes: [String: Date] = [:]

    public init() {}

    public func addPairedDevice(_ device: PairedDevice) {
        lock.lock()
        defer { lock.unlock() }
        pairedDevices[device.id] = device
    }

    public func removePairedDevice(id: String) {
        lock.lock()
        defer { lock.unlock() }
        pairedDevices.removeValue(forKey: id)
    }

    public func createSession(forDeviceId deviceId: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        let sessionId = UUID().uuidString
        activeSessions[sessionId] = deviceId
        lastActivityTimes[sessionId] = Date()
        return sessionId
    }

    public func isSessionValid(_ sessionId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeSessions[sessionId] != nil
    }

    public func recordActivity(for sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        lastActivityTimes[sessionId] = Date()
    }

    public func closeSession(_ sessionId: String) {
        lock.lock()
        defer { lock.unlock() }
        activeSessions.removeValue(forKey: sessionId)
        lastActivityTimes.removeValue(forKey: sessionId)
    }
}

