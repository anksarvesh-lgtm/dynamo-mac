import AppKit
import AVFoundation
import Foundation
import Speech

final class TeleprompterSpeechRecognizer: ObservableObject {
    @Published var recognizedCharCount: Int = 0
    @Published var isListening: Bool = false
    @Published var error: String?
    @Published var audioLevels: [CGFloat] = Array(repeating: 0, count: 30)
    @Published var inputLevel: CGFloat = 0
    @Published var lastSpokenText: String = ""
    @Published var matchConfidenceLabel: String = ""

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var sourceText = ""
    private var sourceDisplayOffsets = TeleprompterTextTokenizer.SpeechMatchingText.empty
    private var recognizedSourceOffset = 0
    private var matchStartOffset = 0
    private var retryCount = 0
    private let maxRetries = 8
    private var restartWorkItem: DispatchWorkItem?
    private var preemptiveRestartTimer: Timer?
    private var recentMatchPositions: [Int] = []
    private var requestLock = NSLock()

    private struct SourceToken {
        let text: String
        let startOffset: Int
        let endOffset: Int
    }

    var isSpeaking: Bool {
        let recent = audioLevels.suffix(10)
        guard !recent.isEmpty else { return false }
        return recent.reduce(0, +) / CGFloat(recent.count) > 0.025
    }

    func start(with text: String, localeIdentifier: String) {
        cleanupRecognition()

        let matchingText = TeleprompterTextTokenizer.speechMatchingText(from: text)
        sourceText = matchingText.text
        sourceDisplayOffsets = matchingText
        recognizedSourceOffset = 0
        recognizedCharCount = 0
        matchStartOffset = 0
        retryCount = 0
        recentMatchPositions = []
        error = nil
        lastSpokenText = ""
        matchConfidenceLabel = ""

        guard !sourceText.isEmpty else { return }

        guard PermissionsManager.shared.checkMicrophone() else {
            error = "Microphone access is required for Word Tracking."
            PermissionsManager.shared.requestTeleprompterWordTrackingAccess()
            return
        }

        guard PermissionsManager.shared.checkSpeechRecognition() else {
            error = "Speech Recognition access is required for Word Tracking."
            PermissionsManager.shared.requestTeleprompterWordTrackingAccess()
            return
        }

        beginRecognition(localeIdentifier: localeIdentifier)
    }

    func stop() {
        isListening = false
        cleanupRecognition()
    }

    func reset() {
        stop()
        sourceText = ""
        recognizedCharCount = 0
        recognizedSourceOffset = 0
        sourceDisplayOffsets = .empty
        matchStartOffset = 0
        recentMatchPositions = []
        audioLevels = Array(repeating: 0, count: 30)
        inputLevel = 0
        lastSpokenText = ""
        matchConfidenceLabel = ""
        error = nil
    }

