import AppKit
import B2PCore
import Carbon.HIToolbox
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
        static let backgroundFolder = "backgroundFolderPath"
        static let backgroundInterval = "backgroundInterval"
        static let backgroundShuffle = "backgroundShuffle"
        static let textBackgroundTransparency = "textBackgroundTransparency"
        static let globalHotKey = "globalHotKeyEnabled"
        static let captureClipboard = "captureClipboardOnCall"
        static let autoRunOnCall = "autoRunOnCall"
        static let autoCopyRevised = "autoCopyRevised"
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
    /// 背景を切り替えるフォルダ。登録中は、選んだ1枚よりこちらを優先する。
    @Published private(set) var backgroundFolder: URL?
    /// 切り替えの間隔（秒）。
    @Published var backgroundInterval: Double {
        didSet {
            defaults.set(backgroundInterval, forKey: Keys.backgroundInterval)
            scheduleSlideshow()
        }
    }
    @Published var backgroundShuffle: Bool {
        didSet { defaults.set(backgroundShuffle, forKey: Keys.backgroundShuffle) }
    }
    /// 入力欄と修正版欄で共通。0 はすりガラスを最も強く、1 は背景を完全に透かす。
    @Published var textBackgroundTransparency: Double {
        didSet { defaults.set(textBackgroundTransparency, forKey: Keys.textBackgroundTransparency) }
    }
    /// どのアプリからでも ⌃⌥B で呼び出す。
    @Published var globalHotKeyEnabled: Bool {
        didSet {
            defaults.set(globalHotKeyEnabled, forKey: Keys.globalHotKey)
            updateHotKey()
        }
    }
    /// 呼び出したとき、クリップボードの文章を入力欄に入れる。
    @Published var captureClipboard: Bool {
        didSet { defaults.set(captureClipboard, forKey: Keys.captureClipboard) }
    }
    /// 呼び出したら、すぐ整える。
    @Published var autoRunOnCall: Bool {
        didSet { defaults.set(autoRunOnCall, forKey: Keys.autoRunOnCall) }
    }
    /// 整え終わったら、修正版を自動でコピーする。
    @Published var autoCopyRevised: Bool {
        didSet { defaults.set(autoCopyRevised, forKey: Keys.autoCopyRevised) }
    }
    /// 返事の待ち状態。.connecting は最初の文字が届くまで、.writing は届き始めてから。
    enum RunPhase { case idle, connecting, writing }
    @Published private(set) var runPhase = RunPhase.idle
    @Published private(set) var runStartedAt: Date?
    /// 修正点の行にカーソルを重ねている間、修正版の該当部分を濃くする。
    @Published var emphasisText: String?
    /// 呼び出しで入力欄を置き換えたときの、置き換え前の文章。
    @Published private(set) var replacedInput: String?
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

    private let defaults: UserDefaults
    private let store: ProfileStore
    private let keychain: KeychainStore
    private let backgroundStore: BackgroundImageStore
    private var task: Task<Void, Never>?
    private var runID: UUID?
    private var copyFeedbackID: UUID?
    private var keyMonitor: Any?
    private var slideshowTimer: Timer?
    private let hotKey = GlobalHotKey()
    private var runSnapshot: ResultSnapshot?
    private var replacedInputID: UUID?
    private var currentBackgroundFile: URL?

    init(defaults: UserDefaults = .standard, store: ProfileStore = ProfileStore(),
         keychain: KeychainStore = KeychainStore(), backgroundStore: BackgroundImageStore = BackgroundImageStore()) {
        self.defaults = defaults
        self.store = store
        self.keychain = keychain
        self.backgroundStore = backgroundStore
        let loaded = store.load()
        profiles = loaded
        input = defaults.string(forKey: Keys.draft) ?? ""
        let saved = defaults.string(forKey: Keys.selectedProfile).flatMap(UUID.init(uuidString:))
        selectedProfileID = loaded.contains { $0.id == saved } ? saved : loaded.first?.id
        alwaysOnTop = defaults.bool(forKey: Keys.alwaysOnTop)
        autoExpandChanges = defaults.object(forKey: Keys.autoExpandChanges) as? Bool ?? true
        backgroundImage = backgroundStore.load()
        backgroundOpacity = min(0.8, max(0.1, defaults.object(forKey: Keys.backgroundOpacity) as? Double ?? 0.35))
        let interval = defaults.object(forKey: Keys.backgroundInterval) as? Double ?? 300
        backgroundInterval = interval.isFinite && interval >= 10 ? interval : 300
        backgroundShuffle = defaults.bool(forKey: Keys.backgroundShuffle)
        globalHotKeyEnabled = defaults.object(forKey: Keys.globalHotKey) as? Bool ?? true
        captureClipboard = defaults.object(forKey: Keys.captureClipboard) as? Bool ?? true
        autoRunOnCall = defaults.bool(forKey: Keys.autoRunOnCall)
        autoCopyRevised = defaults.bool(forKey: Keys.autoCopyRevised)
        let transparency = defaults.object(forKey: Keys.textBackgroundTransparency) as? Double ?? 0
        textBackgroundTransparency = transparency.isFinite ? min(1, max(0, transparency)) : 0
        if !FileManager.default.fileExists(atPath: store.fileURL.path) { saveProfiles() }
        addAppleProfileOnce()
        installControlCMonitor()
        hotKey.onPress = { [weak self] in
            Task { @MainActor in self?.quickCapture() }
        }
        updateHotKey()
        if let path = defaults.string(forKey: Keys.backgroundFolder) {
            backgroundFolder = URL(fileURLWithPath: path, isDirectory: true)
            advanceBackground()
            scheduleSlideshow()
        }
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
        clearBackgroundFolder()
        try backgroundStore.remove()
        backgroundImage = nil
    }

    /// フォルダを登録して、すぐ1枚目を出す。画像が1枚もなければ登録しない。
    func setBackgroundFolder(_ url: URL) throws {
        guard !BackgroundFolder.images(in: url).isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
        backgroundFolder = url
        currentBackgroundFile = nil
        defaults.set(url.path, forKey: Keys.backgroundFolder)
        advanceBackground()
        scheduleSlideshow()
    }

    func clearBackgroundFolder() {
        slideshowTimer?.invalidate()
        slideshowTimer = nil
        backgroundFolder = nil
        currentBackgroundFile = nil
        defaults.removeObject(forKey: Keys.backgroundFolder)
        backgroundImage = backgroundStore.load()
    }

    /// 次の画像へ進める。読めない画像は飛ばす。フォルダの中身は毎回数えなおす。
    func advanceBackground() { advanceBackground(shuffle: backgroundShuffle) }

    /// 順番の設定にかかわらず、フォルダの中からランダムに1枚選んで今すぐ切り替える。
    func shuffleBackgroundNow() { advanceBackground(shuffle: true) }

    private func advanceBackground(shuffle: Bool) {
        guard let folder = backgroundFolder else { return }
        var images = BackgroundFolder.images(in: folder)
        var file = currentBackgroundFile
        while let candidate = BackgroundFolder.next(after: file, in: images, shuffle: shuffle) {
            if let cg = BackgroundImageStore.thumbnail(at: candidate) {
                currentBackgroundFile = candidate
                // 背景とすりガラスのパネルが、同じ3秒のクロスフェードで切り替わる。
                withAnimation(.easeInOut(duration: 3)) {
                    backgroundImage = NSImage(cgImage: cg, size: .zero)
                }
                return
            }
            images.removeAll { $0 == candidate }
            file = candidate
        }
    }

    private func scheduleSlideshow() {
        slideshowTimer?.invalidate()
        slideshowTimer = nil
        guard backgroundFolder != nil else { return }
        slideshowTimer = Timer.scheduledTimer(withTimeInterval: backgroundInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advanceBackground() }
        }
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
        runSnapshot = ResultSnapshot(self)
        runStartedAt = Date()
        runPhase = .connecting
        isRunning = true

        task = Task {
            defer {
                if runID == id {
                    isRunning = false
                    runPhase = .idle
                    runStartedAt = nil
                    runSnapshot = nil
                    task = nil
                }
            }
            do {
                var raw = ""
                for try await chunk in provider.stream(system: system, user: user, config: profile) {
                    guard runID == id, !Task.isCancelled else { return }
                    if runPhase == .connecting { beginWriting() }
                    raw += chunk
                    // 修正版は、届いたところまでを順に見せる。修正点などは最後にまとめて出す。
                    if let partial = PartialJSON.revisedText(in: raw), partial != revised { revised = partial }
                }
                guard runID == id, !Task.isCancelled else { return }
                apply(ResponseParser.parse(raw))
            } catch is CancellationError {
                // 中止した
            } catch {
                guard runID == id, !Task.isCancelled else { return }
                runSnapshot?.restore(into: self)
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        runID = nil
        isRunning = false
        runPhase = .idle
        runStartedAt = nil
        runSnapshot?.restore(into: self)
        runSnapshot = nil
    }

    /// 最初の文字が届いたら、前の結果を片づけて、修正版を書き込む状態にする。
    private func beginWriting() {
        runPhase = .writing
        revised = ""
        changes = []
        minor = ""
        concerns = []
        parseNotice = nil
        hasResult = false
        highlightRequest = nil
        emphasisText = nil
    }

    /// 実行前の結果。中止やエラーのときに戻す。
    private struct ResultSnapshot {
        let revised: String
        let changes: [RevisionChange]
        let minor: String
        let concerns: [String]
        let parseNotice: String?
        let hasResult: Bool

        @MainActor init(_ model: AppModel) {
            revised = model.revised
            changes = model.changes
            minor = model.minor
            concerns = model.concerns
            parseNotice = model.parseNotice
            hasResult = model.hasResult
        }

        @MainActor func restore(into model: AppModel) {
            model.revised = revised
            model.changes = changes
            model.minor = minor
            model.concerns = concerns
            model.parseNotice = parseNotice
            model.hasResult = hasResult
        }
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
        if autoCopyRevised { copyRevised() }
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

    // MARK: クイック呼び出し

    private func updateHotKey() {
        if globalHotKeyEnabled {
            hotKey.register(keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey)
        } else {
            hotKey.unregister()
        }
    }

    /// ⌃⌥B で呼ばれたとき。ウィンドウを前に出し、設定に応じて、クリップボードの文章を入れて整える。
    func quickCapture() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Brain-to-People" }) {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
        if captureClipboard, let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty, text != input.trimmingCharacters(in: .whitespacesAndNewlines), text != revised {
            let old = input
            if !old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { offerUndo(of: old) }
            input = text
        }
        if autoRunOnCall { run() }
    }

    /// 置き換えた入力欄を、10秒のあいだ元に戻せるようにする。
    private func offerUndo(of old: String) {
        let id = UUID()
        replacedInputID = id
        replacedInput = old
        Task {
            try? await Task.sleep(for: .seconds(10))
            if replacedInputID == id { replacedInput = nil }
        }
    }

    func undoReplacedInput() {
        guard let old = replacedInput else { return }
        input = old
        replacedInput = nil
    }

    func dismissReplacedInput() { replacedInput = nil }

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
