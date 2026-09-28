import Foundation

public protocol LLMProvider: Sendable {
    func complete(system: String, user: String, config: ProfileConfig) async throws -> String
}

public enum LLMError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidURL
    case timeout
    case offline
    case cannotConnect(String)
    case network(String)
    case unauthorized
    case rateLimited
    case server(Int, String?)
    case badResponse
    case emptyResponse
    case refused
    case unavailable(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "API キーが未設定です。設定画面（⌘,）で入力してください。"
        case .invalidURL: "接続先 URL が正しくありません。"
        case .timeout: "60秒以内に応答がありませんでした。"
        case .offline: "インターネットに接続されていません。"
        case .cannotConnect(let host): "\(host) に接続できません。サーバーが起動しているか確認してください。"
        case .network(let message): "通信エラー：\(message)"
        case .unauthorized: "認証に失敗しました。API キーを確認してください。"
        case .rateLimited: "利用上限に達しました。少し待ってから実行してください。"
        case .server(let code, let message):
            "サーバーエラー（\(code)）" + (message.map { "：\($0)" } ?? "")
        case .badResponse: "応答の形式が想定と違います。"
        case .emptyResponse: "応答が空でした。"
        case .refused: "AI がこの文章への応答を断りました。"
        case .unavailable(let reason): reason
        }
    }
}

public enum HTTPClient {
    /// 60秒で打ち切る。timeoutIntervalForResource は応答全体にかかる上限。
    public static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    static func send(_ request: URLRequest, session: URLSession) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .timedOut: throw LLMError.timeout
            case .notConnectedToInternet, .networkConnectionLost: throw LLMError.offline
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                throw LLMError.cannotConnect(request.url?.host ?? "接続先")
            default: throw LLMError.network(error.localizedDescription)
            }
        }
        guard let http = response as? HTTPURLResponse else { throw LLMError.badResponse }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw LLMError.unauthorized
        case 429: throw LLMError.rateLimited
        default: throw LLMError.server(http.statusCode, errorMessage(from: data))
        }
    }

    /// Anthropic と OpenAI 互換の両方のエラー形式から本文を拾う。
    static func errorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let error = json["error"] as? String { return error }
        return json["message"] as? String
    }

    static func jsonRequest(url: URL, body: [String: Any], headers: [String: String]) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}

// MARK: - Anthropic

public struct AnthropicProvider: LLMProvider {
    public static let apiVersion = "2023-06-01"
    public static let maxTokens = 4096

    let apiKey: String?
    let session: URLSession

    public init(apiKey: String?, session: URLSession = HTTPClient.session) {
        self.apiKey = apiKey
        self.session = session
    }

    /// 接続先 URL がホストだけでも /v1 付きでも /v1/messages まで書かれていても受け付ける。
    public static func endpoint(baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty { base = ProviderKind.anthropic.defaultBaseURL }
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasSuffix("/v1/messages") { return URL(string: base) }
        if base.hasSuffix("/v1") { return URL(string: base + "/messages") }
        return URL(string: base + "/v1/messages")
    }

    /// Sonnet 5 や Opus 4.7 以降は temperature を送ると 400 になるので送らない。
    public static func acceptsTemperature(model: String) -> Bool {
        let m = model.lowercased()
        let rejecting = ["claude-sonnet-5", "claude-opus-5", "claude-fable-5", "claude-mythos-5", "claude-opus-4-7", "claude-opus-4-8"]
        return !rejecting.contains { m.hasPrefix($0) }
    }

    /// 考える量（effort）を指定できるモデル。Haiku 4.5 などに送るとエラーになる。
    public static func supportsEffort(model: String) -> Bool {
        let m = model.lowercased()
        let supporting = ["claude-sonnet-5", "claude-opus-5", "claude-fable-5", "claude-mythos-5",
                          "claude-opus-4-8", "claude-opus-4-7", "claude-opus-4-6", "claude-opus-4-5", "claude-sonnet-4-6"]
        return supporting.contains { m.hasPrefix($0) }
    }

    public static func requestBody(system: String, user: String, config: ProfileConfig,
                                   includeTemperature: Bool, includeEffort: Bool = false) -> [String: Any] {
        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        if includeTemperature { body["temperature"] = config.temperature }
        if includeEffort { body["output_config"] = ["effort": "low"] }
        return body
    }

