import Foundation
import Security

/// API キーを接続方式ごとに Keychain へ保存する。アカウント名は ProviderKind.rawValue。
public struct KeychainStore: Sendable {
    public let service: String

    public init(service: String = "B2P") {
        self.service = service
    }

    private func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read(account: String) -> String? {
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 空文字を渡すと削除する。
    public func write(_ value: String, account: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            SecItemDelete(query(account: account) as CFDictionary)
            return
        }
        let data = Data(trimmed.utf8)
        let status = SecItemUpdate(query(account: account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(account: account)
            q[kSecValueData as String] = data
            SecItemAdd(q as CFDictionary, nil)
        }
    }
}

/// プロファイルを ~/Library/Application Support/B2P/profiles.json に保存する。
public struct ProfileStore: Sendable {
    public let fileURL: URL

    public init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("B2P", isDirectory: true)
        fileURL = base.appendingPathComponent("profiles.json")
    }

    /// ファイルがなければ既定の4つを返す。壊れていたら退避してから既定に戻す。
    public func load() -> [ProfileConfig] {
        guard let data = try? Data(contentsOf: fileURL) else { return DefaultProfiles.make() }
        if let profiles = try? Self.decode(data), !profiles.isEmpty { return profiles }
        let backup = fileURL.deletingPathExtension().appendingPathExtension("broken.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
        return DefaultProfiles.make()
    }

    public func save(_ profiles: [ProfileConfig]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encode(profiles).write(to: fileURL, options: .atomic)
    }

    public static func encode(_ profiles: [ProfileConfig]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(profiles)
    }

    public static func decode(_ data: Data) throws -> [ProfileConfig] {
        try JSONDecoder().decode([ProfileConfig].self, from: data).map { profile in
            var migrated = profile
            if migrated.provider == .anthropic && migrated.model == "claude-sonnet-5" {
                migrated.model = ProviderKind.anthropic.defaultModel
            }
            return migrated
        }
    }
}
