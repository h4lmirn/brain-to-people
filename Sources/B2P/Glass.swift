import AppKit
import SwiftUI

// Liquid Glass 風の見た目。
// macOS 26 SDK（Swift 6.2 以降）でビルドしたときは本物の glassEffect を使い、
// それ以前はマテリアル、縁のハイライト、影で近い見た目を作る。

extension View {
    func glass<S: InsettableShape>(in shape: S, tint: Color? = nil, backgroundOpacity: Double = 1) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, backgroundOpacity: backgroundOpacity))
    }

    func glassCard(cornerRadius: CGFloat = 20, backgroundOpacity: Double = 1) -> some View {
        modifier(FrostedPanel(cornerRadius: cornerRadius, backgroundOpacity: backgroundOpacity))
    }
}

/// 大きな文章パネル用。ぼかすのは背後だけで、文字はマテリアルの外に置く。
private struct FrostedPanel: ViewModifier {
    var cornerRadius: CGFloat
    var backgroundOpacity: Double
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.frostedBackdropFrame) private var backdropFrame
    @EnvironmentObject private var model: AppModel

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = scheme == .dark
        let opacity = reduceTransparency ? 1 : min(1, max(0, backgroundOpacity))
        content
            .background {
                ZStack {
                    if reduceTransparency {
                        shape.fill(Color(nsColor: .windowBackgroundColor))
                    } else {
                        if let image = model.backgroundImage, !backdropFrame.isEmpty {
                            GeometryReader { geometry in
                                let panelFrame = geometry.frame(in: .named("mainBackdrop"))
                                // 背景と同じ大きさ・位置で描き、パネルの範囲だけを切り出す。
                                // 画像を欄ごとに引き伸ばすと、境目で背景がずれてしまう。
                                BackgroundArtwork(image: image, opacity: model.backgroundOpacity)
                                    .frame(width: backdropFrame.width, height: backdropFrame.height)
                                    .blur(radius: 12)
                                    .offset(x: backdropFrame.minX - panelFrame.minX,
                                            y: backdropFrame.minY - panelFrame.minY)
                            }
                            .id(ObjectIdentifier(image))
                            .transition(.opacity)
                            .clipShape(shape)
                            .opacity(opacity)
                        } else {
                            FrostedBackdrop(opacity: opacity)
                                .clipShape(shape)
                        }
                        shape.fill(LinearGradient(
                            colors: [.white.opacity(dark ? 0.09 : 0.18),
                                     .white.opacity(dark ? 0.025 : 0.035)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                            .opacity(opacity)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .background {
                // 面全体を影の形に使い、本文には影を付けない。
                shape.fill(.black.opacity(0.035 * opacity))
                    .shadow(color: .black.opacity((dark ? 0.28 : 0.10) * opacity), radius: 16, y: 7)
                    .shadow(color: .black.opacity(0.08 * opacity), radius: 2, y: 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .overlay {
                ZStack {
                    shape.strokeBorder(LinearGradient(
                        stops: [
                            .init(color: .white.opacity(dark ? 0.55 : 0.90), location: 0),
                            .init(color: .white.opacity(dark ? 0.14 : 0.28), location: 0.42),
                            .init(color: .black.opacity(dark ? 0.22 : 0.10), location: 0.72),
                            .init(color: .white.opacity(dark ? 0.25 : 0.50), location: 1),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    shape.inset(by: 1).strokeBorder(.white.opacity((dark ? 0.06 : 0.18) * opacity), lineWidth: 0.5)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}

private struct FrostedBackdrop: NSViewRepresentable {
    var opacity: Double

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        // ウィンドウの外ではなく、アプリ内の背景画像をぼかす。
        view.blendingMode = .withinWindow
        view.state = .active
        view.alphaValue = opacity
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.alphaValue = opacity
    }
}

struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color?
    var backgroundOpacity: Double = 1
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content.background {
                // 背景だけを透かし、文字や操作部品の濃さは変えない。
                Color.clear
                    .glassEffect(tint.map { Glass.regular.tint($0.opacity(0.35)) } ?? .regular, in: shape)
                    .opacity(backgroundOpacity)
                    .allowsHitTesting(false)
            }
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
                .opacity(backgroundOpacity)
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

struct BackdropFramePreference: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

private struct FrostedBackdropFrameKey: EnvironmentKey {
    static let defaultValue = CGRect.zero
}

extension EnvironmentValues {
    var frostedBackdropFrame: CGRect {
        get { self[FrostedBackdropFrameKey.self] }
        set { self[FrostedBackdropFrameKey.self] = newValue }
    }
}

/// 通常の背景と、ガラス越しの背景に同じ画像配置・グラデーションを使う。
private struct BackgroundArtwork: View {
    let image: NSImage
    let opacity: Double
    var tracksFrame = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    .clipped()
                    .colorMultiply(scheme == .dark ? Color(white: 0.5) : .white)
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
            .preference(key: BackdropFramePreference.self,
                        value: tracksFrame ? geometry.frame(in: .named("mainBackdrop")) : .zero)
        }
    }
}

/// ウィンドウの後ろをぼかし、その上に淡い色のにじみを置く。ガラスが透けて見えるための下地。
struct Backdrop: View {
    var image: NSImage? = nil
    var opacity: Double = 0.35
    var tracksFrame = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            if let image {
                BackgroundArtwork(image: image, opacity: opacity, tracksFrame: tracksFrame)
                    .id(ObjectIdentifier(image))
                    .transition(.opacity)
            } else {
                VisualEffectBackground()
                StudioTheme.paper.opacity(0.90)
                GeometryReader { geometry in
                    let w = geometry.size.width, h = geometry.size.height
                    let strength = scheme == .dark ? 0.17 : 0.12
                    ZStack {
                        blob(.orange, strength, size: w * 0.70).offset(x: -w * 0.35, y: -h * 0.30)
                        blob(.indigo, strength * 0.65, size: w * 0.60).offset(x: w * 0.40, y: -h * 0.15)
                        blob(.pink, strength * 0.35, size: w * 0.55).offset(x: w * 0.05, y: h * 0.45)
                    }
                    .frame(width: w, height: h)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