    /// 応答 JSON から text ブロックだけをつなぐ（thinking ブロックは捨てる）。
    public static func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else { throw LLMError.badResponse }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        if text.isEmpty {
            if (json["stop_reason"] as? String) == "refusal" { throw LLMError.refused }
            throw LLMError.emptyResponse
        }
        return text
    }

    public func complete(system: String, user: String, config: ProfileConfig) async throws -> String {
        guard let apiKey, !apiKey.isEmpty else { throw LLMError.missingAPIKey }
        var includeTemperature = Self.acceptsTemperature(model: config.model)
        var includeEffort = config.fastMode && Self.supportsEffort(model: config.model)
        // モデルが項目を拒んだときは、その項目を外して送りなおす（最大2回）
        for _ in 0..<2 {
            do {
                return try await send(system: system, user: user, config: config, apiKey: apiKey,
                                      includeTemperature: includeTemperature, includeEffort: includeEffort)
            } catch LLMError.server(400, let message?) where includeTemperature && message.contains("temperature") {
                includeTemperature = false
            } catch LLMError.server(400, let message?) where includeEffort && (message.contains("effort") || message.contains("output_config")) {
                includeEffort = false
            }
        }
        return try await send(system: system, user: user, config: config, apiKey: apiKey,
                              includeTemperature: includeTemperature, includeEffort: includeEffort)
    }

    private func send(system: String, user: String, config: ProfileConfig, apiKey: String,
                      includeTemperature: Bool, includeEffort: Bool) async throws -> String {
        guard let url = Self.endpoint(baseURL: config.baseURL) else { throw LLMError.invalidURL }
        let request = try HTTPClient.jsonRequest(
            url: url,
            body: Self.requestBody(system: system, user: user, config: config,
                                   includeTemperature: includeTemperature, includeEffort: includeEffort),
            headers: ["x-api-key": apiKey, "anthropic-version": Self.apiVersion]
        )
        let data = try await HTTPClient.send(request, session: session)
        return try Self.extractText(from: data)
    }
}

// MARK: - OpenAI 互換（OpenAI・Ollama・LM Studio）

public struct OpenAICompatibleProvider: LLMProvider {
    let apiKey: String?
    let session: URLSession

    public init(apiKey: String?, session: URLSession = HTTPClient.session) {
        self.apiKey = apiKey
        self.session = session
    }

    public static func url(baseURL: String, path: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty, base.hasPrefix("http") else { return nil }
        return URL(string: base + "/" + path)
    }

    public static func extractText(from data: Data) throws -> String {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else { throw LLMError.badResponse }
        guard let text = message["content"] as? String, !text.isEmpty else {
            if message["refusal"] is String { throw LLMError.refused }
            throw LLMError.emptyResponse
        }
        return text
    }

    public static func extractModelIDs(from data: Data) throws -> [String] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { throw LLMError.badResponse }
        return list.compactMap { $0["id"] as? String }.sorted()
    }

    private var authHeaders: [String: String] {
        guard let apiKey, !apiKey.isEmpty else { return [:] }
        return ["Authorization": "Bearer \(apiKey)"]
    }

    public func complete(system: String, user: String, config: ProfileConfig) async throws -> String {
        guard let url = Self.url(baseURL: config.baseURL, path: "chat/completions") else { throw LLMError.invalidURL }
        let body: [String: Any] = [
            "model": config.model,
            "temperature": config.temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        let request = try HTTPClient.jsonRequest(url: url, body: body, headers: authHeaders)
        let data = try await HTTPClient.send(request, session: session)
        return try Self.extractText(from: data)
    }

    public func listModels(baseURL: String) async throws -> [String] {
        guard let url = Self.url(baseURL: baseURL, path: "models") else { throw LLMError.invalidURL }
        var request = URLRequest(url: url, timeoutInterval: 15)
        for (key, value) in authHeaders { request.setValue(value, forHTTPHeaderField: key) }
        let data = try await HTTPClient.send(request, session: session)
        return try Self.extractModelIDs(from: data)
    }
}

// MARK: - 生成

public enum ProviderFactory {
    public static func make(for profile: ProfileConfig, apiKey: String?) throws -> any LLMProvider {
        switch profile.provider {
        case .anthropic:
            return AnthropicProvider(apiKey: apiKey)
        case .openAICompatible:
            return OpenAICompatibleProvider(apiKey: apiKey)
        case .appleOnDevice:
            #if canImport(FoundationModels)
            if #available(macOS 26.0, *) { return AppleOnDeviceProvider() }
            #endif
            throw LLMError.unavailable("Apple Intelligence は macOS 26 以降で使えます。")
        }
    }
}
