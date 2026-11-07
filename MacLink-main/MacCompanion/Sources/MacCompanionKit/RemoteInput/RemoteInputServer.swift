// SPDX-License-Identifier: MIT
import Foundation
import Network

public protocol RemoteInputServerDelegate: AnyObject, Sendable {
    func serverDidStart(port: UInt16)
    func clientDidConnect(endpoint: String)
    func clientDidDisconnect(endpoint: String)
    func didReceiveEvent(_ event: TouchpadEnvelope)
    func serverDidFail(error: String)
}

public final class RemoteInputServer: @unchecked Sendable {
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private let queue = DispatchQueue(label: "app.maclink.touchpad.server", qos: .userInteractive)

    public let inputController = RemoteInputController()
    public let sessionManager = SessionManager()
    private let sequenceManager = SequenceManager()

    public weak var delegate: RemoteInputServerDelegate?

    public private(set) var port: UInt16 = 52400
    public private(set) var isRunning: Bool = false

    public init(port: UInt16 = 52400) {
        self.port = port
    }

    public func start() {
        guard !isRunning else { return }

        do {
            let parameters = NWParameters.tcp
            let wsOptions = NWProtocolWebSocket.Options()
            wsOptions.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)

            guard let nwPort = NWEndpoint.Port(rawValue: port) else { return }
            let newListener = try NWListener(using: parameters, on: nwPort)

            // Bonjour advertisement
            let deviceName = Host.current().localizedName ?? "Mac"
            newListener.service = NWListener.Service(
                name: deviceName,
                type: "_maclink-touchpad._tcp",
                domain: "local.",
                txtRecord: "v=1".data(using: .utf8)
            )

            newListener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isRunning = true
                    self.delegate?.serverDidStart(port: self.port)
                case .failed(let err):
                    self.stop()
                    self.delegate?.serverDidFail(error: err.localizedDescription)
                default:
                    break
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }

            newListener.start(queue: queue)
            self.listener = newListener
        } catch {
            delegate?.serverDidFail(error: error.localizedDescription)
        }
    }

    private func handleNewConnection(_ connection: NWConnection) {
        // Enforce single active remote-controller policy
        if activeConnection != nil {
            connection.cancel()
            return
        }

        activeConnection = connection
        sequenceManager.reset()

        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.delegate?.clientDidConnect(endpoint: connection.endpoint.debugDescription)
                self.receiveNextMessage(from: connection)
            case .failed, .cancelled:
                self.handleDisconnection(connection)
            default:
                break
            }
        }

        connection.start(queue: queue)
    }

    private func receiveNextMessage(from connection: NWConnection) {
        connection.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self else { return }

            if let data = content, let envelope = try? JSONDecoder().decode(TouchpadEnvelope.self, from: data) {
                self.processEnvelope(envelope, on: connection)
            }

            if error == nil && self.activeConnection === connection {
                self.receiveNextMessage(from: connection)
            } else if error != nil {
                self.handleDisconnection(connection)
            }
        }
    }

    private func processEnvelope(_ envelope: TouchpadEnvelope, on connection: NWConnection) {
        let validation = EventValidator.validateEnvelope(envelope, sequenceManager: sequenceManager)
        guard case .success(let validEnvelope) = validation else {
            return
        }

        delegate?.didReceiveEvent(validEnvelope)

        switch validEnvelope.eventType {
        case .pointerMove:
            if let move = EventValidator.extractPointerMove(validEnvelope) {
                inputController.handlePointerMove(deltaX: move.deltaX, deltaY: move.deltaY)
            }
        case .leftClick:
            let clicks = validEnvelope.payload["clicks"]?.asInt ?? 1
            inputController.handleLeftClick(clicks: clicks)
        case .rightClick:
            inputController.handleRightClick()
        case .doubleClick:
            inputController.handleLeftClick(clicks: 2)
        case .pointerDown:
            let btnStr = validEnvelope.payload["button"]?.asString ?? "left"
            let btn = PointerButtonPayload.Button(rawValue: btnStr) ?? .left
            inputController.handlePointerDown(button: btn)
        case .pointerUp:
            let btnStr = validEnvelope.payload["button"]?.asString ?? "left"
            let btn = PointerButtonPayload.Button(rawValue: btnStr) ?? .left
            inputController.handlePointerUp(button: btn)
        case .scroll:
            if let scroll = EventValidator.extractScroll(validEnvelope) {
                inputController.handleScroll(deltaX: scroll.deltaX, deltaY: scroll.deltaY, isContinuous: scroll.isContinuous)
            }
        case .swipe:
            let dirStr = validEnvelope.payload["direction"]?.asString ?? "up"
            let dir = SwipePayload.Direction(rawValue: dirStr) ?? .up
            let fingers = validEnvelope.payload["fingers"]?.asInt ?? 3
            inputController.handleSwipe(direction: dir, fingers: fingers)
        case .connectionPing:
            let pingTs = validEnvelope.payload["timestamp"]?.asInt ?? 0
            sendPong(pingTs: UInt64(pingTs), on: connection)
        default:
            break
        }
    }

    private func sendPong(pingTs: UInt64, on connection: NWConnection) {
        let pong = TouchpadEnvelope(
            version: 1,
            sessionId: "pong",
            sequence: sequenceManager.currentSequence + 1,
            eventType: .connectionPong,
            payload: [
                "pingTimestamp": AnyCodableValue(.int(Int(pingTs))),
                "pongTimestamp": AnyCodableValue(.int(Int(Date().timeIntervalSince1970 * 1000)))
            ]
        )
        if let data = try? JSONEncoder().encode(pong) {
            let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
            let context = NWConnection.ContentContext(identifier: "pong", metadata: [metadata])
            connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
        }
    }

    private func handleDisconnection(_ connection: NWConnection) {
        // Crucial fail-safe input cleanup on connection drop
        inputController.emergencyInputCleanup()

        if activeConnection === connection {
            activeConnection = nil
            delegate?.clientDidDisconnect(endpoint: connection.endpoint.debugDescription)
        }
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        if let conn = activeConnection {
            handleDisconnection(conn)
            conn.cancel()
        }
        isRunning = false
    }
}