    private func beginRecognition(localeIdentifier: String) {
        cleanupRecognition()
        audioEngine = AVAudioEngine()

        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: localeIdentifier))
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            error = "Speech recognizer is not available for the selected language."
            isListening = false
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        if #available(macOS 13.0, *) {
            request.addsPunctuation = false
        }
        request.contextualStrings = contextualStrings()
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 else {
            scheduleRestart(localeIdentifier: localeIdentifier, after: 0.5)
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 512, format: hardwareFormat) { [weak self] buffer, _ in
            self?.append(buffer)
            self?.recordAudioLevel(from: buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                DispatchQueue.main.async {
                    self.retryCount = 0
                    let spoken = result.bestTranscription.formattedString
                    self.lastSpokenText = spoken
                    self.matchCharacters(spoken: spoken)
                }
            }

            if let error {
                DispatchQueue.main.async {
                    guard self.recognitionRequest != nil, self.isListening, !self.sourceText.isEmpty else {
                        self.isListening = false
                        return
                    }

                    self.matchStartOffset = self.recognizedSourceOffset
                    let nsError = error as NSError
                    let isTimeout = nsError.code == 1110 || nsError.code == 216
                    if isTimeout {
                        self.retryCount = 0
                        self.restartTask(localeIdentifier: localeIdentifier)
                    } else if self.retryCount < self.maxRetries {
                        self.retryCount += 1
                        self.scheduleRestart(localeIdentifier: localeIdentifier, after: min(Double(self.retryCount) * 0.4, 1.5))
                    } else {
                        self.error = "Speech recognition stopped unexpectedly."
                        self.isListening = false
                    }
                }
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            startPreemptiveRestart(localeIdentifier: localeIdentifier)
        } catch {
            self.error = "Audio engine failed: \(error.localizedDescription)"
            isListening = false
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        requestLock.lock()
        recognitionRequest?.append(buffer)
        requestLock.unlock()
    }

    private func recordAudioLevel(from buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<frameLength {
            sum += channelData[i] * channelData[i]
        }
        let rms = sqrt(sum / Float(max(frameLength, 1)))
        let level = CGFloat(min(rms * 18, 1.0))

        DispatchQueue.main.async {
            self.inputLevel = level
            self.audioLevels.append(level)
            if self.audioLevels.count > 30 {
                self.audioLevels.removeFirst()
            }
        }
    }

    private func restartTask(localeIdentifier: String) {
        guard isListening else { return }
        matchStartOffset = recognizedSourceOffset
        recentMatchPositions = []
        cleanupRecognitionTask()
        scheduleRestart(localeIdentifier: localeIdentifier, after: 0.1)
    }

    private func scheduleRestart(localeIdentifier: String, after delay: TimeInterval) {
        guard retryCount <= maxRetries else { return }
        restartWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.restartWorkItem = nil
            self?.beginRecognition(localeIdentifier: localeIdentifier)
        }
        restartWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func startPreemptiveRestart(localeIdentifier: String) {
        preemptiveRestartTimer?.invalidate()
        preemptiveRestartTimer = Timer.scheduledTimer(withTimeInterval: 55.0, repeats: true) { [weak self] _ in
            guard let self, self.isListening, !self.sourceText.isEmpty else { return }
            self.restartTask(localeIdentifier: localeIdentifier)
        }
    }

    private func cleanupRecognitionTask() {
        restartWorkItem?.cancel()
        restartWorkItem = nil
        preemptiveRestartTimer?.invalidate()
        preemptiveRestartTimer = nil

        requestLock.lock()
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        requestLock.unlock()

        recognitionTask?.cancel()
        recognitionTask = nil
    }

    private func cleanupRecognition() {
        cleanupRecognitionTask()
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func contextualStrings() -> [String] {
        let upcoming = String(sourceText.dropFirst(matchStartOffset))
        let words = upcoming.split(whereSeparator: { $0.isWhitespace })
            .filter { !Self.containsCJK(String($0)) }
            .map { $0.lowercased().filter { $0.isLetter || $0.isNumber } }
            .filter { $0.count >= 5 }

        var hints: [String] = []
        func add(_ value: String) {
            guard value.count >= 2, !hints.contains(value) else { return }
            hints.append(value)
        }

        words.prefix(50).forEach(add)

        let upcomingWords = upcoming.split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !Self.containsCJK($0) }
        for index in upcomingWords.indices.prefix(24) {
            let twoWordPhrase = upcomingWords[index...].prefix(2).joined(separator: " ")
            add(twoWordPhrase)
            let threeWordPhrase = upcomingWords[index...].prefix(3).joined(separator: " ")
            add(threeWordPhrase)
        }

        let dense = Self.significantText(upcoming)
        if Self.containsCJK(upcoming), dense.count >= 2 {
            let denseChars = Array(dense)
            for length in [2, 3, 4, 6] where denseChars.count >= length {
                add(String(denseChars.prefix(length)))
            }

            let searchLimit = min(denseChars.count, 48)
            for start in stride(from: 0, to: searchLimit, by: 2) {
                for length in [2, 3, 4] {
                    let end = start + length
                    guard end <= denseChars.count else { continue }
                    add(String(denseChars[start..<end]))
                }
            }
        } else if dense.count >= 4 {
            let denseChars = Array(dense)
            for length in [4, 6, 8, 12] where denseChars.count >= length {
                add(String(denseChars.prefix(length)))
            }
            for start in stride(from: 0, to: min(denseChars.count, 80), by: 4) {
                let end = min(start + 8, denseChars.count)
                guard end - start >= 4 else { continue }
                add(String(denseChars[start..<end]))
            }
        }

        return Array(hints.prefix(80))
    }

    private func matchCharacters(spoken: String) {
        let charResult = charLevelMatch(spoken: spoken)
        let wordResult = wordLevelMatch(spoken: spoken)
        let phraseResult = recentPhraseMatch(spoken: spoken)
        let fuzzyResult = fuzzyWindowMatch(spoken: spoken)
        let cjkResult = Self.containsCJK(spoken)
            || Self.containsCJK(String(sourceText.dropFirst(matchStartOffset).prefix(80)))
        let tolerance = cjkResult ? 3 : 20
        var best: Int
        if charResult == 0 {
            best = wordResult
        } else if wordResult == 0 {
            // CJK transcripts often arrive without spaces while the display
            // text is split into character tokens, so word-level matching can
            // be zero even when character matching is correct.
            best = charResult
        } else if abs(charResult - wordResult) <= tolerance {
            best = (charResult + wordResult) / 2
        } else {
            best = min(charResult, wordResult)
        }

        if phraseResult > best {
            let candidate = matchStartOffset + phraseResult
            let step = candidate - recognizedSourceOffset
            if best == 0 || step <= 90 {
                best = phraseResult
            }
        }

        if let fuzzyResult, fuzzyResult.offset > best {
            let candidate = matchStartOffset + fuzzyResult.offset
            let step = candidate - recognizedSourceOffset
            if fuzzyResult.confidence >= 0.82 || best == 0 || step <= 72 {
                best = fuzzyResult.offset
            }
        }

        var candidate = min(matchStartOffset + best, sourceText.count)
        var step = candidate - recognizedSourceOffset
        let cjkStep = cjkResult || Self.containsCJK(String(sourceText.dropFirst(recognizedSourceOffset).prefix(max(step, 1))))
        if cjkStep, step > 10 {
            candidate = min(candidate, recognizedSourceOffset + 6)
            step = candidate - recognizedSourceOffset
        }

        guard candidate > recognizedSourceOffset else {
            matchConfidenceLabel = recognizedSourceOffset > 0
                ? "Matched \(progressLabel(for: recognizedSourceOffset))"
                : "No script match"
            return
        }

        recentMatchPositions.append(candidate)
        if recentMatchPositions.count > 3 {
            recentMatchPositions.removeFirst()
        }

        let agreementThreshold = 10
        let agreeCount = recentMatchPositions.filter { abs($0 - candidate) <= agreementThreshold }.count
        let confirmed = recentMatchPositions.count >= 2 && agreeCount >= 2
        let smallStep = step <= (cjkStep ? 6 : 36)
        let responsiveStep = step <= (cjkStep ? 8 : 72) && inputLevel > 0.006 && !lastSpokenText.isEmpty
        let confirmedStep = confirmed && (!cjkStep || step <= 8)

        if confirmedStep || smallStep || responsiveStep {
            recognizedSourceOffset = candidate
            recognizedCharCount = sourceDisplayOffsets.displayOffset(forSpeechOffset: candidate)
            matchConfidenceLabel = step > 72
                ? "Confirmed \(progressLabel(for: candidate))"
                : "Matched \(progressLabel(for: candidate))"
        } else {
            matchConfidenceLabel = "Weak match"
        }
    }

    private func recentPhraseMatch(spoken: String) -> Int {
        let spokenChars = Array(Self.significantText(spoken).suffix(72))
        guard spokenChars.count >= 2 else { return 0 }

        let consumedFromMatchStart = max(0, recognizedSourceOffset - matchStartOffset)
        let sourceBase = max(0, consumedFromMatchStart - 40)
        let sourceStart = matchStartOffset + sourceBase
        guard sourceStart < sourceText.count else { return 0 }

        let sourceSlice = Array(sourceText.dropFirst(sourceStart).lowercased())
        let sourceChars = significantCharacters(in: sourceSlice)
        guard !sourceChars.isEmpty else { return 0 }

        let maxStart = min(max(0, sourceChars.count - 1), 160)
        var bestScore = Double.leastNonzeroMagnitude
        var bestOffset = 0

        for start in 0...maxStart {
            var spokenIndex = 0
            var sourceIndex = start
            var lastOffset = 0
            let firstOffset = sourceChars[start].offsetAfter

            while sourceIndex < sourceChars.count && spokenIndex < spokenChars.count {
                if sourceIndex - start > 160 { break }
                if sourceChars[sourceIndex].char == spokenChars[spokenIndex] {
                    lastOffset = sourceChars[sourceIndex].offsetAfter
                    spokenIndex += 1
                }
                sourceIndex += 1
            }

            let matched = spokenIndex
            let requiredMatches = min(5, spokenChars.count)
            let ratio = Double(matched) / Double(spokenChars.count)
            let requiredRatio = spokenChars.count <= 4 ? 0.75 : 0.68
            guard matched >= requiredMatches, ratio >= requiredRatio else { continue }

            let spanPenalty = Double(max(0, lastOffset - firstOffset - matched)) / 220.0
            let startPenalty = Double(start) / 600.0
            let score = ratio - spanPenalty - startPenalty
            if score > bestScore {
                bestScore = score
                bestOffset = lastOffset
            }
        }

        return bestOffset == 0 ? 0 : sourceBase + bestOffset
    }

    private func fuzzyWindowMatch(spoken: String) -> (offset: Int, confidence: Double)? {
        let spokenDense = Array(Self.significantText(spoken).suffix(52))
        guard spokenDense.count >= 3 else { return nil }

        let consumedFromMatchStart = max(0, recognizedSourceOffset - matchStartOffset)
        let sourceBase = max(0, consumedFromMatchStart - 32)
        let sourceStart = matchStartOffset + sourceBase
        guard sourceStart < sourceText.count else { return nil }

        let sourceSlice = Array(sourceText.dropFirst(sourceStart).lowercased())
        let sourceChars = significantCharacters(in: sourceSlice)
        guard sourceChars.count >= 3 else { return nil }

        let candidateLengths = [22, 16, 10, 6, 4]
            .map { min($0, spokenDense.count) }
            .filter { $0 >= 3 }
            .reduce(into: [Int]()) { lengths, length in
                if !lengths.contains(length) { lengths.append(length) }
            }

        var bestScore = Double.leastNonzeroMagnitude
        var bestConfidence = 0.0
        var bestOffset = 0
        let searchLimit = min(sourceChars.count, 220)

        for targetLength in candidateLengths {
            let target = String(spokenDense.suffix(targetLength))
            let minWindow = max(2, targetLength - 2)
            let maxWindow = min(sourceChars.count, targetLength + 2)
            guard minWindow <= maxWindow else { continue }

            for start in 0..<searchLimit {
                for windowLength in minWindow...maxWindow {
                    let end = start + windowLength
                    guard end <= sourceChars.count else { break }

                    let segment = String(sourceChars[start..<end].map { $0.char })
                    let distance = editDistance(segment, target)
                    let longest = max(segment.count, target.count)
                    let confidence = 1.0 - (Double(distance) / Double(max(longest, 1)))
                    let requiredConfidence = targetLength <= 5 ? 0.72 : 0.66
                    let maxDistance = max(1, targetLength / 3)
                    guard confidence >= requiredConfidence, distance <= maxDistance else { continue }

                    let startPenalty = Double(start) / 520.0
                    let lengthBonus = Double(targetLength) / 240.0
                    let score = confidence + lengthBonus - startPenalty
                    if score > bestScore {
                        bestScore = score
                        bestConfidence = confidence
                        bestOffset = sourceBase + sourceChars[end - 1].offsetAfter
                    }
                }
            }
        }

        guard bestOffset > 0 else { return nil }
        return (bestOffset, bestConfidence)
    }

    private func charLevelMatch(spoken: String) -> Int {
        let remainingSource = String(sourceText.dropFirst(matchStartOffset))
        let source = Array(remainingSource.lowercased())
        let spokenChars = Array(Self.normalize(spoken))
        var sourceIndex = 0
        var spokenIndex = 0
        var lastGoodIndex = 0

        while sourceIndex < source.count && spokenIndex < spokenChars.count {
            let sourceChar = source[sourceIndex]
            let spokenChar = spokenChars[spokenIndex]

            if !sourceChar.isLetter && !sourceChar.isNumber {
                sourceIndex += 1
                continue
            }
            if !spokenChar.isLetter && !spokenChar.isNumber {
                spokenIndex += 1
                continue
            }

            if sourceChar == spokenChar {
                sourceIndex += 1
                spokenIndex += 1
                lastGoodIndex = sourceIndex
                continue
            }

            var resynced = false
            let spokenSkip = min(3, spokenChars.count - spokenIndex - 1)
            if spokenSkip >= 1 {
                for skip in 1...spokenSkip where spokenChars[spokenIndex + skip] == sourceChar {
                    spokenIndex += skip
                    resynced = true
                    break
                }
            }
            if resynced { continue }

            let sourceSkip = min(3, source.count - sourceIndex - 1)
            if sourceSkip >= 1 {
                for skip in 1...sourceSkip where source[sourceIndex + skip] == spokenChar {
                    sourceIndex += skip
                    resynced = true
                    break
                }
            }
            if resynced { continue }

            spokenIndex += 1
        }

        return lastGoodIndex
    }

    private func wordLevelMatch(spoken: String) -> Int {
        let remainingSource = String(sourceText.dropFirst(matchStartOffset))
        let sourceWords = wordTokens(in: remainingSource)
        let spokenWords = spoken.lowercased().split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var sourceIndex = 0
        var spokenIndex = 0
        var matchedOffset = 0

        while sourceIndex < sourceWords.count && spokenIndex < spokenWords.count {
            let sourceToken = sourceWords[sourceIndex]
            if Self.isAnnotationWord(sourceToken.text) {
                matchedOffset = sourceToken.endOffset
                sourceIndex += 1
                continue
            }

            let sourceWord = sourceToken.text.lowercased().filter { $0.isLetter || $0.isNumber }
            let spokenWord = spokenWords[spokenIndex].filter { $0.isLetter || $0.isNumber }

            if !spokenWord.isEmpty, sourceWord.hasPrefix(spokenWord), sourceWord.count > spokenWord.count {
                matchedOffset = sourceToken.startOffset + offsetAfterSignificantCharacters(
                    spokenWord.count,
                    in: sourceToken.text
                )
                break
            }

            if sourceWord == spokenWord || isFuzzyMatch(sourceWord, spokenWord) {
                matchedOffset = sourceToken.endOffset
                sourceIndex += 1
                spokenIndex += 1
            } else {
                spokenIndex += 1
            }
        }

        while sourceIndex < sourceWords.count && Self.isAnnotationWord(sourceWords[sourceIndex].text) {
            matchedOffset = sourceWords[sourceIndex].endOffset
            sourceIndex += 1
        }

        return matchedOffset
    }

    private func wordTokens(in text: String) -> [SourceToken] {
        var tokens: [SourceToken] = []
        var tokenStart: String.Index?
        var index = text.startIndex

        while index < text.endIndex {
            if text[index].isWhitespace {
                if let start = tokenStart {
                    tokens.append(
                        SourceToken(
                            text: String(text[start..<index]),
                            startOffset: text.distance(from: text.startIndex, to: start),
                            endOffset: text.distance(from: text.startIndex, to: index)
                        )
                    )
                    tokenStart = nil
                }
            } else if tokenStart == nil {
                tokenStart = index
            }
            index = text.index(after: index)
        }

        if let start = tokenStart {
            tokens.append(
                SourceToken(
                    text: String(text[start..<text.endIndex]),
                    startOffset: text.distance(from: text.startIndex, to: start),
                    endOffset: text.distance(from: text.startIndex, to: text.endIndex)
                )
            )
        }

        return tokens
    }

    private func offsetAfterSignificantCharacters(_ count: Int, in text: String) -> Int {
        guard count > 0 else { return 0 }
        var matched = 0
        var offset = 0

        for character in text {
            offset += 1
            guard character.isLetter || character.isNumber else { continue }
            matched += 1
            if matched >= count {
                return offset
            }
        }

        return offset
    }

    private static func isAnnotationWord(_ word: String) -> Bool {
        if word.hasPrefix("[") && word.hasSuffix("]") { return true }
        return word.filter { $0.isLetter || $0.isNumber }.isEmpty
    }

    private func isFuzzyMatch(_ a: String, _ b: String) -> Bool {
        if a.isEmpty || b.isEmpty { return false }
        if a == b { return true }
        let shorter = min(a.count, b.count)
        if shorter >= 3 && (a.hasPrefix(b) || b.hasPrefix(a)) { return true }
        let shared = zip(a, b).prefix(while: { $0 == $1 }).count
        if shorter >= 3 && shared >= max(3, shorter * 3 / 5) { return true }
        let distance = editDistance(a, b)
        if shorter <= 2 { return false }
        if shorter <= 4 { return distance <= 1 }
        if shorter <= 8 { return distance <= 2 }
        return distance <= max(a.count, b.count) / 3
    }

    private func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a)
        let b = Array(b)
        var dp = Array(0...b.count)
        for i in 1...a.count {
            var previous = dp[0]
            dp[0] = i
            for j in 1...b.count {
                let temp = dp[j]
                dp[j] = a[i - 1] == b[j - 1] ? previous : min(previous, dp[j], dp[j - 1]) + 1
                previous = temp
            }
        }
        return dp[b.count]
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
    }

    private static func significantText(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: { scalar in
            let value = scalar.value
            return (value >= 0x4E00 && value <= 0x9FFF)
                || (value >= 0x3400 && value <= 0x4DBF)
                || (value >= 0x20000 && value <= 0x2A6DF)
                || (value >= 0xF900 && value <= 0xFAFF)
                || (value >= 0x3040 && value <= 0x309F)
                || (value >= 0x30A0 && value <= 0x30FF)
                || (value >= 0xAC00 && value <= 0xD7AF)
        })
    }

    private func progressLabel(for count: Int) -> String {
        let total = max(sourceText.count, 1)
        let clamped = min(max(count, 0), total)
        return "\(Int((Double(clamped) / Double(total)) * 100))%"
    }

    private func significantCharacters(in characters: [Character]) -> [(char: Character, offsetAfter: Int)] {
        characters.enumerated().compactMap { index, character in
            guard character.isLetter || character.isNumber else { return nil }
            return (character, index + 1)
        }
    }
}
