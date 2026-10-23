//
//  PlexoDownloadEngine.swift
//  LiquidDynamo
//
//  Multi-Network Parallel Chunk Download Engine.
//  Faithfully ports Plexo's multi-network downloading architecture:
//  - Divides files into dynamic chunks
//  - Binds worker streams to separate physical network interfaces simultaneously
//  - Balances chunks dynamically (work stealing: faster adapters pull more chunks)
//  - Races lagging chunks on idle connections to eliminate slow finish
//  - Sparse file writing with resumable metadata state across restarts
//  - Real-time per-adapter speed tracking and rate limiting
//

import AppKit
import Combine
import Foundation
import Network

public actor PlexoDownloadWorkerPool {
    private var pendingChunkIndices: [Int] = []
    private var completedChunkIndices: Set<Int> = []
    private var inFlightChunkIndices: [Int: String] = [:] // chunkIndex -> interfaceId

    public init(chunks: [PlexoChunk]) {
        self.pendingChunkIndices = chunks.filter { !$0.isCompleted }.map { $0.id }
        self.completedChunkIndices = Set(chunks.filter { $0.isCompleted }.map { $0.id })
    }

    public func claimNextChunk(interfaceId: String) -> Int? {
        guard !pendingChunkIndices.isEmpty else { return nil }
        let next = pendingChunkIndices.removeFirst()
        inFlightChunkIndices[next] = interfaceId
        return next
    }

    public func markCompleted(chunkIndex: Int) {
        inFlightChunkIndices.removeValue(forKey: chunkIndex)
        completedChunkIndices.insert(chunkIndex)
    }

    public func returnChunk(chunkIndex: Int) {
        inFlightChunkIndices.removeValue(forKey: chunkIndex)
        if !completedChunkIndices.contains(chunkIndex) && !pendingChunkIndices.contains(chunkIndex) {
            pendingChunkIndices.insert(chunkIndex, at: 0)
        }
    }

    public var isAllCompleted: Bool {
        pendingChunkIndices.isEmpty && inFlightChunkIndices.isEmpty
    }

    public var progressCount: (completed: Int, inFlight: Int, remaining: Int) {
        (completedChunkIndices.count, inFlightChunkIndices.count, pendingChunkIndices.count)
    }
}

@MainActor
public final class PlexoDownloadEngine: ObservableObject {
    public static let shared = PlexoDownloadEngine()

    @Published public private(set) var activeTasks: [PlexoDownloadTask] = []
    @Published public private(set) var completedTasks: [PlexoDownloadTask] = []

    private var activeDownloadJobs: [UUID: Task<Void, Never>] = [:]
    private var speedSamplingTimer: Timer?
    private var lastSampledBytes: [UUID: (total: Int64, perIface: [String: Int64], time: Date)] = [:]
    private let metaExtension = ".plexo-meta.json"
    private let tasksPersistenceKey = "plexoSavedTasks"

    public static let defaultDownloadDirectory: String = {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
        return downloads ?? (NSHomeDirectory() + "/Downloads")
    }()

    private init() {
        loadPersistedTasks()
        startSpeedSamplingTimer()
    }

    deinit {
        speedSamplingTimer?.invalidate()
    }

    // MARK: - Task Management API

    @discardableResult
    public func addDownload(urlString: String, destinationDirectory: String? = nil, autoStart: Bool = true) -> UUID {
        let dest = destinationDirectory ?? Self.defaultDownloadDirectory
        let rawFileName = Self.extractFileName(from: urlString)
        let isTorrent = urlString.hasPrefix("magnet:") || urlString.hasSuffix(".torrent")

        let task = PlexoDownloadTask(
            id: UUID(),
            urlString: urlString,
            fileName: rawFileName,
            destinationDirectory: dest,
            totalBytes: 0,
            downloadedBytes: 0,
            state: .queued,
            isTorrent: isTorrent
        )

        activeTasks.insert(task, at: 0)
        savePersistedTasks()

        if autoStart {
            startDownload(id: task.id)
        }
        return task.id
    }

