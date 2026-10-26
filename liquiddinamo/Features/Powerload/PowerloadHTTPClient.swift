//
//  PowerloadHTTPClient.swift
//  LiquidDynamo
//
//  High-performance interface-bound HTTP client using Network.framework (NWConnection)
//  with strict NWParameters.requiredInterface binding and fallback to /usr/bin/curl.
//  Replaces undocumented private KVC _socketStreamProperties with documented Apple APIs.
//

import Foundation
import Network

public enum PowerloadHTTPError: LocalizedError, Sendable {
    case invalidURL
    case connectionFailed(String)
    case timeout
    case cancelled
    case invalidStatus(Int)
    case rangeNotSupported(statusCode: Int)
    case byteCountMismatch(expected: Int64, received: Int64)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid download URL."
        case .connectionFailed(let reason): return "Network connection failed: \(reason)"
        case .timeout: return "Download chunk timed out."
        case .cancelled: return "Download chunk was cancelled."
        case .invalidStatus(let code): return "HTTP status \(code)."
        case .rangeNotSupported(let code): return "Server returned status \(code) (Range requests not supported)."
        case .byteCountMismatch(let exp, let rec): return "Chunk size mismatch: expected \(exp) bytes, received \(rec) bytes."
        case .writeFailed(let reason): return "Failed to write data to disk: \(reason)"
        }
    }
}

public struct PowerloadHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let contentRange: String?
    public let data: Data

    public init(statusCode: Int, headers: [String: String], contentRange: String?, data: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.contentRange = contentRange
        self.data = data
    }
}

public final class PowerloadHTTPClient: @unchecked Sendable {
    public static let shared = PowerloadHTTPClient()

    private let pathMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.liquiddynamo.powerload.httpclient.monitor", qos: .utility)
    private var cachedAvailableInterfaces: [String: NWInterface] = [:]
    private let lock = NSLock()

