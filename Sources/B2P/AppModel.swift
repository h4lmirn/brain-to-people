import AppKit
import B2PCore
import SwiftUI

struct HighlightRequest: Equatable {
    let id = UUID()
    let text: String
}

@MainActor
final class AppModel: ObservableObject {
    private enum Keys {
        static let draft = "draft"
        static let selectedProfile = "selectedProfileID"
        static let alwaysOnTop = "alwaysOnTop"
        static let autoExpandChanges = "autoExpandChanges"
        static let addedAppleProfile = "addedAppleProfile"
        static let backgroundOpacity = "backgroundOpacity"
        static let textBackgroundTransparency = "textBackgroundTransparency"
    }

    @Published var profiles: [ProfileConfig] {
        didSet { saveProfiles() }
    }
    @Published var selectedProfileID: UUID? {
        didSet { defaults.set(selectedProfileID?.uuidString, forKey: Keys.selectedProfile) }
    }
    /// 入力中の下書き。起動しなおしても残す。
    @Published var input: String {
        didSet { defaults.set(input, forKey: Keys.draft) }
    }

    /// ウィンドウを常に最前面に表示する。
    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Keys.alwaysOnTop) }
    }
    /// 修正版が出たら修正点の欄を自動で開く。
    @Published var autoExpandChanges: Bool {
        didSet { defaults.set(autoExpandChanges, forKey: Keys.autoExpandChanges) }
    }

    @Published var revised = ""
    @Published private(set) var backgroundImage: NSImage?
    @Published var backgroundOpacity: Double {
        didSet { defaults.set(backgroundOpacity, forKey: Keys.backgroundOpacity) }
    }
    /// 入力欄と修正版欄で共通。0 はすりガラスを最も強く、1 は背景を完全に透かす。
    @Published var textBackgroundTransparency: Double {
        didSet { defaults.set(textBackgroundTransparency, forKey: Keys.textBackgroundTransparency) }
    }
    @Published var changes: [RevisionChange] = []
    @Published var minor = ""
    @Published var concerns: [String] = []
    @Published var parseNotice: String?
    @Published var errorMessage: String?
    @Published var hasResult = false
    @Published var isRunning = false
    @Published var highlightRequest: HighlightRequest?
    /// 結果を受け取るたびに増える。修正点の自動展開のきっかけに使う。
    @Published var resultCount = 0
    /// コピー直後の「コピーしました」表示用。
    @Published var justCopied = false

    private let defaults = UserDefaults.standard
    private let store = ProfileStore()
    private let keychain = KeychainStore()
    private let backgroundStore = BackgroundImageStore()
    private var task: Task<Void, Never>?
    private var runID: UUID?
    private var copyFeedbackID: UUID?
    private var keyMonitor: Any?

    init() {
        let loaded = store.load()
        profiles = loaded
        input = defaults.string(forKey: Keys.draft) ?? ""
        let saved = defaults.string(forKey: Keys.selectedProfile).flatMap(UUID.init(uuidString:))
        selectedProfileID = loaded.contains { $0.id == saved } ? saved : loaded.first?.id
        alwaysOnTop = defaults.bool(forKey: Keys.alwaysOnTop)
        autoExpandChanges = defaults.object(forKey: Keys.autoExpandChanges) as? Bool ?? true
        backgroundImage = backgroundStore.load()
        backgroundOpacity = min(0.8, max(0.1, defaults.object(forKey: Keys.backgroundOpacity) as? Double ?? 0.35))
        let transparency = defaults.object(forKey: Keys.textBackgroundTransparency) as? Double ?? 0
        textBackgroundTransparency = transparency.isFinite ? min(1, max(0, transparency)) : 0
        if !FileManager.default.fileExists(atPath: store.fileURL.path) { saveProfiles() }
        addAppleProfileOnce()
        installControlCMonitor()
    }

    /// Apple Intelligence が使える Mac では、端末内で動くプロファイルを一度だけ足す。
    /// 消した後にまた足されないよう、足したことを覚えておく。
    private func addAppleProfileOnce() {
        guard AppleOnDevice.isSupportedOS, !defaults.bool(forKey: Keys.addedAppleProfile) else { return }
        defaults.set(true, forKey: Keys.addedAppleProfile)
        guard !profiles.contains(where: { $0.provider == .appleOnDevice }) else { return }
        profiles.append(ProfileConfig(
            name: "整える（Apple Intelligence）",
            provider: .appleOnDevice,
            instructions: DefaultProfiles.common + "\n\n" + DefaultProfiles.general
        ))
    }

    /// Control+C で修正版をコピーする。⌘C は通常のコピーのまま残す。
    private func installControlCMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == .control, event.charactersIgnoringModifiers?.lowercased() == "c" else { return event }
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, !self.revised.isEmpty else { return false }
                self.copyRevised()
                return true
            }
            return handled ? nil : event
        }
    }

    var selectedProfile: ProfileConfig? {
        profiles.first { $0.id == selectedProfileID } ?? profiles.first
    }

    // MARK: 実行

    func setBackground(from url: URL) throws {
        backgroundImage = try backgroundStore.save(from: url)
    }

    func resetBackground() throws {
        try backgroundStore.remove()
        backgroundImage = nil
    }

    func run() {
        guard !isRunning, let profile = selectedProfile else { return }
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        errorMessage = nil

        let provider: any LLMProvider
        do {
            provider = try ProviderFactory.make(for: profile, apiKey: apiKey(for: profile.provider))
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        let system = PromptBuilder.system(for: profile)
        let user = input
        let id = UUID()
        runID = id
        isRunning = true

        task = Task {
            defer {
                if runID == id {
                    isRunning = false
                    task = nil
                }
            }
            do {
                let raw = try await provider.complete(system: system, user: user, config: profile)
                guard runID == id, !Task.isCancelled else { return }
                apply(ResponseParser.parse(raw))
            } catch is CancellationError {
                // 中止した
            } catch {
                guard runID == id, !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        runID = nil
        isRunning = false
    }

    private func apply(_ response: ParsedResponse) {
        switch response {
        case .structured(let result):
            revised = result.revised
            changes = result.changes
            minor = result.minor
            concerns = result.concerns
            parseNotice = nil
        case .raw(let text):
            revised = text
            changes = []
            minor = ""
            concerns = []
            parseNotice = "修正点を読み取れませんでした"
        }
        highlightRequest = nil
        hasResult = true
        resultCount += 1
    }

    func highlight(_ change: RevisionChange) {
        highlightRequest = HighlightRequest(text: change.after)
    }

    func copyRevised() {
        guard !revised.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(revised, forType: .string)
        let id = UUID()
        copyFeedbackID = id
        justCopied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copyFeedbackID == id { justCopied = false }
        }
    }

    // MARK: プロファイル

    func selectProfile(at index: Int) {
        guard profiles.indices.contains(index) else { return }
        selectedProfileID = profiles[index].id
    }

    @discardableResult
    func addProfile() -> UUID {
        let profile = ProfileConfig(name: "新しいプロファイル", instructions: DefaultProfiles.common + "\n\n" + DefaultProfiles.general)
        profiles.append(profile)
        return profile.id
    }

    @discardableResult
    func duplicateProfile(id: UUID) -> UUID? {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return nil }
        var copy = profiles[index]
        copy.id = UUID()
        copy.name += " のコピー"
        profiles.insert(copy, at: index + 1)
        return copy.id
    }

    /// 最後の1つは消さない。
    func deleteProfile(id: UUID) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == id }
        if selectedProfileID == id { selectedProfileID = profiles.first?.id }
    }

    func importProfiles(_ imported: [ProfileConfig]) {
        profiles += imported.map { var p = $0; p.id = UUID(); return p }
    }

    private func saveProfiles() {
        do {
            try store.save(profiles)
        } catch {
            errorMessage = "プロファイルを保存できませんでした：\(error.localizedDescription)"
        }
    }

    // MARK: API キー

    func apiKey(for kind: ProviderKind) -> String? {
        keychain.read(account: kind.rawValue)
    }

    func setAPIKey(_ key: String, for kind: ProviderKind) {
        keychain.write(key, account: kind.rawValue)
    }
}