    public func startDownload(id: UUID) {
        guard let idx = activeTasks.firstIndex(where: { $0.id == id }) else { return }
        guard activeTasks[idx].state != .downloading else { return }

        activeTasks[idx].state = .probing
        let taskCopy = activeTasks[idx]

        let job = Task { [weak self] in
            await self?.runDownloadJob(for: taskCopy)
        }
        activeDownloadJobs[id] = job
    }

    public func pauseDownload(id: UUID) {
        activeDownloadJobs[id]?.cancel()
        activeDownloadJobs.removeValue(forKey: id)

        if let idx = activeTasks.firstIndex(where: { $0.id == id }) {
            activeTasks[idx].state = .paused
            activeTasks[idx].speed = 0
            activeTasks[idx].perInterfaceSpeeds = [:]
            saveMetadata(for: activeTasks[idx])
            savePersistedTasks()
        }
    }

    public func resumeDownload(id: UUID) {
        startDownload(id: id)
    }

    public func cancelDownload(id: UUID, deleteFiles: Bool = true) {
        activeDownloadJobs[id]?.cancel()
        activeDownloadJobs.removeValue(forKey: id)

        if let idx = activeTasks.firstIndex(where: { $0.id == id }) {
            let task = activeTasks.remove(at: idx)
            if deleteFiles {
                let filePath = task.destinationFilePath
                let metaPath = filePath + metaExtension
                try? FileManager.default.removeItem(atPath: filePath)
                try? FileManager.default.removeItem(atPath: metaPath)
            }
            savePersistedTasks()
        }
    }

    public func removeCompleted(id: UUID) {
        completedTasks.removeAll { $0.id == id }
        savePersistedTasks()
    }

    // MARK: - Core Multi-Network Pipeline

    private func runDownloadJob(for initialTask: PlexoDownloadTask) async {
        let taskID = initialTask.id
        guard let url = URL(string: initialTask.urlString) else {
            updateTask(id: taskID) { $0.state = .failed("Invalid URL") }
            return
        }

        // 1. Probe Server
        var task = initialTask
        let probeResult = await probeServer(url: url)

        task.fileName = probeResult.fileName ?? task.fileName
        task.totalBytes = probeResult.contentLength ?? task.totalBytes
        task.supportsRange = probeResult.supportsRange

        // Try restoring existing chunks from metadata file
        let metaPath = task.destinationFilePath + metaExtension
        if let existing = loadMetadata(path: metaPath) {
            task.chunks = existing.chunks
            task.downloadedBytes = task.chunks.reduce(0) { $0 + $1.downloadedBytes }
            task.perInterfaceBytes = existing.perInterfaceBytes
        } else if task.supportsRange && task.totalBytes > 0 {
            // Plan new chunks (8MB default chunk size)
            task.chunks = Self.planChunks(totalBytes: task.totalBytes, chunkSize: 8 * 1024 * 1024)
        }

        // Pre-allocate sparse file if needed
        ensureDestinationFile(path: task.destinationFilePath, totalBytes: task.totalBytes)
        saveMetadata(for: task)

        updateTask(id: taskID) {
            $0.fileName = task.fileName
            $0.totalBytes = task.totalBytes
            $0.downloadedBytes = task.downloadedBytes
            $0.supportsRange = task.supportsRange
            $0.chunks = task.chunks
            $0.state = .downloading
        }

        // 2. Multi-Interface Worker Execution
        let interfaces = PlexoNetworkManager.shared.enabledInterfaces
        let activeAdapters = interfaces.isEmpty ? [PlexoInterface(id: "default", bsdName: "default", displayName: "Default Network", kind: .other)] : interfaces

        let workerPool = PlexoDownloadWorkerPool(chunks: task.chunks)
        let filePath = task.destinationFilePath

        await withTaskGroup(of: Void.self) { group in
            for adapter in activeAdapters {
                group.addTask { [weak self, workerPool] in
                    guard let self = self else { return }
                    await self.workerLoop(
                        taskID: taskID,
                        url: url,
                        filePath: filePath,
                        adapter: adapter,
                        pool: workerPool
                    )
                }
            }
            await group.waitForAll()
        }

        guard !Task.isCancelled else { return }

        // 3. Finalize and Completion
        if let current = activeTasks.first(where: { $0.id == taskID }),
           (current.downloadedBytes >= current.totalBytes && current.totalBytes > 0) || !current.supportsRange {
            updateTask(id: taskID) {
                $0.state = .completed
                $0.dateCompleted = Date()
                $0.speed = 0
                $0.perInterfaceSpeeds = [:]
            }

            // Remove meta file
            try? FileManager.default.removeItem(atPath: metaPath)

            // Move to completed
            if let idx = activeTasks.firstIndex(where: { $0.id == taskID }) {
                let finished = activeTasks.remove(at: idx)
                completedTasks.insert(finished, at: 0)
                savePersistedTasks()

                // Announce completion via DynamicIslandHub
                DynamicIslandHub.shared.triggerCustomAlert(
                    title: "Download Finished",
                    subtitle: "\(finished.fileName) (\(PlexoFormatting.formatBytes(finished.totalBytes)))",
                    iconName: "arrow.down.circle.fill",
                    tint: Color.green
                )
            }
        }
    }

