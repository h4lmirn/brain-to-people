import Foundation

/// 接続方式。Keychain のアカウント名には rawValue を使う。
public enum ProviderKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case anthropic
    case openAICompatible
    case appleOnDevice

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAICompatible: "OpenAI 互換（OpenAI・Ollama・LM Studio）"
        case .appleOnDevice: "Apple Intelligence（端末内）"
        }
    }

    public var shortName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .openAICompatible: "OpenAI 互換"
        case .appleOnDevice: "Apple Intelligence"
        }
    }

    public var usesNetwork: Bool { self != .appleOnDevice }

    public var defaultBaseURL: String {
        switch self {
        case .anthropic: "https://api.anthropic.com"
        case .openAICompatible: OpenAIPreset.ollama.url
        case .appleOnDevice: ""
        }
    }

    public var defaultModel: String {
        switch self {
        case .anthropic: "claude-sonnet-5"
        case .openAICompatible: ""
        case .appleOnDevice: "SystemLanguageModel"
        }
    }

    /// この OS で選べる接続方式。Apple 端末内モデルは macOS 26 以降でのみ出す。
    public static var available: [ProviderKind] {
        var kinds: [ProviderKind] = [.anthropic, .openAICompatible]
        if AppleOnDevice.isSupportedOS { kinds.append(.appleOnDevice) }
        return kinds
    }
}

public enum OpenAIPreset: String, CaseIterable, Identifiable, Sendable {
    case openAI, ollama, lmStudio

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .openAI: "OpenAI"
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        }
    }

    public var url: String {
        switch self {
        case .openAI: "https://api.openai.com/v1"
        case .ollama: "http://localhost:11434/v1"
        case .lmStudio: "http://localhost:1234/v1"
        }
    }
}

public enum AppleOnDevice {
    public static var isSupportedOS: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}

public struct ProfileConfig: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var provider: ProviderKind
    public var baseURL: String
    public var model: String
    public var temperature: Double
    public var instructions: String
    /// 速さを優先する。対応するモデルでは考える量（effort）を low にして送る。
    public var fastMode: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        provider: ProviderKind = .anthropic,
        baseURL: String? = nil,
        model: String? = nil,
        temperature: Double = 0.3,
        instructions: String,
        fastMode: Bool = false
    ) {
        self.id = id
        self.name = name
        self.provider = provider
        self.baseURL = baseURL ?? provider.defaultBaseURL
        self.model = model ?? provider.defaultModel
        self.temperature = temperature
        self.instructions = instructions
        self.fastMode = fastMode
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, provider, baseURL, model, temperature, instructions, fastMode
    }

    /// 後から足した項目（fastMode）がない古い profiles.json も読めるようにする。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        provider = try c.decode(ProviderKind.self, forKey: .provider)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        model = try c.decode(String.self, forKey: .model)
        temperature = try c.decode(Double.self, forKey: .temperature)
        instructions = try c.decode(String.self, forKey: .instructions)
        fastMode = try c.decodeIfPresent(Bool.self, forKey: .fastMode) ?? false
    }

    /// ツールバーの「ローカル」「クラウド」バッジ用。
    public var isLocal: Bool {
        switch provider {
        case .appleOnDevice: return true
        case .anthropic: return false
        case .openAICompatible:
            guard let host = URL(string: baseURL.trimmingCharacters(in: .whitespaces))?.host?.lowercased() else { return false }
            let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return ["localhost", "127.0.0.1", "::1"].contains(bare)
                || bare.hasSuffix(".localhost") || bare.hasSuffix(".local")
        }
    }
}
