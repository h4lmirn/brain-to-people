import AppKit
import SwiftUI

@main
struct B2PApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Brain-to-People", id: "main") {
            MainView()
                .environmentObject(model)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1180, height: 820)
        .commands { B2PCommands(model: model) }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct B2PCommands: Commands {
    @ObservedObject var model: AppModel

    var body: some Commands {
        CommandMenu("文章") {
            Button("実行") { model.run() }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.isRunning)
            Button("中止") { model.cancel() }
                .keyboardShortcut(.escape, modifiers: [])
                .disabled(!model.isRunning)
            Divider()
            Button("修正版をコピー") { model.copyRevised() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(model.revised.isEmpty)
        }
        CommandGroup(after: .windowArrangement) {
            Toggle("常に最前面に表示", isOn: $model.alwaysOnTop)
                .keyboardShortcut("t", modifiers: [.command, .option])
        }
        CommandMenu("プロファイル") {
            ForEach(Array(model.profiles.prefix(9).enumerated()), id: \.element.id) { index, profile in
                Toggle(profile.name, isOn: Binding(
                    get: { model.selectedProfile?.id == profile.id },
                    set: { _ in model.selectedProfileID = profile.id }
                ))
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
    }
}
