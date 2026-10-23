//
//  ClipboardEntry.swift
//  LiquidDynamo
//
//  Represents a captured clipboard item (text, image, file, url) in LiquidDynamo.
//

import AppKit
import Foundation
import SwiftUI

public enum ClipboardType: String, Codable, CaseIterable {
    case text
    case image
    case file
    case url
}

public struct ClipboardEntry: Identifiable, Codable, Equatable {
    public let id: UUID
    public let type: ClipboardType
    public let text: String
    public let fileURL: URL?
    public let imageData: Data?
    public let timestamp: Date
    public var isPinned: Bool

    public init(
        id: UUID = UUID(),
        type: ClipboardType = .text,
        text: String,
        fileURL: URL? = nil,
        imageData: Data? = nil,
        timestamp: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.fileURL = fileURL
        self.imageData = imageData
        self.timestamp = timestamp
        self.isPinned = isPinned
    }

    enum CodingKeys: String, CodingKey {
        case id, type, text, fileURL, imageData, timestamp, isPinned
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.type = try container.decodeIfPresent(ClipboardType.self, forKey: .type) ?? .text
        self.text = try container.decodeIfPresent(String.self, forKey: .text) ?? ""
        self.fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        self.imageData = try container.decodeIfPresent(Data.self, forKey: .imageData)
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        self.isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    public var previewText: String {
        switch type {
        case .file:
            return fileURL?.lastPathComponent ?? (text.isEmpty ? "File" : text)
        case .image:
            return text.isEmpty ? "Image" : text
        case .url:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = URL(string: trimmed), let host = url.host {
                return host + (url.path == "/" ? "" : url.path)
            }
            return trimmed
        case .text:
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
            if singleLine.count > 60 {
                return String(singleLine.prefix(57)) + "…"
            }
            return singleLine.isEmpty ? "Empty Text" : singleLine
        }
    }

    public var detailText: String {
        switch type {
        case .file:
            if let url = fileURL, let values = try? url.resourceValues(forKeys: [.fileSizeKey]) {
                if let size = values.fileSize {
                    return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
                }
            }
            return "File"
        case .image:
            return "Image"
        case .url:
            return "URL"
        case .text:
            let lines = text.components(separatedBy: .newlines).count
            if lines > 1 {
                return "\(lines) lines • \(text.count) chars"
            }
            return "\(text.count) chars"
        }
    }

    public var iconSymbolName: String {
        switch type {
        case .file:
            return "doc.fill"
        case .image:
            return "photo.fill"
        case .url:
            return "link"
        case .text:
            return "doc.text"
        }
    }

    public var iconColor: Color {
        switch type {
        case .file:
            return .blue
        case .image:
            return .purple
        case .url:
            return .teal
        case .text:
            return .cyan
        }
    }

    public var lineCount: Int {
        text.components(separatedBy: .newlines).count
    }

    public var charCount: Int {
        text.count
    }
}
