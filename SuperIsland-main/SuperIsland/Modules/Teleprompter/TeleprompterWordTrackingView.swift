import AppKit
import SwiftUI

enum TeleprompterTextTokenizer {
    struct SpeechMatchingText {
        let text: String
        let displayOffsetBySpeechOffset: [Int]

        static let empty = SpeechMatchingText(text: "", displayOffsetBySpeechOffset: [0])

        func displayOffset(forSpeechOffset offset: Int) -> Int {
            let clamped = min(max(offset, 0), max(0, displayOffsetBySpeechOffset.count - 1))
            return displayOffsetBySpeechOffset[clamped]
        }
    }

    static func displayText(from text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    static func speechMatchingText(from text: String) -> SpeechMatchingText {
        let display = displayText(from: text)
        guard !display.isEmpty else { return .empty }

        var speechText = ""
        var offsets = [0]
        var emittedSpeech = false
        var pendingWhitespaceDisplayOffset: Int?
        var displayOffset = 0

        for character in display {
            let characterStartOffset = displayOffset
            displayOffset += 1

            if character.isWhitespace {
                if emittedSpeech, pendingWhitespaceDisplayOffset == nil {
                    pendingWhitespaceDisplayOffset = characterStartOffset
                }
                continue
            }

            if emittedSpeech, let whitespaceOffset = pendingWhitespaceDisplayOffset {
                speechText.append(" ")
                offsets.append(whitespaceOffset)
                pendingWhitespaceDisplayOffset = nil
            }

            speechText.append(character)
            offsets.append(displayOffset)
            emittedSpeech = true
        }

        if emittedSpeech {
            offsets[offsets.count - 1] = display.count
        }

        guard !speechText.isEmpty else { return .empty }
        return SpeechMatchingText(text: speechText, displayOffsetBySpeechOffset: offsets)
    }

    static func splitTextIntoWords(_ text: String) -> [String] {
        let tokens = displayText(from: text)
            .split(omittingEmptySubsequences: true, whereSeparator: { $0.isWhitespace })
            .map(String.init)

        var result: [String] = []
        for token in tokens {
            guard token.unicodeScalars.contains(where: { $0.isCJK }) else {
                result.append(token)
                continue
            }

            var buffer = ""
            for character in token {
                if character.unicodeScalars.first.map(\.isCJK) == true {
                    if !buffer.isEmpty {
                        result.append(buffer)
                        buffer = ""
                    }
                    result.append(String(character))
                } else {
                    buffer.append(character)
                }
            }
            if !buffer.isEmpty {
                result.append(buffer)
            }
        }
        return result
    }
}

private extension Unicode.Scalar {
    var isCJK: Bool {
        let value = value
        return (value >= 0x4E00 && value <= 0x9FFF)
            || (value >= 0x3400 && value <= 0x4DBF)
            || (value >= 0x20000 && value <= 0x2A6DF)
            || (value >= 0xF900 && value <= 0xFAFF)
            || (value >= 0x3040 && value <= 0x309F)
            || (value >= 0x30A0 && value <= 0x30FF)
            || (value >= 0xAC00 && value <= 0xD7AF)
    }
}

private struct WordTrackingHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TeleprompterLinePosition: Equatable {
    let index: Int
    let top: CGFloat
}

struct TeleprompterWordTrackingTextView: View {
    let containerHeight: CGFloat

    @ObservedObject private var manager = TeleprompterManager.shared
    @ObservedObject private var speech = TeleprompterManager.shared.speechRecognizer
    @State private var textHeight: CGFloat = 0
    @State private var manualOffset: CGFloat = 0
    @State private var appliedNudge: CGFloat = 0
    @State private var activeLinePosition = TeleprompterLinePosition(index: 0, top: 0)

    private var displayText: String {
        manager.wordTrackingDisplayText
    }

    private var maxOffset: CGFloat {
        max(0, textHeight - containerHeight)
    }

    private var currentLineAnchorY: CGFloat {
        containerHeight * 0.28
    }

