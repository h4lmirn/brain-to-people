import Foundation

public struct RevisionChange: Codable, Hashable, Sendable {
    public var before: String
    public var after: String
    public var reason: String

    public init(before: String, after: String, reason: String) {
        self.before = before
        self.after = after
        self.reason = reason
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        before = try c.decodeIfPresent(String.self, forKey: .before) ?? ""
        after = try c.decodeIfPresent(String.self, forKey: .after) ?? ""
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
    }
}

public struct RevisionResult: Codable, Equatable, Sendable {
    public var revised: String
    public var changes: [RevisionChange]
    public var minor: String
    public var concerns: [String]

    public init(revised: String, changes: [RevisionChange] = [], minor: String = "", concerns: [String] = []) {
        self.revised = revised
        self.changes = changes
        self.minor = minor
        self.concerns = concerns
    }

    /// revised だけは必須。ほかの項目は欠けていても、型が少し違っても受け取る。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        revised = try c.decode(String.self, forKey: .revised)
        changes = (try? c.decodeIfPresent([RevisionChange].self, forKey: .changes)) ?? []
        minor = (try? c.decodeIfPresent(String.self, forKey: .minor)) ?? ""
        if let list = try? c.decodeIfPresent([String].self, forKey: .concerns) {
            concerns = list
        } else if let single = try? c.decodeIfPresent(String.self, forKey: .concerns), !single.isEmpty {
            concerns = [single]
        } else {
            concerns = []
        }
    }
}

public enum ParsedResponse: Equatable, Sendable {
    case structured(RevisionResult)
    /// JSON として読めなかった応答。前後の空白だけ取り除いた本文。
    case raw(String)
}

public enum ResponseParser {
    public static func parse(_ raw: String) -> ParsedResponse {
        let cleaned = stripFence(raw)
        if let result = decode(cleaned) { return .structured(result) }
        // JSON の前後に説明文が付いた応答を救う
        if let open = cleaned.firstIndex(of: "{"), let close = cleaned.lastIndex(of: "}"), open < close,
           let result = decode(String(cleaned[open...close])) {
            return .structured(result)
        }
        return .raw(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// 前後の空白と ```json のコードフェンスを取り除く。
    public static func stripFence(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        if let newline = s.firstIndex(of: "\n") {
            s = String(s[s.index(after: newline)...])
        } else {
            s = String(s.dropFirst(3))
        }
        if let fence = s.range(of: "```", options: .backwards) {
            s = String(s[..<fence.lowerBound])
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decode(_ text: String) -> RevisionResult? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(RevisionResult.self, from: data)
    }
}
