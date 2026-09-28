#if DEBUG
import AppKit
import B2PCore

/// 開発用。環境変数で見本データを入れ、自分のウィンドウを PNG に書き出して終了する。
///   B2P_DEMO=1  B2P_APPEARANCE=dark  B2P_SNAPSHOT=/path/to/out.png
@MainActor
enum DebugSnapshot {
    static func runIfRequested(model: AppModel) {
        let env = ProcessInfo.processInfo.environment
        if env["B2P_APPEARANCE"] == "dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
        if env["B2P_APPEARANCE"] == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
        if env["B2P_DEMO"] == "1" { loadDemo(into: model) }
        guard let path = env["B2P_SNAPSHOT"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && $0.frame.width > 600 }),
               let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]),
               let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }

    private static func loadDemo(into model: AppModel) {
        model.input = "来週の打合せなんですが、たぶん火曜か水曜が良いかなと思っていて、あと資料も事前に共有したほうが良いと思うのでそのへんも含めて確認させていただければ幸甚です。"
        model.revised = "来週の打ち合わせの日程を確認させてください。\n\n候補は火曜か水曜です。\n資料は事前に共有します。"
        model.changes = [
            RevisionChange(before: "来週の打合せなんですが", after: "来週の打ち合わせの日程を確認させてください。", reason: "用件を冒頭に置くと、最初の一文で何の話かわかる。"),
            RevisionChange(before: "たぶん火曜か水曜が良いかなと思っていて", after: "候補は火曜か水曜です。", reason: "根拠なく弱めた表現を外すと、候補がはっきり伝わる。"),
            RevisionChange(before: "幸甚です", after: "資料は事前に共有します。", reason: "難しい語をやめ、依頼と共有を別の文に分けた。"),
        ]
        model.minor = "「打合せ」を「打ち合わせ」に統一"
        model.concerns = ["返信の期限が書かれていない"]
        model.hasResult = true
        model.highlightRequest = HighlightRequest(text: "候補は火曜か水曜です。")
    }
}
#endif
