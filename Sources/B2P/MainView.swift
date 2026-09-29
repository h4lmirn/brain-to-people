import B2PCore
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var changesExpanded = true

    var body: some View {
        ZStack {
            Backdrop(image: model.backgroundImage, opacity: model.backgroundOpacity)
            VStack(spacing: 14) {
                if let message = model.errorMessage {
                    errorBanner(message)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                GeometryReader { geometry in
                    let layout = geometry.size.width >= 760
                        ? AnyLayout(HStackLayout(spacing: 14))
                        : AnyLayout(VStackLayout(spacing: 14))
                    layout {
                        inputPane
                        revisedPane
                    }
                }
                ChangesPanel(expanded: $changesExpanded)
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 18)
        }
        .background(WindowConfigurator(alwaysOnTop: model.alwaysOnTop))
        .onChange(of: model.resultCount) {
            if model.autoExpandChanges {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { changesExpanded = true }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) { pinButton }
            ToolbarItem(placement: .automatic) { profileCapsule }
            ToolbarItem(placement: .automatic) { runButton }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        #if DEBUG
        .onAppear { DebugSnapshot.runIfRequested(model: model) }
        #endif
        .frame(minWidth: 600, minHeight: 560)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.errorMessage)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.isRunning)
        .animation(.easeOut(duration: 0.2), value: model.justCopied)
    }

    // MARK: 上のバー

    private var pinButton: some View {
        Button {
            model.alwaysOnTop.toggle()
        } label: {
            Image(systemName: model.alwaysOnTop ? "pin.fill" : "pin")
                .foregroundStyle(model.alwaysOnTop ? Color.accentColor : Color.primary)
                .rotationEffect(.degrees(model.alwaysOnTop ? 0 : 45))
                .frame(width: 16)
        }
        .buttonStyle(GlassButtonStyle())
        .help(model.alwaysOnTop ? "常に最前面：オン（⌥⌘T）" : "常に最前面に表示（⌥⌘T）")
    }

    private var profileCapsule: some View {
        HStack(spacing: 0) {
            Menu {
                Picker("プロファイル", selection: $model.selectedProfileID) {
                    ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                        Text(index < 9 ? "\(profile.name)　⌘\(index + 1)" : profile.name)
                            .tag(Optional(profile.id))
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.badge.checkmark")
                    Text(model.selectedProfile?.name ?? "プロファイル")
                    if model.selectedProfile?.fastMode == true {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                            .help("速さ優先")
                    }
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                .font(.system(size: 13, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .help("プロファイル（⌘1〜⌘9）")

            if let profile = model.selectedProfile {
                Divider().frame(height: 16)
                locationBadge(profile)
                    .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 7)
        .glass(in: Capsule())
    }

    private func locationBadge(_ profile: ProfileConfig) -> some View {
        let local = profile.isLocal
        let color: Color = local ? .green : .blue
        return HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.8), radius: 3)
            Text(local ? "ローカル" : "クラウド")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .fixedSize()
        .help(local ? "文章はこの Mac の外に送られません" : "文章は \(profile.provider.shortName) のサーバーに送られます")
    }

    @ViewBuilder
    private var runButton: some View {
        if model.isRunning {
            Button { model.cancel() } label: {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("中止")
                    Text("esc").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(GlassButtonStyle())
            .help("中止（Esc）")
        } else {
            Button { model.run() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.stars")
                    Text("整える")
                    Text("⌘↩").font(.system(size: 11, weight: .medium)).opacity(0.75)
                }
            }
            .buttonStyle(GlassButtonStyle(prominent: true))
            .disabled(model.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("実行（⌘Enter）")
        }
    }

    // MARK: 入力と修正版

    private var escapeHandler: () -> Bool {
        let model = model
        return {
            guard model.isRunning else { return false }
            model.cancel()
            return true
        }
    }

    private var inputPane: some View {
        GlassPane(title: "入力", systemImage: "brain.head.profile") {
            EmptyView()
        } content: {
            TextArea(text: $model.input, onEscape: escapeHandler)
                .overlay(alignment: .topLeading) {
                    if model.input.isEmpty {
                        placeholder("頭に浮かんだまま書いてください")
                    }
                }
        }
    }

    private var revisedPane: some View {
        GlassPane(title: "修正版", systemImage: "person.2") {
            Button {
                model.copyRevised()
            } label: {
                Label(model.justCopied ? "コピーしました" : "コピー", systemImage: model.justCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12, weight: .medium))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(GlassButtonStyle())
            .controlSize(.small)
            .disabled(model.revised.isEmpty)
            .help("修正版をコピー（⌃C / ⌘⇧C）")
        } content: {
            TextArea(text: $model.revised, highlight: model.highlightRequest, onEscape: escapeHandler)
                .overlay(alignment: .topLeading) {
                    if model.revised.isEmpty, !model.isRunning {
                        placeholder("⌘Enter で、読み手に届く文章がここに出ます")
                    }
                }
                .overlay {
                    if model.isRunning {
                        HStack(spacing: 10) {
                            ProgressView().controlSize(.small)
                            Text("整えています…").font(.system(size: 13, weight: .medium))
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .glass(in: Capsule())
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .allowsHitTesting(false)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13))
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button {
                model.errorMessage = nil
            } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("閉じる")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(in: Capsule(), tint: .orange)
    }
}

private struct GlassPane<Accessory: View, Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                accessory
            }
            .frame(height: 30)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            content
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .glassCard(cornerRadius: 22)
    }
}

// MARK: - 修正点

private struct ChangesPanel: View {
    @EnvironmentObject private var model: AppModel
    @Binding var expanded: Bool
    @ViewState private var hovered: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                    Text("修正点")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    if !model.changes.isEmpty {
                        Text("\(model.changes.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                    }
                    if !model.concerns.isEmpty {
                        Label("懸念 \(model.concerns.count)", systemImage: "questionmark.bubble")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)

            if expanded {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                }
                .frame(minHeight: 70, maxHeight: 230)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .glassCard(cornerRadius: 22)
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasResult {
            Text("実行すると、ここに修正点と読み手目線の懸念が出ます。行をクリックすると修正版の該当部分を示します。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        if let notice = model.parseNotice {
            Label(notice, systemImage: "exclamationmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        ForEach(Array(model.changes.enumerated()), id: \.offset) { index, change in
            Button { model.highlight(change) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(change.before)
                            .foregroundStyle(.secondary)
                            .strikethrough(color: .secondary.opacity(0.6))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                        Text(change.after)
                    }
                    .font(.system(size: 13))
                    .lineLimit(4)
                    if !change.reason.isEmpty {
                        Text(change.reason)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if hovered == index {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(.white.opacity(0.25), lineWidth: 1))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { inside in
                withAnimation(.easeOut(duration: 0.12)) {
                    hovered = inside ? index : (hovered == index ? nil : hovered)
                }
            }
            .help("修正版の該当部分を表示")
        }
        if !model.minor.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("表記")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.secondary.opacity(0.15)))
                    .foregroundStyle(.secondary)
                Text(model.minor).font(.system(size: 12))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        if !model.concerns.isEmpty {
            Text("読み手目線の懸念")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)
            ForEach(Array(model.concerns.enumerated()), id: \.offset) { _, concern in
                Label {
                    Text(concern).font(.system(size: 12))
                } icon: {
                    Image(systemName: "questionmark.bubble").foregroundStyle(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
            }
        }
        if model.hasResult, model.parseNotice == nil, model.changes.isEmpty, model.minor.isEmpty, model.concerns.isEmpty {
            Label("直すところは見つかりませんでした。", systemImage: "checkmark.seal")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
    }
}
