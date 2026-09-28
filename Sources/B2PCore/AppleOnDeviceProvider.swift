#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// 構造化生成で受け取り、ほかの接続方式と同じ JSON 文字列にして返す。
/// @Generable マクロは Xcode 本体がないと展開できないので、スキーマは実行時に組み立てる。
@available(macOS 26.0, *)
public struct AppleOnDeviceProvider: LLMProvider {
    public init() {}

    public static func unavailableReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return "この Mac は Apple Intelligence に対応していません。"
            case .appleIntelligenceNotEnabled: return "Apple Intelligence がオフです。システム設定でオンにしてください。"
            case .modelNotReady: return "端末内モデルを準備中です。ダウンロードが終わるまで待ってください。"
            @unknown default: return "Apple Intelligence を使えません。"
            }
        }
    }

    static func revisionSchema() throws -> GenerationSchema {
        let text = DynamicGenerationSchema(type: String.self)
        let change = DynamicGenerationSchema(name: "Change", properties: [
            .init(name: "before", description: "元の表現", schema: text),
            .init(name: "after", description: "直した表現。修正版の中にそのまま含まれる文字列", schema: text),
            .init(name: "reason", description: "なぜ読みやすくなるかを一文で", schema: text),
        ])
        let revision = DynamicGenerationSchema(name: "Revision", properties: [
            .init(name: "revised", description: "修正版の全文", schema: text),
            .init(name: "changes", description: "影響の大きい順の修正点",
                  schema: DynamicGenerationSchema(arrayOf: change, maximumElements: 7)),
            .init(name: "minor", description: "細かな表記修正のまとめ。なければ空文字", schema: text),
            .init(name: "concerns", description: "文面では直せない懸念。なければ空配列",
                  schema: DynamicGenerationSchema(arrayOf: text)),
        ])
        return try GenerationSchema(root: revision, dependencies: [])
    }

    public func complete(system: String, user: String, config: ProfileConfig) async throws -> String {
        if let reason = Self.unavailableReason() { throw LLMError.unavailable(reason) }
        let session = LanguageModelSession(instructions: system)
        let response = try await session.respond(
            to: user,
            schema: try Self.revisionSchema(),
            includeSchemaInPrompt: true,
            options: GenerationOptions(temperature: config.temperature)
        )
        return response.content.jsonString
    }
}
#endif