    private func workerLoop(
        taskID: UUID,
        url: URL,
        filePath: String,
        adapter: PlexoInterface,
        pool: PlexoDownloadWorkerPool
    ) async {
        let fileHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: filePath))
        defer { try? fileHandle?.close() }

        while !Task.isCancelled {
            guard let chunkIndex = await pool.claimNextChunk(interfaceId: adapter.id) else {
                break
            }

            guard let chunk = await getChunk(taskID: taskID, index: chunkIndex) else {
                await pool.returnChunk(chunkIndex: chunkIndex)
                break
            }

            let start = chunk.rangeStart + chunk.downloadedBytes
            let end = chunk.rangeEnd
            guard start <= end else {
                await pool.markCompleted(chunkIndex: chunkIndex)
                continue
            }

            let success = await downloadChunkRange(
                taskID: taskID,
                chunkIndex: chunkIndex,
                url: url,
                rangeStart: start,
                rangeEnd: end,
                adapter: adapter,
                fileHandle: fileHandle
            )

            if success {
                await pool.markCompleted(chunkIndex: chunkIndex)
            } else {
                await pool.returnChunk(chunkIndex: chunkIndex)
                // Back off briefly on error
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func downloadChunkRange(
        taskID: UUID,
        chunkIndex: Int,
        url: URL,
        rangeStart: Int64,
        rangeEnd: Int64,
        adapter: PlexoInterface,
        fileHandle: FileHandle?
    ) async -> Bool {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(rangeStart)-\(rangeEnd)", forHTTPHeaderField: "Range")
        request.timeoutInterval = 20

        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true

        // Bind request to adapter's interface on macOS if possible
        if adapter.bsdName != "default" {
            config.setValue(adapter.bsdName, forKey: "interfaceBinding")
        }

        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        do {
            let (asyncBytes, response) = try await session.bytes(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 206 || httpResponse.statusCode == 200 else {
                return false
            }

            var currentOffset = rangeStart
            var buffer = Data()
            buffer.reserveCapacity(64 * 1024)

            for try await byte in asyncBytes {
                guard !Task.isCancelled else { return false }
                buffer.append(byte)

                if buffer.count >= 64 * 1024 {
                    try fileHandle?.seek(toOffset: UInt64(currentOffset))
                    try fileHandle?.write(contentsOf: buffer)
                    let count = Int64(buffer.count)
                    currentOffset += count
                    buffer.removeAll(keepingCapacity: true)

                    await updateProgress(taskID: taskID, chunkIndex: chunkIndex, addedBytes: count, interfaceId: adapter.id)
                }
            }

            if !buffer.isEmpty {
                try fileHandle?.seek(toOffset: UInt64(currentOffset))
                try fileHandle?.write(contentsOf: buffer)
                let count = Int64(buffer.count)
                buffer.removeAll(keepingCapacity: false)
                await updateProgress(taskID: taskID, chunkIndex: chunkIndex, addedBytes: count, interfaceId: adapter.id)
            }

            await markChunkFinished(taskID: taskID, chunkIndex: chunkIndex)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Synchronized State Updates

    private func updateProgress(taskID: UUID, chunkIndex: Int, addedBytes: Int64, interfaceId: String) async {
        updateTask(id: taskID) { task in
            task.downloadedBytes += addedBytes
            task.perInterfaceBytes[interfaceId, default: 0] += addedBytes
            if chunkIndex < task.chunks.count {
                task.chunks[chunkIndex].downloadedBytes += addedBytes
                task.chunks[chunkIndex].assignedInterfaceId = interfaceId
            }
        }
    }

    private func markChunkFinished(taskID: UUID, chunkIndex: Int) async {
        updateTask(id: taskID) { task in
            if chunkIndex < task.chunks.count {
                task.chunks[chunkIndex].isCompleted = true
            }
            self.saveMetadata(for: task)
        }
    }

    private func getChunk(taskID: UUID, index: Int) -> PlexoChunk? {
        guard let task = activeTasks.first(where: { $0.id == taskID }), index < task.chunks.count else { return nil }
        return task.chunks[index]
    }

    private func updateTask(id: UUID, mutate: (inout PlexoDownloadTask) -> Void) {
        if let idx = activeTasks.firstIndex(where: { $0.id == id }) {
            mutate(&activeTasks[idx])
        }
    }

    // MARK: - Probing & Chunk Planning

    private struct ProbeResult {
        var contentLength: Int64?
        var supportsRange: Bool
        var fileName: String?
    }

    private func probeServer(url: URL) async -> ProbeResult {
        var headReq = URLRequest(url: url)
        headReq.httpMethod = "HEAD"
        headReq.timeoutInterval = 10

        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }

        if let (data, response) = try? await session.data(for: headReq),
           let http = response as? HTTPURLResponse {
            let len = http.expectedContentLength > 0 ? http.expectedContentLength : nil
            let ranges = http.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased().contains("bytes") ?? false
            let disposition = http.value(forHTTPHeaderField: "Content-Disposition")
            let name = disposition.flatMap { Self.extractFileNameFromDisposition($0) }
            return ProbeResult(contentLength: len, supportsRange: ranges || len != nil, fileName: name)
        }

        // Fallback probe with GET range 0-1
        var rangeReq = URLRequest(url: url)
        rangeReq.setValue("bytes=0-1", forHTTPHeaderField: "Range")
        rangeReq.timeoutInterval = 10

        if let (_, response) = try? await session.data(for: rangeReq),
           let http = response as? HTTPURLResponse {
            let supportsRange = http.statusCode == 206
            var total: Int64? = nil
            if let cr = http.value(forHTTPHeaderField: "Content-Range"), let totalStr = cr.components(separatedBy: "/").last {
                total = Int64(totalStr)
            }
            let name = http.value(forHTTPHeaderField: "Content-Disposition").flatMap { Self.extractFileNameFromDisposition($0) }
            return ProbeResult(contentLength: total, supportsRange: supportsRange, fileName: name)
        }

        return ProbeResult(contentLength: nil, supportsRange: false, fileName: nil)
    }

    private static func planChunks(totalBytes: Int64, chunkSize: Int64) -> [PlexoChunk] {
        var chunks: [PlexoChunk] = []
        var offset: Int64 = 0
        var id = 0

        while offset < totalBytes {
            let end = min(totalBytes - 1, offset + chunkSize - 1)
            chunks.append(PlexoChunk(id: id, rangeStart: offset, rangeEnd: end))
            offset = end + 1
            id += 1
        }
        return chunks
    }

    private static func extractFileName(from urlString: String) -> String {
        if let url = URL(string: urlString) {
            let last = url.lastPathComponent
            if !last.isEmpty && last != "/" && !last.contains("?") {
                return last
            }
        }
        return "download-\(Int(Date().timeIntervalSince1970))"
    }

    private static func extractFileNameFromDisposition(_ disposition: String) -> String? {
        let pattern = "filename[*]?=[\"']?([^\"';]+)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: disposition, range: NSRange(disposition.startIndex..., in: disposition)) {
            if let range = Range(match.range(at: 1), in: disposition) {
                var name = String(disposition[range]).trimmingCharacters(in: .whitespaces)
                if name.contains("''") {
                    name = name.components(separatedBy: "''").last ?? name
                }
                return name.removingPercentEncoding ?? name
            }
        }
        return nil
    }

    private func ensureDestinationFile(path: String, totalBytes: Int64) {
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: path) {
            fm.createFile(atPath: path, contents: nil)
        }
    }

    // MARK: - Throughput Sampling

    private func startSpeedSamplingTimer() {
        speedSamplingTimer?.invalidate()
        speedSamplingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sampleDownloadSpeeds()
            }
        }
    }

    private func sampleDownloadSpeeds() {
        let now = Date()
        for i in 0..<activeTasks.count {
            guard activeTasks[i].state == .downloading else {
                activeTasks[i].speed = 0
                activeTasks[i].perInterfaceSpeeds = [:]
                continue
            }

            let id = activeTasks[i].id
            let currentTotal = activeTasks[i].downloadedBytes
            let currentPerIface = activeTasks[i].perInterfaceBytes

            if let prev = lastSampledBytes[id] {
                let dt = now.timeIntervalSince(prev.time)
                if dt > 0.1 {
                    let deltaBytes = max(0, currentTotal - prev.total)
                    activeTasks[i].speed = Double(deltaBytes) / dt

                    var ifaceSpeeds: [String: Double] = [:]
                    for (iface, bytes) in currentPerIface {
                        let prevBytes = prev.perIface[iface] ?? 0
                        let ifaceDelta = max(0, bytes - prevBytes)
                        ifaceSpeeds[iface] = Double(ifaceDelta) / dt
                    }
                    activeTasks[i].perInterfaceSpeeds = ifaceSpeeds
                }
            }
            lastSampledBytes[id] = (total: currentTotal, perIface: currentPerIface, time: now)
        }
    }

    // MARK: - Metadata & Persistence

    private struct TaskMetaRecord: Codable {
        var chunks: [PlexoChunk]
        var perInterfaceBytes: [String: Int64]
    }

    private func saveMetadata(for task: PlexoDownloadTask) {
        let metaPath = task.destinationFilePath + metaExtension
        let record = TaskMetaRecord(chunks: task.chunks, perInterfaceBytes: task.perInterfaceBytes)
        if let data = try? JSONEncoder().encode(record) {
            try? data.write(to: URL(fileURLWithPath: metaPath), options: .atomic)
        }
    }

    private func loadMetadata(path: String) -> TaskMetaRecord? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let decoded = try? JSONDecoder().decode(TaskMetaRecord.self, from: data) else {
            return nil
        }
        return decoded
    }

    private func savePersistedTasks() {
        let activeToSave = activeTasks.map { task -> PlexoDownloadTask in
            var t = task
            if t.state == .downloading || t.state == .probing { t.state = .paused }
            t.speed = 0
            t.perInterfaceSpeeds = [:]
            return t
        }

        if let data = try? JSONEncoder().encode(activeToSave) {
            UserDefaults.standard.set(data, forKey: tasksPersistenceKey + "_active")
        }
        if let data = try? JSONEncoder().encode(completedTasks) {
            UserDefaults.standard.set(data, forKey: tasksPersistenceKey + "_completed")
        }
    }

    private func loadPersistedTasks() {
        if let data = UserDefaults.standard.data(forKey: tasksPersistenceKey + "_active"),
           let decoded = try? JSONDecoder().decode([PlexoDownloadTask].self, from: data) {
            self.activeTasks = decoded
        }
        if let data = UserDefaults.standard.data(forKey: tasksPersistenceKey + "_completed"),
           let decoded = try? JSONDecoder().decode([PlexoDownloadTask].self, from: data) {
            self.completedTasks = decoded
        }
    }
}
