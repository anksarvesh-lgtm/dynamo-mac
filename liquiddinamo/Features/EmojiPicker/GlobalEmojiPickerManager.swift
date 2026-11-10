//
//  GlobalEmojiPickerManager.swift
//  LiquidDynamo
//
//  Floating fast emoji and symbol search picker triggered globally or from Dynamic Island.
//  Adopted from SuperIsland's EmojiPicker architecture.
//

import AppKit
import Combine
import Foundation
import SwiftUI

public struct EmojiItem: Identifiable, Sendable {
    public let id: String
    public let emoji: String
    public let name: String
    public let category: String

    public init(emoji: String, name: String, category: String = "Common") {
        self.id = name
        self.emoji = emoji
        self.name = name
        self.category = category
    }
}

@MainActor
public final class GlobalEmojiPickerManager: ObservableObject {
    public static let shared = GlobalEmojiPickerManager()

    @Published public var isVisible: Bool = false
    @Published public var searchText: String = ""
    @Published public private(set) var filteredEmojis: [EmojiItem] = []

    private let library: [EmojiItem] = [
        EmojiItem(emoji: "✨", name: "Sparkles", category: "Magic"),
        EmojiItem(emoji: "🚀", name: "Rocket", category: "Travel"),
        EmojiItem(emoji: "🔥", name: "Fire", category: "Nature"),
        EmojiItem(emoji: "💡", name: "Light Bulb", category: "Idea"),
        EmojiItem(emoji: "💻", name: "Laptop", category: "Tech"),
        EmojiItem(emoji: "⚡", name: "High Voltage", category: "Power"),
        EmojiItem(emoji: "🎉", name: "Party Popper", category: "Celebrate"),
        EmojiItem(emoji: "👍", name: "Thumbs Up", category: "People"),
        EmojiItem(emoji: "❤️", name: "Red Heart", category: "Love"),
        EmojiItem(emoji: "✅", name: "Check Mark", category: "Status"),
        EmojiItem(emoji: "☕", name: "Coffee", category: "Food"),
        EmojiItem(emoji: "🍎", name: "Apple", category: "Food"),
        EmojiItem(emoji: "🤖", name: "Robot", category: "Tech"),
        EmojiItem(emoji: "🎧", name: "Headphones", category: "Audio"),
        EmojiItem(emoji: "📅", name: "Calendar", category: "Time"),
        EmojiItem(emoji: "🔔", name: "Bell", category: "Alerts"),
        EmojiItem(emoji: "🔒", name: "Locked", category: "Security"),
        EmojiItem(emoji: "🛡️", name: "Shield", category: "Security")
    ]

    private init() {
        self.filteredEmojis = library
    }

    public func search(_ text: String) {
        searchText = text
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            filteredEmojis = library
        } else {
            filteredEmojis = library.filter {
                $0.name.lowercased().contains(q) || $0.category.lowercased().contains(q)
            }
        }
    }

    public func copyEmojiToClipboard(_ item: EmojiItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.emoji, forType: .string)
        print("==> [EmojiPicker] Copied \(item.emoji) (\(item.name)) to clipboard")
        isVisible = false
    }
}