    private init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.lock.lock()
            var map: [String: NWInterface] = [:]
            for iface in path.availableInterfaces {
                map[iface.name] = iface
            }
            self.cachedAvailableInterfaces = map
            self.lock.unlock()
        }
        pathMonitor.start(queue: monitorQueue)
    }

    deinit {
        pathMonitor.cancel()
    }

    public func getNWInterface(bsdName: String) -> NWInterface? {
        lock.lock()
        defer { lock.unlock() }
        if let iface = cachedAvailableInterfaces[bsdName] {
            return iface
        }
        // Fallback: check currentPath directly
        return pathMonitor.currentPath.availableInterfaces.first { $0.name == bsdName }
    }

    /// Bound probe against target host using designated interface
    public func probeInterface(bsdName: String, url: URL, timeout: TimeInterval = 6.0) async -> Bool {
        guard let host = url.host else { return false }
        let isHTTPS = url.scheme?.lowercased() == "https"
        let portNumber = UInt16(url.port ?? (isHTTPS ? 443 : 80))

        let nwInterface = getNWInterface(bsdName: bsdName)

        // Try NWConnection first if interface is available in NWPath
        if let iface = nwInterface {
            let success = await withCheckedContinuation { continuation in
                let tcpOptions = NWProtocolTCP.Options()
                let tlsOptions = isHTTPS ? NWProtocolTLS.Options() : nil
                let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
                params.requiredInterface = iface

                let nwHost = NWEndpoint.Host(host)
                let nwPort = NWEndpoint.Port(rawValue: portNumber)!
                let connection = NWConnection(host: nwHost, port: nwPort, using: params)

                final class ProbeState: @unchecked Sendable {
                    var resumed = false
                    var timer: DispatchSourceTimer?
                }
                let state = ProbeState()

                let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
                timeoutTimer.schedule(deadline: .now() + timeout)
                timeoutTimer.setEventHandler {
                    if !state.resumed {
                        state.resumed = true
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                }
                timeoutTimer.resume()
                state.timer = timeoutTimer

                connection.stateUpdateHandler = { connState in
                    switch connState {
                    case .ready:
                        let path = url.path.isEmpty ? "/" : url.path
                        let req = "HEAD \(path) HTTP/1.1\r\nHost: \(host)\r\nUser-Agent: LiquidDynamo/2.0.5\r\nConnection: close\r\n\r\n"
                        connection.send(content: req.data(using: .utf8), completion: .contentProcessed({ error in
                            if error != nil {
                                if !state.resumed {
                                    state.resumed = true
                                    state.timer?.cancel()
                                    connection.cancel()
                                    continuation.resume(returning: false)
                                }
                            } else {
                                connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, recvError in
                                    if !state.resumed {
                                        state.resumed = true
                                        state.timer?.cancel()
                                        connection.cancel()
                                        continuation.resume(returning: recvError == nil && (data?.count ?? 0) > 0)
                                    }
                                }
                            }
                        }))
                    case .failed, .cancelled:
                        if !state.resumed {
                            state.resumed = true
                            state.timer?.cancel()
                            continuation.resume(returning: false)
                        }
                    default:
                        break
                    }
                }
                connection.start(queue: DispatchQueue.global(qos: .utility))
            }

            if success { return true }
        }

        // Secondary fallback probe via curl bound to interface
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                proc.arguments = [
                    "--interface", bsdName,
                    "-I",
                    "--max-time", "\(Int(timeout))",
                    "-s", "-o", "/dev/null",
                    "-w", "%{http_code}",
                    url.absoluteString
                ]
                do {
                    let pipe = Pipe()
                    proc.standardOutput = pipe
                    try proc.run()
                    proc.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let codeStr = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let code = Int(codeStr) ?? 0
                    continuation.resume(returning: proc.terminationStatus == 0 && code >= 200 && code < 400)
                } catch {
                    continuation.resume(returning: false)
                }
            }
        }
    }

    /// Downloads a chunk range bound to the specified interface.
    public func downloadChunk(
        url: URL,
        rangeStart: Int64,
        rangeEnd: Int64,
        bsdName: String,
        timeout: TimeInterval = 20.0
    ) async throws -> PowerloadHTTPResponse {
        guard let host = url.host else { throw PowerloadHTTPError.invalidURL }
        let isHTTPS = url.scheme?.lowercased() == "https"
        let portNumber = UInt16(url.port ?? (isHTTPS ? 443 : 80))
        let expectedBytes = rangeEnd - rangeStart + 1

        let nwInterface = getNWInterface(bsdName: bsdName)

        // Method A: Primary native NWConnection with requiredInterface binding
        if let iface = nwInterface {
            do {
                return try await performNWConnectionChunk(
                    url: url,
                    host: host,
                    portNumber: portNumber,
                    isHTTPS: isHTTPS,
                    iface: iface,
                    rangeStart: rangeStart,
                    rangeEnd: rangeEnd,
                    expectedBytes: expectedBytes,
                    timeout: timeout
                )
            } catch {
                // If NWConnection fails, try Method C fallback (curl bound to interface)
            }
        }

        // Method C: Fallback to /usr/bin/curl bound to interface
        return try await performCurlChunk(
            url: url,
            bsdName: bsdName,
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            expectedBytes: expectedBytes,
            timeout: timeout
        )
    }

    // MARK: - Method A: NWConnection Implementation

    private func performNWConnectionChunk(
        url: URL,
        host: String,
        portNumber: UInt16,
        isHTTPS: Bool,
        iface: NWInterface,
        rangeStart: Int64,
        rangeEnd: Int64,
        expectedBytes: Int64,
        timeout: TimeInterval
    ) async throws -> PowerloadHTTPResponse {
        return try await withCheckedThrowingContinuation { continuation in
            let tcpOptions = NWProtocolTCP.Options()
            let tlsOptions = isHTTPS ? NWProtocolTLS.Options() : nil
            let params = NWParameters(tls: tlsOptions, tcp: tcpOptions)
            params.requiredInterface = iface

            let nwHost = NWEndpoint.Host(host)
            let nwPort = NWEndpoint.Port(rawValue: portNumber)!
            let connection = NWConnection(host: nwHost, port: nwPort, using: params)

            final class NWState: @unchecked Sendable {
                var resumed = false
                var rawData = Data()
                var headerParsed = false
                var statusCode: Int = 0
                var headers: [String: String] = [:]
                var contentRange: String?
                var timer: DispatchSourceTimer?
            }
            let state = NWState()

            let timeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
            timeoutTimer.schedule(deadline: .now() + timeout)
            timeoutTimer.setEventHandler {
                if !state.resumed {
                    state.resumed = true
                    connection.cancel()
                    continuation.resume(throwing: PowerloadHTTPError.timeout)
                }
            }
            timeoutTimer.resume()
            state.timer = timeoutTimer

            func failOnce(_ err: Error) {
                if !state.resumed {
                    state.resumed = true
                    state.timer?.cancel()
                    connection.cancel()
                    continuation.resume(throwing: err)
                }
            }

            func readMore() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                    if let error = error {
                        failOnce(PowerloadHTTPError.connectionFailed(error.localizedDescription))
                        return
                    }

                    if let data = data, !data.isEmpty {
                        state.rawData.append(data)

                        if !state.headerParsed {
                            // Find CRLF CRLF delimiter
                            if let headerEndRange = state.rawData.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) {
                                let headerData = state.rawData.subdata(in: 0..<headerEndRange.lowerBound)
                                let bodyData = state.rawData.subdata(in: headerEndRange.upperBound..<state.rawData.count)
                                state.rawData = bodyData

                                let headerString = String(decoding: headerData, as: UTF8.self)
                                let (code, headers) = Self.parseHeaders(headerString)
                                state.statusCode = code
                                state.headers = headers
                                state.contentRange = headers["content-range"]
                                state.headerParsed = true

                                if code == 200 {
                                    failOnce(PowerloadHTTPError.rangeNotSupported(statusCode: 200))
                                    return
                                } else if code != 206 {
                                    failOnce(PowerloadHTTPError.invalidStatus(code))
                                    return
                                }
                            }
                        }
                    }

                    if state.headerParsed && state.rawData.count >= Int(expectedBytes) {
                        if !state.resumed {
                            state.resumed = true
                            state.timer?.cancel()
                            connection.cancel()
                            let finalData = state.rawData.prefix(Int(expectedBytes))
                            continuation.resume(returning: PowerloadHTTPResponse(
                                statusCode: state.statusCode,
                                headers: state.headers,
                                contentRange: state.contentRange,
                                data: Data(finalData)
                            ))
                        }
                        return
                    }

                    if isComplete {
                        if state.headerParsed && state.rawData.count == Int(expectedBytes) {
                            if !state.resumed {
                                state.resumed = true
                                state.timer?.cancel()
                                continuation.resume(returning: PowerloadHTTPResponse(
                                    statusCode: state.statusCode,
                                    headers: state.headers,
                                    contentRange: state.contentRange,
                                    data: state.rawData
                                ))
                            }
                        } else {
                            failOnce(PowerloadHTTPError.byteCountMismatch(expected: expectedBytes, received: Int64(state.rawData.count)))
                        }
                    } else {
                        readMore()
                    }
                }
            }

            connection.stateUpdateHandler = { connState in
                switch connState {
                case .ready:
                    var path = url.path
                    if path.isEmpty { path = "/" }
                    if let query = url.query { path += "?\(query)" }

                    var request = "GET \(path) HTTP/1.1\r\n"
                    request += "Host: \(host)\r\n"
                    request += "Range: bytes=\(rangeStart)-\(rangeEnd)\r\n"
                    request += "Accept-Encoding: identity\r\n"
                    request += "User-Agent: LiquidDynamo/2.0.5\r\n"
                    request += "Connection: close\r\n\r\n"

                    guard let reqData = request.data(using: .utf8) else {
                        failOnce(PowerloadHTTPError.invalidURL)
                        return
                    }

                    connection.send(content: reqData, completion: .contentProcessed({ sendErr in
                        if let sendErr = sendErr {
                            failOnce(PowerloadHTTPError.connectionFailed(sendErr.localizedDescription))
                        } else {
                            readMore()
                        }
                    }))
                case .failed(let err):
                    failOnce(PowerloadHTTPError.connectionFailed(err.localizedDescription))
                case .cancelled:
                    failOnce(PowerloadHTTPError.cancelled)
                default:
                    break
                }
            }

            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
    }

    // MARK: - Method C: /usr/bin/curl Fallback

    private func performCurlChunk(
        url: URL,
        bsdName: String,
        rangeStart: Int64,
        rangeEnd: Int64,
        expectedBytes: Int64,
        timeout: TimeInterval
    ) async throws -> PowerloadHTTPResponse {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let tempOut = FileManager.default.temporaryDirectory.appendingPathComponent("chunk_\(UUID().uuidString).bin")
                let tempHead = FileManager.default.temporaryDirectory.appendingPathComponent("head_\(UUID().uuidString).txt")
                defer {
                    try? FileManager.default.removeItem(at: tempOut)
                    try? FileManager.default.removeItem(at: tempHead)
                }

                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
                proc.arguments = [
                    "--interface", bsdName,
                    "-s", "-S",
                    "-r", "\(rangeStart)-\(rangeEnd)",
                    "--dump-header", tempHead.path,
                    "--max-time", "\(Int(timeout))",
                    "-o", tempOut.path,
                    url.absoluteString
                ]

                do {
                    try proc.run()
                    proc.waitUntilExit()

                    let headStr = (try? String(contentsOf: tempHead, encoding: .utf8)) ?? ""
                    let (statusCode, headers) = Self.parseHeaders(headStr)

                    if statusCode == 200 {
                        continuation.resume(throwing: PowerloadHTTPError.rangeNotSupported(statusCode: 200))
                        return
                    }

                    guard statusCode == 206 else {
                        continuation.resume(throwing: PowerloadHTTPError.invalidStatus(statusCode))
                        return
                    }

                    let data = (try? Data(contentsOf: tempOut)) ?? Data()
                    guard Int64(data.count) == expectedBytes else {
                        continuation.resume(throwing: PowerloadHTTPError.byteCountMismatch(expected: expectedBytes, received: Int64(data.count)))
                        return
                    }

                    continuation.resume(returning: PowerloadHTTPResponse(
                        statusCode: statusCode,
                        headers: headers,
                        contentRange: headers["content-range"],
                        data: data
                    ))
                } catch {
                    continuation.resume(throwing: PowerloadHTTPError.connectionFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Helpers

    public static func parseHeaders(_ headerString: String) -> (statusCode: Int, headers: [String: String]) {
        var statusCode = 0
        var headers: [String: String] = [:]

        let lines = headerString.components(separatedBy: "\r\n")
        for (idx, line) in lines.enumerated() {
            if idx == 0 {
                // HTTP/1.1 206 Partial Content
                let parts = line.components(separatedBy: " ")
                if parts.count >= 2, let code = Int(parts[1]) {
                    statusCode = code
                }
                continue
            }
            if let colonIdx = line.firstIndex(of: ":") {
                let key = line[..<colonIdx].trimmingCharacters(in: .whitespaces).lowercased()
                let val = line[line.index(after: colonIdx)...].trimmingCharacters(in: .whitespaces)
                headers[key] = val
            }
        }
        return (statusCode, headers)
    }
}
