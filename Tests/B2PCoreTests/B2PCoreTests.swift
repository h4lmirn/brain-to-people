import Foundation
import Testing
@testable import B2PCore

@Suite("応答の解析")
struct ResponseParserTests {
    let json = #"""
    {
      "revised": "来週の打ち合わせの日程を確認させてください。\n候補は火曜と水曜です。",
      "changes": [
        { "before": "打ち合わせの日程についてなのですが", "after": "来週の打ち合わせの日程を確認させてください。", "reason": "用件を冒頭に置くと、最初の一文で何の話かわかる。" }
      ],
      "minor": "「打合せ」を「打ち合わせ」に統一",
      "concerns": ["返信の期限が書かれていない"]
    }
    """#

    @Test func 正常なJSON() {
        guard case .structured(let r) = ResponseParser.parse(json) else {
            Issue.record("構造化できなかった"); return
        }
        #expect(r.revised.hasPrefix("来週の打ち合わせ"))
        #expect(r.revised.contains("\n"))
        #expect(r.changes.count == 1)
        #expect(r.changes[0].after == "来週の打ち合わせの日程を確認させてください。")
        #expect(r.minor == "「打合せ」を「打ち合わせ」に統一")
        #expect(r.concerns == ["返信の期限が書かれていない"])
    }

    @Test func コードフェンス付き() {
        let fenced = "\n  ```json\n" + json + "\n```  \n"
        guard case .structured(let r) = ResponseParser.parse(fenced) else {
            Issue.record("構造化できなかった"); return
        }
        #expect(r.changes.count == 1)
    }

    @Test func 言語名なしのコードフェンス() {
        guard case .structured = ResponseParser.parse("```\n" + json + "\n```") else {
            Issue.record("構造化できなかった"); return
        }
    }

    @Test func 壊れたJSONは応答をそのまま返す() {
        let broken = #"  {"revised": "途中で切れた応答", "changes": [ { "before": "あ"  "#
        #expect(ResponseParser.parse(broken) == .raw(#"{"revised": "途中で切れた応答", "changes": [ { "before": "あ""#))
    }

    @Test func JSONでない応答はそのまま返す() {
        #expect(ResponseParser.parse("すみません、うまく直せませんでした。") == .raw("すみません、うまく直せませんでした。"))
    }

    @Test func 前後に説明文が付いたJSON() {
        guard case .structured(let r) = ResponseParser.parse("以下が結果です。\n" + json + "\n以上です。") else {
            Issue.record("構造化できなかった"); return
        }
        #expect(r.concerns.count == 1)
    }

    @Test func 省略された項目は空で補う() {
        guard case .structured(let r) = ResponseParser.parse(#"{"revised": "本文", "concerns": "期限がない"}"#) else {
            Issue.record("構造化できなかった"); return
        }
        #expect(r.changes.isEmpty)
        #expect(r.minor.isEmpty)
        #expect(r.concerns == ["期限がない"])
    }

    @Test func revisedがなければ読めない扱い() {
        guard case .raw = ResponseParser.parse(#"{"changes": []}"#) else {
            Issue.record("raw になるはず"); return
        }
    }
}

@Suite("接続方式ごとの応答の取り出し")
struct ProviderParsingTests {
    @Test func Anthropicはtextブロックだけをつなぐ() throws {
        let data = Data(#"""
        {"content":[{"type":"thinking","thinking":""},{"type":"text","text":"{\"revised\":"},{"type":"text","text":"\"本文\"}"}],"stop_reason":"end_turn"}
        """#.utf8)
        #expect(try AnthropicProvider.extractText(from: data) == #"{"revised":"本文"}"#)
    }

    @Test func Anthropicの拒否() {
        let data = Data(#"{"content":[],"stop_reason":"refusal"}"#.utf8)
        #expect(throws: LLMError.refused) { try AnthropicProvider.extractText(from: data) }
    }

    @Test func Anthropicのエンドポイント() {
        let expected = "https://api.anthropic.com/v1/messages"
        #expect(AnthropicProvider.endpoint(baseURL: "https://api.anthropic.com")?.absoluteString == expected)
        #expect(AnthropicProvider.endpoint(baseURL: "https://api.anthropic.com/v1/")?.absoluteString == expected)
        #expect(AnthropicProvider.endpoint(baseURL: expected)?.absoluteString == expected)
        #expect(AnthropicProvider.endpoint(baseURL: "")?.absoluteString == expected)
    }

    @Test func temperatureを送るかどうか() {
        #expect(!AnthropicProvider.acceptsTemperature(model: "claude-sonnet-5"))
        #expect(!AnthropicProvider.acceptsTemperature(model: "claude-opus-5-5"))
        #expect(AnthropicProvider.acceptsTemperature(model: "claude-haiku-4-5-20251001"))
        let profile = ProfileConfig(name: "t", model: "claude-sonnet-5", instructions: "")
        let body = AnthropicProvider.requestBody(system: "s", user: "u", config: profile, includeTemperature: false)
        #expect(body["temperature"] == nil)
        #expect(body["max_tokens"] as? Int == 4096)
    }

    @Test func OpenAI互換の応答() throws {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"こんにちは"}}]}"#.utf8)
        #expect(try OpenAICompatibleProvider.extractText(from: data) == "こんにちは")
    }

    @Test func OpenAI互換のモデル一覧() throws {
        let data = Data(#"{"object":"list","data":[{"id":"qwen3:8b"},{"id":"gemma3:12b"}]}"#.utf8)
        #expect(try OpenAICompatibleProvider.extractModelIDs(from: data) == ["gemma3:12b", "qwen3:8b"])
    }

    @Test func OpenAI互換のURL() {
        #expect(OpenAICompatibleProvider.url(baseURL: "http://localhost:11434/v1/", path: "chat/completions")?.absoluteString
                == "http://localhost:11434/v1/chat/completions")
        #expect(OpenAICompatibleProvider.url(baseURL: "localhost", path: "models") == nil)
    }

    @Test func エラー本文の取り出し() {
        let anthropic = Data(#"{"type":"error","error":{"type":"invalid_request_error","message":"bad model"}}"#.utf8)
        #expect(HTTPClient.errorMessage(from: anthropic) == "bad model")
    }
}

@Suite("プロファイルとプロンプト")
struct ProfileTests {
    @Test func 出力形式は必ず末尾に付く() {
        let profile = ProfileConfig(name: "t", instructions: "自由に編集した指示")
        let system = PromptBuilder.system(for: profile)
        #expect(system.hasPrefix("自由に編集した指示"))
        #expect(system.hasSuffix(PromptBuilder.outputFormat))
        let empty = ProfileConfig(name: "t", instructions: "   ")
        #expect(PromptBuilder.system(for: empty) == PromptBuilder.outputFormat)
    }

    @Test func ローカルかクラウドか() {
        #expect(ProfileConfig(name: "a", provider: .openAICompatible, baseURL: "http://localhost:11434/v1", instructions: "").isLocal)
        #expect(ProfileConfig(name: "a", provider: .openAICompatible, baseURL: "http://127.0.0.1:1234/v1", instructions: "").isLocal)
        #expect(!ProfileConfig(name: "a", provider: .openAICompatible, baseURL: "https://api.openai.com/v1", instructions: "").isLocal)
        #expect(!ProfileConfig(name: "a", instructions: "").isLocal)
    }

    @Test func 既定のプロファイル() {
        let profiles = DefaultProfiles.make()
        #expect(profiles.map(\.name) == ["整える", "Slack", "メール", "記事"])
        #expect(profiles.allSatisfy { $0.provider == .anthropic && $0.instructions.hasPrefix(DefaultProfiles.common) })
    }

    @Test func 保存と読み込み() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        #expect(store.load().count == 4)
        var profiles = DefaultProfiles.make()
        profiles[0].name = "変えた"
        try store.save(profiles)
        #expect(store.load() == profiles)
    }

    @Test func 壊れたファイルは退避して既定に戻す() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ProfileStore(directory: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load().count == 4)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("profiles.broken.json").path))
    }
}

#if canImport(FoundationModels)
/// 実機の端末内モデルを呼ぶ。時間がかかるので B2P_ONDEVICE=1 のときだけ動かす。
@Suite("Apple 端末内モデル", .enabled(if: ProcessInfo.processInfo.environment["B2P_ONDEVICE"] == "1"))
struct AppleOnDeviceTests {
    @Test func 構造化生成で修正版と修正点が返る() async throws {
        guard #available(macOS 26.0, *), AppleOnDeviceProvider.unavailableReason() == nil else { return }
        var profile = DefaultProfiles.make()[1]
        profile.provider = .appleOnDevice
        let raw = try await AppleOnDeviceProvider().complete(
            system: PromptBuilder.system(for: profile),
            user: "明日の定例なんですが、資料がまだできてなくて、たぶん午後には共有できると思うんですけど、遅れたらすみません。",
            config: profile
        )
        print("RAW:", raw)
        guard case .structured(let result) = ResponseParser.parse(raw) else {
            Issue.record("構造化できなかった: \(raw)"); return
        }
        #expect(!result.revised.isEmpty)
    }
}
#endif

@Suite("速さ優先")
struct FastModeTests {
    @Test func 対応モデルではeffortをlowで送る() {
        let profile = ProfileConfig(name: "t", model: "claude-sonnet-5", instructions: "", fastMode: true)
        let body = AnthropicProvider.requestBody(system: "s", user: "u", config: profile, includeTemperature: false, includeEffort: true)
        #expect((body["output_config"] as? [String: String]) == ["effort": "low"])
        #expect(AnthropicProvider.supportsEffort(model: "claude-sonnet-5"))
        #expect(!AnthropicProvider.supportsEffort(model: "claude-haiku-4-5-20251001"))
    }

    @Test func オフならeffortを送らない() {
        let profile = ProfileConfig(name: "t", model: "claude-sonnet-5", instructions: "")
        let body = AnthropicProvider.requestBody(system: "s", user: "u", config: profile, includeTemperature: false)
        #expect(body["output_config"] == nil)
    }

    @Test func fastModeのない古いJSONも読める() throws {
        let old = Data(#"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"整える","provider":"anthropic","baseURL":"https://api.anthropic.com","model":"claude-sonnet-5","temperature":0.3,"instructions":"x"}]"#.utf8)
        let profiles = try ProfileStore.decode(old)
        #expect(profiles.count == 1)
        #expect(profiles[0].fastMode == false)
    }
}