    var body: some View {
        GeometryReader { geo in
            highlightedText(width: geo.size.width)
                .offset(y: -lineAnchoredOffset)
                .animation(.easeOut(duration: 0.22), value: activeLinePosition.index)
                .onAppear {
                    syncLinePosition(width: geo.size.width, force: true)
                }
                .onChange(of: geo.size.width) { _, width in
                    syncLinePosition(width: width, force: true)
                }
                .onChange(of: speech.recognizedCharCount) { _, _ in
                    syncLinePosition(width: geo.size.width)
                }
                .onChange(of: manager.fontSize) { _, _ in
                    syncLinePosition(width: geo.size.width, force: true)
                }
                .onChange(of: manager.textAlignmentIndex) { _, _ in
                    syncLinePosition(width: geo.size.width, force: true)
                }
        }
        .clipped()
        .mask(verticalFade)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .onPreferenceChange(WordTrackingHeightKey.self) { textHeight = $0 }
        .onChange(of: manager.scrollNudge) { _, total in
            let delta = total - appliedNudge
            appliedNudge = total
            manualOffset = min(maxOffset, max(-maxOffset, manualOffset + delta))
        }
        .onChange(of: manager.resetToken) { _, _ in
            manualOffset = 0
            activeLinePosition = TeleprompterLinePosition(index: 0, top: 0)
            appliedNudge = manager.scrollNudge
        }
        .onChange(of: manager.scriptText) { _, _ in
            manualOffset = 0
            activeLinePosition = TeleprompterLinePosition(index: 0, top: 0)
            appliedNudge = manager.scrollNudge
        }
        .onChange(of: speech.recognizedCharCount) { _, count in
            guard manager.isPlaying, displayText.count > 0, count >= displayText.count else { return }
            manager.pause()
        }
        .dataAnnotationID("teleprompter-word-tracking-surface")
    }

