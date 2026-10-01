import AppKit
import B2PCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("一般", systemImage: "gearshape") }
            ProfilesSettingsView()
                .tabItem { Label("プロファイル", systemImage: "text.badge.checkmark") }
        }
        .tint(StudioTheme.accent)
    }
}

private struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var backgroundError: String?

    var body: some View {
        Form {
            Section("表示") {
                Toggle("修正版が出たら、修正点を自動で開く", isOn: $model.autoExpandChanges)
                Toggle("常に最前面に表示", isOn: $model.alwaysOnTop)
            }
            Section("テキストボックス") {
                HStack {
                    Slider(value: $model.textBackgroundTransparency, in: 0...1, step: 0.05) {
                        Text("背景の透明度")
                    }
                    .accessibilityLabel("テキストボックスの背景の透明度")
                    .accessibilityValue(model.textBackgroundTransparency.formatted(.percent.precision(.fractionLength(0))))
                    Text(model.textBackgroundTransparency.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .frame(width: 42, alignment: .trailing)
                }
                Text("入力欄と修正版欄に共通です。値を上げると、背後の画像が見えやすくなります。文字の濃さは変わりません。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("初期値は 0% です。100% で欄の背景が透明になります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("ショートカット") {
                LabeledContent("実行", value: "⌘↩")
                LabeledContent("中止", value: "Esc")
                LabeledContent("修正版をコピー", value: "⌃C　または　⌘⇧C")
                LabeledContent("プロファイルの切り替え", value: "⌘1〜⌘9")
                LabeledContent("常に最前面の切り替え", value: "⌥⌘T")
            }
            Section("背景") {
                Backdrop(image: model.backgroundImage, opacity: model.backgroundOpacity)
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("背景のプレビュー")
                HStack {
                    Button("画像を選ぶ…", action: chooseBackground)
                    Button("フォルダを選ぶ…", action: chooseBackgroundFolder)
                    if model.backgroundImage != nil {
                        Button("元の背景に戻す") {
                            do { try model.resetBackground() }
                            catch { backgroundError = "背景を戻せませんでした。もう一度お試しください。" }
                        }
                    }
                }
                if let folder = model.backgroundFolder {
                    LabeledContent("フォルダ", value: folder.lastPathComponent)
                    Picker("切り替え間隔", selection: $model.backgroundInterval) {
                        ForEach(Self.intervals, id: \.seconds) { Text($0.label).tag($0.seconds) }
                    }
                    Toggle("ランダムな順番にする", isOn: $model.backgroundShuffle)
                    HStack {
                        Button("次の画像へ") { model.advanceBackground() }
                        Button("シャッフル") { model.shuffleBackgroundNow() }
                        Button("フォルダの登録を解除") { model.clearBackgroundFolder() }
                    }
                }
                if model.backgroundImage != nil {
                    Slider(value: $model.backgroundOpacity, in: 0.1...0.8, step: 0.05) {
                        Text("画像の濃さ")
                    }
                }
                Text("下側ほど画像が淡くなります。画像は AI には送りません。フォルダ登録中は、アプリを開いている間、背景が切り替わります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .alert("背景を変更できません", isPresented: Binding(
            get: { backgroundError != nil }, set: { if !$0 { backgroundError = nil } }
        )) { Button("OK") {} } message: { Text(backgroundError ?? "") }
    }

    private static let intervals: [(label: String, seconds: Double)] = [
        ("30秒", 30), ("1分", 60), ("5分", 300), ("30分", 1800), ("1時間", 3600),
    ]

    private func chooseBackgroundFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "このフォルダを使う"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.setBackgroundFolder(url) }
        catch { backgroundError = "このフォルダに PNG・JPEG・HEIC・TIFF の画像が見つかりません。" }
    }

    private func chooseBackground() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "背景に使う"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { model.clearBackgroundFolder(); try model.setBackground(from: url) }
        catch { backgroundError = "画像を保存できませんでした。別の PNG や JPEG 画像を選んでください。" }
    }
}

