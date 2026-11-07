import Foundation

public struct AIMessage: Sendable, Equatable {
    public enum Role: String, Sendable { case user, assistant }
    public var role: Role
    public var text: String
    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public enum AIError: Error, Equatable, LocalizedError {
    case notConfigured(String), http(Int, String), refused(String?), emptyResponse, invalidResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured(let m): m
        case .http(let code, let m): "AI request failed (\(code)): \(m)"
        case .refused(let c): "The model declined this request" + (c.map { " (\($0))" } ?? "")
        case .emptyResponse: "The model returned no text"
        case .invalidResponse: "Unexpected response from the AI provider"
        }
    }
}

/// Text-in, text-out. AI providers never receive tools that touch the system: anything actionable
/// must be parsed into a typed `AppAction` and pass `PermissionPolicy` with origin `.ai`.
public protocol AIProvider: Sendable {
    var name: String { get }
    func complete(system: String, messages: [AIMessage], maxTokens: Int) async throws -> String
}

public enum AIProviderFactory {
    public static func defaultModel(_ kind: AIProviderKind) -> String {
        switch kind {
        case .anthropic: "claude-opus-5-5"
        case .openAI: "gpt-5-mini"
        case .ollama: "llama3.2"
        case .none: ""
        }
    }

    public static func make(kind: AIProviderKind, model: String, apiKey: @escaping @Sendable () -> String?) -> AIProvider? {
        let m = model.trimmingCharacters(in: .whitespaces).isEmpty ? defaultModel(kind) : model
        switch kind {
        case .none: return nil
        case .anthropic: return AnthropicProvider(model: m, apiKey: apiKey)
        case .openAI: return OpenAIProvider(model: m, apiKey: apiKey)
        case .ollama: return OllamaProvider(model: m)
        }
    }
}

/// Anthropic Messages API over raw HTTP (there is no official Swift SDK).
public struct AnthropicProvider: AIProvider {
    public let name = "Anthropic"
    let model: String
    let apiKey: @Sendable () -> String?
    let http: HTTPClient

    public init(model: String = "claude-opus-5-5", apiKey: @escaping @Sendable () -> String?, http: HTTPClient = HTTPClient(timeout: 90, retries: 1)) {
        self.model = model
        self.apiKey = apiKey
        self.http = http
    }

    func body(system: String, messages: [AIMessage], maxTokens: Int) -> [String: Any] {
        var b: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.text] },
            // Short, cited answers: low effort keeps latency and cost down.
            "output_config": ["effort": "low"],
        ]
        // Server-side refusal fallback (routes declined requests to an appropriate model).
        if model.hasPrefix("claude-opus-5") || model.hasPrefix("claude-fable-5") || model == "claude-sonnet-5-5" {
            b["fallbacks"] = "default"
        }
        return b
    }

    public func complete(system: String, messages: [AIMessage], maxTokens: Int) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw AIError.notConfigured("Add an Anthropic API key in Settings › AI") }
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let b = body(system: system, messages: messages, maxTokens: maxTokens)
        if b["fallbacks"] != nil { req.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta") }
        req.httpBody = try JSONSerialization.data(withJSONObject: b)
        let (data, resp) = try await http.data(req)
        return try Self.parse(data, status: resp.statusCode)
    }

    static func parse(_ data: Data, status: Int) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.invalidResponse }
        guard (200...299).contains(status) else {
            let msg = ((obj["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(status)"
            throw AIError.http(status, msg)
        }
        if (obj["stop_reason"] as? String) == "refusal" {
            throw AIError.refused((obj["stop_details"] as? [String: Any])?["category"] as? String)
        }
        let text = (obj["content"] as? [[String: Any]] ?? [])
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIError.emptyResponse }
        return text
    }
}

/// OpenAI Chat Completions.
public struct OpenAIProvider: AIProvider {
    public let name = "OpenAI"
    let model: String
    let apiKey: @Sendable () -> String?
    let http: HTTPClient

    public init(model: String, apiKey: @escaping @Sendable () -> String?, http: HTTPClient = HTTPClient(timeout: 90, retries: 1)) {
        self.model = model
        self.apiKey = apiKey
        self.http = http
    }

    public func complete(system: String, messages: [AIMessage], maxTokens: Int) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw AIError.notConfigured("Add an OpenAI API key in Settings › AI") }
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let msgs = [["role": "system", "content": system]] + messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": msgs, "max_completion_tokens": maxTokens])
        let (data, resp) = try await http.data(req)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.invalidResponse }
        guard (200...299).contains(resp.statusCode) else {
            throw AIError.http(resp.statusCode, ((obj["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(resp.statusCode)")
        }
        guard let text = ((obj["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String,
              !text.isEmpty else { throw AIError.emptyResponse }
        return text
    }
}

/// Local models through Ollama (http://localhost:11434). Nothing leaves the machine.
public struct OllamaProvider: AIProvider {
    public let name = "Ollama"
    let model: String
    let http: HTTPClient
    let baseURL: URL

    public init(model: String, baseURL: URL = URL(string: "http://localhost:11434")!, http: HTTPClient = HTTPClient(timeout: 120, retries: 0)) {
        self.model = model
        self.baseURL = baseURL
        self.http = http
    }

    public func complete(system: String, messages: [AIMessage], maxTokens: Int) async throws -> String {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let msgs = [["role": "system", "content": system]] + messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": msgs, "stream": false,
                                                                   "options": ["num_predict": maxTokens]])
        let data: Data, resp: HTTPURLResponse
        do { (data, resp) = try await http.data(req) } catch {
            throw AIError.notConfigured("Ollama isn't running on localhost:11434")
        }
        guard (200...299).contains(resp.statusCode),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = (obj["message"] as? [String: Any])?["content"] as? String, !text.isEmpty else {
            throw AIError.http(resp.statusCode, "Ollama error")
        }
        return text
    }
}
