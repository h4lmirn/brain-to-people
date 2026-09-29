import AppKit
import SwiftUI

// Liquid Glass 風の見た目。
// macOS 26 SDK（Swift 6.2 以降）でビルドしたときは本物の glassEffect を使い、
// それ以前はマテリアル、縁のハイライト、影で近い見た目を作る。

extension View {
    func glass<S: InsettableShape>(in shape: S, tint: Color? = nil) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint))
    }

    func glassCard(cornerRadius: CGFloat = 20) -> some View {
        glass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        let dark = scheme == .dark
        return content
            .background {
                ZStack {
                    shape
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(dark ? 0.35 : 0.10), radius: 18, y: 8)
                    // 上から光が当たったような明るさの勾配
                    shape.fill(LinearGradient(
                        colors: [.white.opacity(dark ? 0.10 : 0.45), .white.opacity(dark ? 0.02 : 0.10)],
                        startPoint: .top, endPoint: .bottom))
                    if let tint {
                        shape.fill(tint.opacity(dark ? 0.22 : 0.16))
                    }
                }
            }
            .overlay {
                // 縁のハイライト（左上が強く光る）
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(dark ? 0.35 : 0.85),
                            .white.opacity(dark ? 0.06 : 0.20),
                            .white.opacity(dark ? 0.18 : 0.50),
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            }
    }
}

// MARK: - ボタン

struct GlassButtonStyle: ButtonStyle {
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: prominent ? .semibold : .medium))
            .padding(.horizontal, prominent ? 16 : 12)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .background {
                if prominent {
                    Capsule()
                        .fill(LinearGradient(
                            colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.75)],
                            startPoint: .top, endPoint: .bottom))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.45), lineWidth: 1))
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 10, y: 4)
                }
            }
            .modifier(OptionalGlass(enabled: !prominent))
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct OptionalGlass: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.glass(in: Capsule()) } else { content }
    }
}

// MARK: - 背景

/// ウィンドウの後ろをぼかし、その上に淡い色のにじみを置く。ガラスが透けて見えるための下地。
struct Backdrop: View {
    var image: NSImage? = nil
    var opacity: Double = 0.35
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if let image {
                Color(nsColor: .windowBackgroundColor)
                GeometryReader { geometry in
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                        .clipped()
                        .opacity(opacity)
                        .mask {
                            LinearGradient(stops: [
                                .init(color: .white, location: 0),
                                .init(color: .white.opacity(0.9), location: 0.3),
                                .init(color: .white.opacity(0.35), location: 0.65),
                                .init(color: .clear, location: 1),
                            ], startPoint: .top, endPoint: .bottom)
                        }
                }
            } else {
                VisualEffectBackground()
                GeometryReader { geometry in
                    let w = geometry.size.width, h = geometry.size.height
                    let strength = scheme == .dark ? 0.30 : 0.22
                    ZStack {
                        blob(.blue, strength, size: w * 0.65).offset(x: -w * 0.30, y: -h * 0.30)
                        blob(.purple, strength * 0.8, size: w * 0.55).offset(x: w * 0.35, y: -h * 0.10)
                        blob(.teal, strength * 0.7, size: w * 0.60).offset(x: w * 0.05, y: h * 0.40)
                    }
                    .frame(width: w, height: h)
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }

    private func blob(_ color: Color, _ opacity: Double, size: CGFloat) -> some View {
        Circle()
            .fill(color.opacity(opacity))
            .frame(width: size, height: size)
            .blur(radius: 110)
    }
}

private struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// タイトルバーを透明にし、背景をつかんでウィンドウを動かせるようにする。
struct WindowConfigurator: NSViewRepresentable {
    var alwaysOnTop = false

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let alwaysOnTop = alwaysOnTop
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = alwaysOnTop ? .floating : .normal
            window.titlebarAppearsTransparent = true
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.level = alwaysOnTop ? .floating : .normal
    }
}
