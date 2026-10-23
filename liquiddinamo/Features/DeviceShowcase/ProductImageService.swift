//
//  ProductImageService.swift
//  boringNotch
//
//  Created for Boring Notch
//

import AppKit
import Foundation

// MARK: - Product Image Candidate

public struct ProductImageCandidate: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let imageURL: URL
    public let thumbnailURL: URL?
    public let width: Int
    public let height: Int
    public let displayDomain: String
    public let contextURL: URL?

    public init(
        id: String,
        title: String,
        imageURL: URL,
        thumbnailURL: URL? = nil,
        width: Int = 0,
        height: Int = 0,
        displayDomain: String = "",
        contextURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.width = width
        self.height = height
        self.displayDomain = displayDomain
        self.contextURL = contextURL
    }

    public var dimensionsString: String {
        if width > 0 && height > 0 {
            return "\(width) × \(height)"
        }
        return "Bundled 3D"
    }
}

// MARK: - Offline Bundled Asset Service

public final class ProductImageService {
    public static let shared = ProductImageService()

    public init() {}

    /// Resolves closest relevant 3D asset from the bundled offline library without network access.
    public func resolveBundledAsset(for query: String) -> ProcessedProductImage? {
        let icon = Premium3DIcon.from(name: query)
        return ProductImageProcessor.shared.createFromSymbol(icon: icon)
    }

    /// Returns matching candidates from the bundled offline 3D catalog.
    public func searchBundledCandidates(query: String) -> [ProductImageCandidate] {
        let icon = Premium3DIcon.from(name: query)
        let id = "bundled://\(icon.rawValue)"
        guard let url = URL(string: id) else { return [] }

        return [
            ProductImageCandidate(
                id: id,
                title: icon.rawValue.capitalized,
                imageURL: url,
                thumbnailURL: url,
                width: 1024,
                height: 1024,
                displayDomain: "Bundled 3D Asset",
                contextURL: nil
            )
        ]
    }
}
