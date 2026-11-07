import Foundation

public struct Citation: Identifiable, Equatable, Sendable {
    public var index: Int
    public var title: String
    public var url: URL
    public var id: Int { index }
    public init(index: Int, title: String, url: URL) {
        self.index = index
        self.title = title
        self.url = url
    }
}

public struct ResearchAnswer: Equatable, Sendable {
    public var text: String
    public var citations: [Citation]
    public var usedWeb: Bool
    public init(text: String, citations: [Citation], usedWeb: Bool) {
        self.text = text
        self.citations = citations
        self.usedWeb = usedWeb
    }
}
