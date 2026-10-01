import Foundation

/// 届いている途中の JSON から、"revised" の文字列を読めるところまで取り出す。
public enum PartialJSON {
    /// "revised" の値を返す。まだキーや開きの引用符が届いていなければ nil。
    /// 末尾が途中で切れたエスケープ（`\` や `\u00` など）は、続きが届くまで含めない。
    public static func revisedText(in raw: String) -> String? {
        guard let key = raw.range(of: "\"revised\"") else { return nil }
        let scalars = Array(raw[key.upperBound...].unicodeScalars)
        var i = 0
        func skipSpaces() { while i < scalars.count, scalars[i].properties.isWhitespace { i += 1 } }
        skipSpaces()
        guard i < scalars.count, scalars[i] == ":" else { return nil }
        i += 1
        skipSpaces()
        guard i < scalars.count, scalars[i] == "\"" else { return nil }
        i += 1

        var out = String.UnicodeScalarView()
        while i < scalars.count {
            let c = scalars[i]
            if c == "\"" { break }
            guard c == "\\" else { out.append(c); i += 1; continue }
            guard i + 1 < scalars.count else { break }
            switch scalars[i + 1] {
            case "n": out.append("\n"); i += 2
            case "t": out.append("\t"); i += 2
            case "r", "b", "f": i += 2
            case "u":
                guard let (scalar, used) = unicodeEscape(scalars, at: i) else { return String(out) }
                out.append(scalar); i += used
            default: out.append(scalars[i + 1]); i += 2
            }
        }
        return String(out)
    }

    /// `\uXXXX`（上位サロゲートなら続く `\uXXXX` も）を読む。足りなければ nil。
    private static func unicodeEscape(_ s: [Unicode.Scalar], at i: Int) -> (Unicode.Scalar, Int)? {
        func hex(_ start: Int) -> UInt32? {
            guard start + 6 <= s.count, s[start] == "\\", s[start + 1] == "u" else { return nil }
            var value: UInt32 = 0
            for k in 2..<6 {
                guard let d = Character(s[start + k]).hexDigitValue else { return nil }
                value = value * 16 + UInt32(d)
            }
            return value
        }
        guard let first = hex(i) else { return nil }
        if (0xD800...0xDBFF).contains(first) {
            guard let second = hex(i + 6), (0xDC00...0xDFFF).contains(second),
                  let scalar = Unicode.Scalar(0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)) else { return nil }
            return (scalar, 12)
        }
        guard let scalar = Unicode.Scalar(first) else { return nil }
        return (scalar, 6)
    }
}

/// ストリーミング応答の 1 イベントから取り出した内容。
public enum StreamEvent: Equatable, Sendable {
    case text(String)
    case refusal
    case failure(String)
    case ignored
}

public extension LLMProvider {
    /// 応答を断片ごとに返す。ストリーミングに対応しない接続方式は、全文を1回で返す。
    func stream(system: String, user: String, config: ProfileConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await complete(system: system, user: user, config: config))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