private struct ProfilesSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var selection: UUID?
    @ViewState private var alertMessage: String?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                        HStack {
                            Text(profile.name)
                            Spacer()
                            if index < 9 {
                                Text("⌘\(index + 1)").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        .tag(profile.id)
                    }
                    .onMove { model.profiles.move(fromOffsets: $0, toOffset: $1) }
                }
                Divider()
                HStack(spacing: 2) {
                    Button { selection = model.addProfile() } label: { Image(systemName: "plus") }
                        .help("追加")
                    Button {
                        if let id = selection { delete(id) }
                    } label: { Image(systemName: "minus") }
                        .help("削除")
                        .disabled(selection == nil || model.profiles.count <= 1)
                    Button {
                        if let id = selection { selection = model.duplicateProfile(id: id) }
                    } label: { Image(systemName: "plus.square.on.square") }
                        .help("複製")
                        .disabled(selection == nil)
                    Spacer()
                    Menu {
                        Button("JSON に書き出す…", action: exportProfiles)
                        Button("JSON から読み込む…", action: importProfiles)
                    } label: { Image(systemName: "square.and.arrow.up.on.square") }
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("書き出し・読み込み")
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 190, idealWidth: 210, maxWidth: 280)

            Group {
                if let id = selection, let binding = binding(for: id) {
                    ProfileEditor(profile: binding)
                        .id(id)
                } else {
                    Text("左の一覧からプロファイルを選んでください。")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 540)
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear { selection = selection ?? model.selectedProfile?.id }
        .alert("エラー", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK") {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func binding(for id: UUID) -> Binding<ProfileConfig>? {
        guard let current = model.profiles.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: { model.profiles.first(where: { $0.id == id }) ?? current },
            set: { newValue in
                if let index = model.profiles.firstIndex(where: { $0.id == id }) {
                    model.profiles[index] = newValue
                }
            }
        )
    }

    private func delete(_ id: UUID) {
        let index = model.profiles.firstIndex { $0.id == id } ?? 0
        model.deleteProfile(id: id)
        selection = model.profiles[min(index, model.profiles.count - 1)].id
    }

    private func exportProfiles() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "B2P-profiles.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProfileStore.encode(model.profiles).write(to: url, options: .atomic)
        } catch {
            alertMessage = "書き出せませんでした：\(error.localizedDescription)"
        }
    }

    private func importProfiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try ProfileStore.decode(Data(contentsOf: url))
            model.importProfiles(imported)
        } catch {
            alertMessage = "読み込めませんでした。B2P で書き出した JSON か確認してください。"
        }
    }
}

// MARK: - プロファイルの編集

private struct ProfileEditor: View {
    @EnvironmentObject private var model: AppModel
    @Binding var profile: ProfileConfig

    @ViewState private var apiKey = ""
    @ViewState private var fetchedModels: [String] = []
    @ViewState private var modelListMessage: String?
    @ViewState private var isFetchingModels = false
    @ViewState private var test = TestState.idle

    private enum TestState {
        case idle, running
        case success(String, TimeInterval)
        case failure(String)
    }

