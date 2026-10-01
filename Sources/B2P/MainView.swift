import B2PCore
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var changesExpanded = true
    @ViewState private var backdropFrame = CGRect.zero
    @ViewState private var selectedPane = 0

    var body: some View {
        GeometryReader { window in
            ZStack {
                Backdrop(image: model.backgroundImage, opacity: model.backgroundOpacity, tracksFrame: true)
                VStack(spacing: 18) {
                    masthead
                    controls
                    if let message = model.errorMessage { errorBanner(message) }
                    if model.replacedInput != nil { replacedInputBanner }
                    GeometryReader { geometry in
                        if geometry.size.width >= 720 {
                            HStack(spacing: 16) { inputPane; revisedPane }
                        } else {
                            VStack(spacing: 12) {
                                Picker("表示する欄", selection: $selectedPane) {
                                    Text("01  入力").tag(0)
                                    Text("02  修正版").tag(1)
                                }
                                .pickerStyle(.segmented).labelsHidden()
                                .accessibilityLabel("表示する欄")
                                if selectedPane == 0 { inputPane } else { revisedPane }
                            }
                        }
                    }
                    ChangesPanel(expanded: $changesExpanded,
                                 maxContentHeight: min(220, max(80, window.size.height - 580)))

                }
                .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 18)
            }
            .foregroundStyle(StudioTheme.ink).tint(StudioTheme.accent)
            .coordinateSpace(name: "mainBackdrop")
            .environment(\.frostedBackdropFrame, backdropFrame)
            .onPreferenceChange(BackdropFramePreference.self) { backdropFrame = $0 }
            .background(WindowConfigurator(alwaysOnTop: model.alwaysOnTop))
            .onChange(of: model.resultCount) {
                selectedPane = 1
                if model.autoExpandChanges {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { changesExpanded = true }
                }
            }
            .onChange(of: model.highlightRequest?.id) { selectedPane = 1 }
            .onChange(of: model.isRunning) { if model.isRunning { selectedPane = 1 } }
            .toolbarBackground(.hidden, for: .windowToolbar)
            #if DEBUG
            .onAppear { DebugSnapshot.runIfRequested(model: model) }
            #endif
        }
        .frame(minWidth: 600, minHeight: 640)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.errorMessage != nil)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.justCopied)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: model.replacedInput != nil)
    }

    private var masthead: some View {
        HStack(spacing: 13) {
            BrandMark()
            Text("Brain-to-People").font(.system(size: 21, weight: .semibold)).tracking(-0.7)
            Spacer(minLength: 12)
            Button { model.alwaysOnTop.toggle() } label: {
                Image(systemName: model.alwaysOnTop ? "pin.fill" : "pin")
                    .foregroundStyle(model.alwaysOnTop ? StudioTheme.accent : StudioTheme.ink).frame(width: 16)
            }
            .buttonStyle(StudioButtonStyle(compact: true))
            .accessibilityLabel("常に最前面").accessibilityValue(model.alwaysOnTop ? "オン" : "オフ")
            .help("常に最前面（⌥⌘T）")
            SettingsLink { Image(systemName: "slider.horizontal.3").frame(width: 16) }
                .buttonStyle(StudioButtonStyle(compact: true))
                .accessibilityLabel("設定").help("設定（⌘,）")
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                StudioEyebrow(text: "WRITE FOR")
                Menu {
                    Picker("プロファイル", selection: $model.selectedProfileID) {
                        ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                            Text(index < 9 ? "\(profile.name)　⌘\(index + 1)" : profile.name).tag(Optional(profile.id))
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 8) {
                        Text(model.selectedProfile?.name ?? "プロファイル")
                            .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        if model.selectedProfile?.fastMode == true {
                            Image(systemName: "bolt.fill").foregroundStyle(StudioTheme.accent)
                        }
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                    }
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden)
                .frame(maxWidth: 240, alignment: .leading)
                .accessibilityLabel("プロファイル").help("プロファイル（⌘1〜⌘9）")
            }
            Spacer(minLength: 6)
            if let profile = model.selectedProfile {
                HStack(spacing: 6) {
                    Circle().fill(profile.isLocal ? Color.green : StudioTheme.accent).frame(width: 5, height: 5)
                    Text(profile.isLocal ? "ローカル" : "クラウド").font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.secondary).fixedSize()
                .help(profile.isLocal ? "文章はこの Mac の外に送られません" : "文章は \(profile.provider.shortName) のサーバーに送られます")
            }
            Button {
                if model.isRunning { model.cancel() } else { model.run() }
            } label: {
                HStack(spacing: 12) {
                    Text(model.isRunning ? "中止" : "整える")
                    if model.isRunning {
                        Image(systemName: "stop.fill").font(.system(size: 9))
                    } else {
                        Text("⌘↩").font(.system(size: 11, weight: .regular)).opacity(0.7)
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                    }
                }.frame(minWidth: 100)
            }
            .buttonStyle(StudioButtonStyle(prominent: true))
            .disabled(!model.isRunning && model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(model.isRunning ? "中止（Esc）" : "実行（⌘Enter）")
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(StudioTheme.paper.opacity(0.66), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(StudioTheme.line, lineWidth: 0.5))
    }

    /// 背景の画像が透けているときだけ、文字の周りに薄い縁取りを付ける。
    private var haloStrength: Double {
        model.backgroundImage == nil ? 0 : model.textBackgroundTransparency
    }

    private var replacedInputBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard").foregroundStyle(StudioTheme.accent)
            Text("入力欄をクリップボードの文章に置き換えました。").font(.system(size: 12))
            Spacer(minLength: 8)
            Button("元に戻す") { model.undoReplacedInput() }
                .buttonStyle(StudioButtonStyle(compact: true))
            Button { model.dismissReplacedInput() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("閉じる")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(StudioTheme.paper.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(StudioTheme.line, lineWidth: 0.5))
        .transition(.opacity)
    }

    private var escapeHandler: () -> Bool {
        let model = model
        return {
            guard model.isRunning else { return false }
            model.cancel()
            return true
        }
    }

    private var inputPane: some View {
        EditorPane(number: "01", eyebrow: "YOUR THOUGHTS", title: "入力",
                   count: model.input.count,
                   backgroundOpacity: 1 - model.textBackgroundTransparency) {
            Image(systemName: "pencil.line").font(.system(size: 16, weight: .light)).foregroundStyle(.secondary)
        } content: {
            TextArea(text: $model.input, placeholder: "入力…", haloStrength: haloStrength,
                     onEscape: escapeHandler)
                .accessibilityLabel("入力")
        }
    }

    private var revisedPane: some View {
        EditorPane(number: "02", eyebrow: "READY FOR PEOPLE", title: "修正版",
                   count: model.revised.count,
                   backgroundOpacity: 1 - model.textBackgroundTransparency) {
            HStack(spacing: 10) {
                if model.runPhase == .writing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("書いています").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
                Button { model.copyRevised() } label: {
                    Label(model.justCopied ? "コピー済み" : "コピー", systemImage: model.justCopied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(StudioButtonStyle(compact: true)).disabled(model.revised.isEmpty || model.isRunning)
                .help("修正版をコピー（⌃C / ⌘⇧C）")
            }
        } content: {
            TextArea(text: $model.revised,
                     highlight: model.highlightRequest,
                     marks: model.isRunning ? [] : model.changes.map {
                         TextMark(text: $0.after, note: "元の文：\($0.before)" + ($0.reason.isEmpty ? "" : "\n理由：\($0.reason)"))
                     },
                     emphasis: model.emphasisText,
                     isEditable: !model.isRunning,
                     followsEnd: model.runPhase == .writing,
                     haloStrength: haloStrength,
                     onEscape: escapeHandler)
                .accessibilityLabel("修正版")
                .overlay {
                    if model.runPhase == .connecting, let started = model.runStartedAt {
                        VStack(spacing: 12) {
                            ProgressView().controlSize(.small)
                            Text("AI の返事を待っています").font(.system(size: 13, weight: .medium))
                            TimelineView(.periodic(from: started, by: 1)) { context in
                                Text("\(max(0, Int(context.date.timeIntervalSince(started)))) 秒")
                                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            }
                        }
                        .padding(26).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                        .allowsHitTesting(false)
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.runPhase)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(StudioTheme.accent)
            Text(message).font(.system(size: 12)).textSelection(.enabled)
            Spacer(minLength: 8)
            Button { model.errorMessage = nil } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("エラーを閉じる")
        }
        .padding(14).background(StudioTheme.paper.opacity(0.92), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(StudioTheme.accent.opacity(0.25), lineWidth: 1))
    }
}

private struct EditorPane<Accessory: View, Content: View>: View {
    let number: String
    let eyebrow: String
    let title: String
    let count: Int
    let backgroundOpacity: Double
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(number).font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(StudioTheme.accent).frame(width: 27, height: 27)
                    .background(StudioTheme.accent.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 5) {
                    StudioEyebrow(text: eyebrow)
                    Text(title).font(.system(size: 17, weight: .semibold))
                }
                Spacer(minLength: 6)
                accessory
            }
            .padding(.horizontal, 20).padding(.vertical, 17)
            StudioRule().padding(.horizontal, 20)
            content.padding(.horizontal, 8).padding(.top, 6)
            HStack(spacing: 8) {
                Text("\(count.formatted()) 文字").monospacedDigit()
                Spacer(minLength: 4)
            }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .padding(.horizontal, 22).padding(.vertical, 13)
        }
        .glassCard(cornerRadius: 24, backgroundOpacity: backgroundOpacity)
    }
}

