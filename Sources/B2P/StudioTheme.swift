import AppKit
import SwiftUI

enum StudioTheme {
    static let ink = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.94, green: 0.93, blue: 0.91, alpha: 1)
            : NSColor(red: 0.15, green: 0.17, blue: 0.20, alpha: 1)
    })
    static let paper = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.10, green: 0.11, blue: 0.14, alpha: 1)
            : NSColor(red: 0.97, green: 0.965, blue: 0.95, alpha: 1)
    })
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 1, green: 0.69, blue: 0.53, alpha: 1)
            : NSColor(red: 0.66, green: 0.26, blue: 0.16, alpha: 1)
    })
    static let line = Color.primary.opacity(0.09)
}

struct StudioButtonStyle: ButtonStyle {
    var prominent = false
    var compact = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, compact ? 10 : 16)
            .frame(height: compact ? 32 : 42)
            .foregroundStyle(prominent ? StudioTheme.paper : StudioTheme.ink)
            .background {
                RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous)
                    .fill(prominent ? StudioTheme.ink : StudioTheme.ink.opacity(hovered ? 0.09 : 0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: compact ? 10 : 13, style: .continuous)
                            .strokeBorder(StudioTheme.ink.opacity(prominent ? 0 : 0.08), lineWidth: 0.5)
                    }
            }
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.42)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovered)
            .onHover { hovered = $0 }
    }
}

struct StudioEyebrow: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1.7).foregroundStyle(.secondary)
    }
}

struct StudioRule: View {
    var body: some View { Rectangle().fill(StudioTheme.line).frame(height: 0.5) }
}