    var body: some View {
        Form {
            Section {
                TextField("名前", text: $profile.name)
                Picker("接続方式", selection: providerBinding) {
                    ForEach(ProviderKind.available) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
            }

            if profile.provider.usesNetwork {
                connectionSection
            } else {
                appleSection
            }

            Section {
                Toggle(isOn: $profile.fastMode) {
                    Label("速さを優先する", systemImage: "bolt.fill")
                }
                Text(fastModeNote)
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("温度") {
                    HStack {
                        Slider(value: $profile.temperature, in: 0...1, step: 0.05)
                        Text(profile.temperature.formatted(.number.precision(.fractionLength(2))))
                            .monospacedDigit()
                            .frame(width: 36, alignment: .trailing)
                    }
                }
                if profile.provider == .anthropic, !AnthropicProvider.acceptsTemperature(model: profile.model) {
                    Text("このモデルは温度の指定を受け付けないため、送信しません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                TextEditor(text: $profile.instructions)
                    .font(.system(size: 13))
                    .frame(minHeight: 260)
            } header: {
                HStack {
                    Text("指示文")
                    Spacer()
                    Menu("既定の指示文を入れる") {
                        Button("整える（汎用）") { setInstructions(DefaultProfiles.general) }
                        Button("Slack") { setInstructions(DefaultProfiles.slack) }
                        Button("メール") { setInstructions(DefaultProfiles.mail) }
                        Button("記事") { setInstructions(DefaultProfiles.article) }
                    }
                    .fixedSize()
                }
            } footer: {
                Text("出力形式（JSON）の指定は、アプリが指示文の末尾に自動で付けます。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack(alignment: .firstTextBaseline) {
                    Button("接続テスト", action: runTest)
                        .disabled(isTestRunning)
                    testResult
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { loadKey() }
        .onChange(of: profile.provider) {
            loadKey()
            fetchedModels = []
            modelListMessage = nil
            test = .idle
        }
    }

    // MARK: 接続先

    private var connectionSection: some View {
        Section {
            HStack {
                TextField("接続先 URL", text: $profile.baseURL)
                if profile.provider == .openAICompatible {
                    Menu("候補") {
                        ForEach(OpenAIPreset.allCases) { preset in
                            Button("\(preset.name)　\(preset.url)") { profile.baseURL = preset.url }
                        }
                    }
                    .fixedSize()
                }
            }
            HStack {
                TextField("モデル名", text: $profile.model)
                if profile.provider == .anthropic {
                    Menu("候補") {
                        Button(ProviderKind.anthropic.defaultModel) { profile.model = ProviderKind.anthropic.defaultModel }
                        Button("claude-haiku-4-5-20251001（軽く安く）") { profile.model = "claude-haiku-4-5-20251001" }
                    }
                    .fixedSize()
                } else {
                    if !fetchedModels.isEmpty {
                        Menu("選ぶ") {
                            ForEach(fetchedModels, id: \.self) { name in
                                Button(name) { profile.model = name }
                            }
                        }
                        .fixedSize()
                    }
                    Button(isFetchingModels ? "取得中…" : "一覧を取得", action: fetchModels)
                        .disabled(isFetchingModels)
                }
            }
            if let modelListMessage {
                Text(modelListMessage).font(.caption).foregroundStyle(.secondary)
            }
            SecureField("API キー", text: $apiKey, prompt: Text(profile.provider == .anthropic ? "sk-ant-…" : "ローカルなら空でよい"))
                .onChange(of: apiKey) { model.setAPIKey(apiKey, for: profile.provider) }
        } footer: {
            Text("API キーは Keychain に保存し、\(profile.provider.shortName) を使うプロファイルすべてで共有します。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var appleSection: some View {
        Section {
            if let reason = appleUnavailableReason {
                Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
            } else {
                Label("この Mac の中だけで動きます。API キーは不要です。", systemImage: "checkmark.circle")
            }
        }
    }

    private var appleUnavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return AppleOnDeviceProvider.unavailableReason() }
        #endif
        return "Apple Intelligence は macOS 26 以降で使えます。"
    }

    private var fastModeNote: String {
        switch profile.provider {
        case .anthropic:
            AnthropicProvider.supportsEffort(model: profile.model)
                ? "AI が答える前に考える量を最小にして、応答を速くします。推敲の質は少し下がることがあります。"
                : "このモデルはもともと考える時間をとらないため、オンにしても速さは変わりません。"
        case .openAICompatible:
            "OpenAI 互換の接続では速くなりません。速くしたいときは、小さいモデルを選んでください。"
        case .appleOnDevice:
            "Apple Intelligence では速くなりません。"
        }
    }

    private var providerBinding: Binding<ProviderKind> {
        Binding(
            get: { profile.provider },
            set: { kind in
                guard kind != profile.provider else { return }
                profile.provider = kind
                profile.baseURL = kind.defaultBaseURL
                profile.model = kind.defaultModel
            }
        )
    }

    private func setInstructions(_ specific: String) {
        profile.instructions = DefaultProfiles.common + "\n\n" + specific
    }

    private func loadKey() {
        apiKey = profile.provider.usesNetwork ? (model.apiKey(for: profile.provider) ?? "") : ""
    }

    private func fetchModels() {
        isFetchingModels = true
        modelListMessage = nil
        let provider = OpenAICompatibleProvider(apiKey: apiKey)
        let baseURL = profile.baseURL
        Task {
            defer { isFetchingModels = false }
            do {
                fetchedModels = try await provider.listModels(baseURL: baseURL)
                modelListMessage = fetchedModels.isEmpty ? "モデルが見つかりませんでした。モデル名を手で入力してください。" : "\(fetchedModels.count)件のモデルを取得しました。"
            } catch {
                fetchedModels = []
                modelListMessage = "一覧を取得できませんでした（\(error.localizedDescription)）。モデル名を手で入力してください。"
            }
        }
    }

    // MARK: 接続テスト

    private var isTestRunning: Bool {
        if case .running = test { return true }
        return false
    }

    @ViewBuilder
    private var testResult: some View {
        switch test {
        case .idle:
            Text("短い文を送り、応答と所要時間を表示します。").font(.caption).foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .success(let reply, let seconds):
            VStack(alignment: .leading, spacing: 2) {
                Label("\(seconds.formatted(.number.precision(.fractionLength(1)))) 秒で応答がありました", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(reply).font(.caption).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            }
        case .failure(let message):
            Label(message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func runTest() {
        let profile = self.profile
        let provider: any LLMProvider
        do {
            provider = try ProviderFactory.make(for: profile, apiKey: apiKey)
        } catch {
            test = .failure(error.localizedDescription)
            return
        }
        test = .running
        Task {
            let start = Date()
            do {
                let reply = try await provider.complete(
                    system: "短く答えてください。",
                    user: "接続テストです。「OK」とだけ返してください。",
                    config: profile
                )
                let text: String
                if case .structured(let result) = ResponseParser.parse(reply) { text = result.revised } else { text = reply }
                test = .success(text.trimmingCharacters(in: .whitespacesAndNewlines), Date().timeIntervalSince(start))
            } catch {
                test = .failure(error.localizedDescription)
            }
        }
    }
}