private struct ChangesPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var expanded: Bool
    var maxContentHeight: CGFloat
    @ViewState private var hovered: Int?

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { expanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "text.alignleft").font(.system(size: 13)).foregroundStyle(StudioTheme.accent)
                    Text("修正点").font(.system(size: 13, weight: .semibold))
                    if model.isRunning {
                        Text(model.runPhase == .writing ? "修正点をまとめています…" : "")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if model.hasResult {
                        Text("\(model.changes.count)").font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(StudioTheme.ink.opacity(0.06), in: Capsule())
                    }
                    Spacer(minLength: 8)
                    if !model.concerns.isEmpty {
                        Label("確認 \(model.concerns.count)", systemImage: "questionmark.circle")
                            .font(.system(size: 10)).foregroundStyle(StudioTheme.accent)
                    }
                    if model.hasResult || model.parseNotice != nil {
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary).rotationEffect(.degrees(expanded ? 0 : -90))
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 17).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("修正点")
            .disabled(!model.hasResult && model.parseNotice == nil)
            .accessibilityValue(model.hasResult || model.parseNotice != nil ? (expanded ? "展開" : "折りたたみ") : "")
            if expanded && (model.hasResult || model.parseNotice != nil) {
                StudioRule().padding(.horizontal, 20)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) { reviewContent }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.frame(height: maxContentHeight)
            }
        }.glassCard(cornerRadius: 20)
    }

    @ViewBuilder
    private var reviewContent: some View {
        if let notice = model.parseNotice {
            Label(notice, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(.secondary).padding(8)
        }
        ForEach(Array(model.changes.enumerated()), id: \.offset) { index, change in
            Button { model.highlight(change) } label: {
                HStack(alignment: .top, spacing: 14) {
                    Text(String(format: "%02d", index + 1)).font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(StudioTheme.accent).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(change.before).strikethrough(color: .secondary.opacity(0.45))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                        Text(change.after).font(.system(size: 13, weight: .medium))
                        if !change.reason.isEmpty {
                            Text(change.reason).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary).padding(.top, 3)
                }
                .padding(12)
                .background(StudioTheme.ink.opacity(hovered == index ? 0.07 : 0.025), in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in
                hovered = inside ? index : (hovered == index ? nil : hovered)
                if inside { model.emphasisText = change.after }
                else if model.emphasisText == change.after { model.emphasisText = nil }
            }
            .help("修正版の該当部分を表示")
        }
        if !model.minor.isEmpty {
            Label(model.minor, systemImage: "textformat.abc").font(.system(size: 11)).foregroundStyle(.secondary).padding(8)
        }
        if !model.concerns.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("確認事項", systemImage: "questionmark.circle")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(StudioTheme.accent)
                ForEach(Array(model.concerns.enumerated()), id: \.offset) { _, concern in
                    Text(concern).font(.system(size: 12))
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(StudioTheme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        if model.hasResult, model.parseNotice == nil, model.changes.isEmpty, model.minor.isEmpty, model.concerns.isEmpty {
            Label("修正なし", systemImage: "checkmark.circle")
                .font(.system(size: 12)).foregroundStyle(.secondary).padding(8)
        }
    }
}