    private func highlightedText(width: CGFloat) -> some View {
        let parts = textParts()
        let read = Text(parts.read)
            .foregroundColor(.white.opacity(0.88))
        let current = Text(parts.current)
            .fontWeight(.semibold)
            .foregroundColor(.white)
        let unread = Text(parts.unread)
            .foregroundColor(.white.opacity(0.42))

        return (read + current + unread)
            .font(.system(size: manager.fontSize, weight: .regular))
            .lineSpacing(manager.fontSize * 0.35)
            .multilineTextAlignment(manager.textAlignment)
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: width, alignment: frameAlignment)
            .padding(.top, currentLineAnchorY)
            .padding(.bottom, containerHeight - currentLineAnchorY)
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(key: WordTrackingHeightKey.self, value: geometry.size.height)
                }
            )
    }

    private var frameAlignment: Alignment {
        switch manager.textAlignment {
        case .leading: return .topLeading
        case .trailing: return .topTrailing
        default: return .top
        }
    }

    private func textParts() -> (read: String, current: String, unread: String) {
        guard !displayText.isEmpty else { return ("", "", "") }
        if speech.recognizedCharCount >= displayText.count {
            return (displayText, "", "")
        }
        let clamped = min(max(speech.recognizedCharCount, 0), displayText.count)
        let currentRange = currentTokenRange(containing: clamped)
        let readEnd = currentRange?.lowerBound ?? displayText.index(displayText.startIndex, offsetBy: clamped)
        let currentEnd = currentRange?.upperBound ?? readEnd

        let read = String(displayText[..<readEnd])
        let current = String(displayText[readEnd..<currentEnd])
        let unread = String(displayText[currentEnd...])
        return (read, current, unread)
    }

    private var lineAnchoredOffset: CGFloat {
        min(maxOffset, max(0, activeLinePosition.top + manualOffset))
    }

    private func syncLinePosition(width: CGFloat, force: Bool = false) {
        guard width > 1, !displayText.isEmpty else {
            activeLinePosition = TeleprompterLinePosition(index: 0, top: 0)
            return
        }
        let position = currentLinePosition(width: width)
        guard force || position.index > activeLinePosition.index else { return }
        activeLinePosition = position
    }

    private func currentLinePosition(width: CGFloat) -> TeleprompterLinePosition {
        guard width > 1, !displayText.isEmpty else {
            return TeleprompterLinePosition(index: 0, top: 0)
        }
        let offset = currentWordStartOffset()
        return TeleprompterLineLayout.position(
            forCharacterOffset: offset,
            in: displayText,
            width: width,
            fontSize: manager.fontSize,
            lineSpacing: manager.fontSize * 0.35,
            alignment: manager.textAlignment
        )
    }

    private func currentWordStartOffset() -> Int {
        guard !displayText.isEmpty else { return 0 }
        if speech.recognizedCharCount >= displayText.count {
            return max(0, displayText.count - 1)
        }
        let clamped = min(max(speech.recognizedCharCount, 0), displayText.count)
        guard let currentRange = currentTokenRange(containing: clamped) else {
            return clamped
        }
        return displayText.distance(from: displayText.startIndex, to: currentRange.lowerBound)
    }

    private func currentTokenRange(containing offset: Int) -> Range<String.Index>? {
        guard !displayText.isEmpty else { return nil }
        let clamped = min(max(offset, 0), max(0, displayText.count - 1))
        let index = displayText.index(displayText.startIndex, offsetBy: clamped)

        if offset > 0, index > displayText.startIndex {
            let previousIndex = displayText.index(before: index)
            if displayText[previousIndex].unicodeScalars.contains(where: \.isCJK) {
                return previousIndex..<displayText.index(after: previousIndex)
            }
        }

        if displayText[index].unicodeScalars.contains(where: \.isCJK) {
            return index..<displayText.index(after: index)
        }

        if displayText[index].isWhitespace {
            return nil
        }

        let lower = displayText[..<index].lastIndex(where: \.isWhitespace)
            .map { displayText.index(after: $0) } ?? displayText.startIndex
        let upper = displayText[index...].firstIndex(where: \.isWhitespace) ?? displayText.endIndex
        guard lower < upper else { return nil }
        return lower..<upper
    }

    private var verticalFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.00),
                .init(color: .black, location: 0.18),
                .init(color: .black, location: 0.78),
                .init(color: .clear, location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

private enum TeleprompterLineLayout {
    static func position(
        forCharacterOffset characterOffset: Int,
        in text: String,
        width: CGFloat,
        fontSize: CGFloat,
        lineSpacing: CGFloat,
        alignment: TextAlignment
    ) -> TeleprompterLinePosition {
        guard !text.isEmpty, width > 1 else {
            return TeleprompterLinePosition(index: 0, top: 0)
        }

        let nsText = text as NSString
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = lineSpacing
        paragraphStyle.alignment = nsTextAlignment(for: alignment)

        let attributedString = NSMutableAttributedString(string: text)
        attributedString.addAttributes(
            [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .regular),
                .paragraphStyle: paragraphStyle
            ],
            range: NSRange(location: 0, length: nsText.length)
        )

        let textStorage = NSTextStorage(attributedString: attributedString)
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let characterIndex = min(
            max(utf16Offset(forCharacterOffset: characterOffset, in: text), 0),
            max(0, nsText.length - 1)
        )
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        var currentLine = 0
        var position = TeleprompterLinePosition(index: 0, top: 0)
        var found = false

        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
        ) { rect, _, _, glyphRange, stop in
            if NSLocationInRange(glyphIndex, glyphRange) {
                position = TeleprompterLinePosition(index: currentLine, top: rect.minY)
                found = true
                stop.pointee = true
                return
            }
            currentLine += 1
        }

        if !found {
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            position = TeleprompterLinePosition(index: currentLine, top: rect.minY)
        }
        return position
    }

    private static func utf16Offset(forCharacterOffset offset: Int, in text: String) -> Int {
        let clamped = min(max(offset, 0), text.count)
        let index = text.index(text.startIndex, offsetBy: clamped)
        return text[..<index].utf16.count
    }

    private static func nsTextAlignment(for alignment: TextAlignment) -> NSTextAlignment {
        switch alignment {
        case .leading: return .left
        case .trailing: return .right
        default: return .center
        }
    }
}
