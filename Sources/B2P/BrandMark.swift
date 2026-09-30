import SwiftUI

/// アプリ内と Dock で共通のマーク。外観モードによらず黒地を保つ。
struct BrandMark: View {
    static let backgroundColor = Color(red: 0.15, green: 0.17, blue: 0.20)
    var size: CGFloat = 44

    var body: some View {
        Text("b→p")
            .font(.system(size: size * 16 / 44, weight: .medium, design: .monospaced))
            .tracking(-size / 44)
            .foregroundStyle(Color(red: 0.97, green: 0.965, blue: 0.95))
            .frame(width: size, height: size)
            .background(Self.backgroundColor,
                        in: RoundedRectangle(cornerRadius: size * 14 / 44, style: .continuous))
            .accessibilityHidden(true)
    }
}
