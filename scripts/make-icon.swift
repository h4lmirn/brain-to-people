// アプリアイコンを Icon Composer 形式（Resources/AppIcon.icon）で書き出す。
// 使い方: swift scripts/make-icon.swift [確認用PNG]
//
// 図柄: アプリと同じ青の地に、透けた液体が1つ。左下の吹き出しに B、右上のしずくに P を置き、
// 左から「B → P」と読める並びにする。
// 液体の層は glass を有効にし、Liquid Glass の反射や屈折はシステムに任せる。
import AppKit
import SwiftUI

let size: CGFloat = 1024
/// アプリのボタン（accentColor）に合わせた青
let blueTop = (r: 0.29, g: 0.60, b: 1.00)
let blueBottom = (r: 0.04, g: 0.40, b: 0.92)
let letterBlue = Color(red: 0.05, green: 0.36, blue: 0.85)

/// しずくと吹き出しをなめらかにつなげた液体の形（白）
struct Liquid: View {
    var body: some View {
        Canvas { ctx, _ in
            ctx.addFilter(.alphaThreshold(min: 0.5, color: .white))
            ctx.addFilter(.blur(radius: 42))
            ctx.drawLayer { l in
                l.fill(Path(ellipseIn: CGRect(x: 170, y: 160, width: 300, height: 300)), with: .color(.white))
                l.fill(Path(ellipseIn: CGRect(x: 395, y: 395, width: 470, height: 450)), with: .color(.white))
                l.fill(Path(ellipseIn: CGRect(x: 360, y: 350, width: 140, height: 140)), with: .color(.white))
                var tail = Path()
                tail.move(to: CGPoint(x: 660, y: 740))
                tail.addLine(to: CGPoint(x: 905, y: 945))
                tail.addLine(to: CGPoint(x: 820, y: 690))
                l.fill(tail, with: .color(.white))
            }
        }
        .frame(width: size, height: size)
        // 右上のしずく（B）から、左下の吹き出し（P）へ流れる向きにする
        .scaleEffect(x: -1, y: 1)
    }
}

struct Letters: View {
    var body: some View {
        ZStack {
            Text("P").font(.system(size: 190, weight: .heavy, design: .serif))
                .position(x: 704, y: 305)
            Text("B").font(.system(size: 300, weight: .heavy, design: .serif))
                .position(x: 392, y: 612)
        }
        .foregroundStyle(letterBlue)
        .frame(width: size, height: size)
    }
}

/// 確認用。システムのガラスは再現せず、配置と色だけを見る。
struct Preview: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: blueTop.r, green: blueTop.g, blue: blueTop.b),
                                    Color(red: blueBottom.r, green: blueBottom.g, blue: blueBottom.b)],
                           startPoint: .top, endPoint: .bottom)
            Liquid().opacity(0.9).shadow(color: .black.opacity(0.25), radius: 24, y: 18)
            Letters()
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 230, style: .continuous))
    }
}

@MainActor
func png<V: View>(_ view: V) -> Data {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let cg = renderer.cgImage else { fatalError("描画に失敗しました") }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
}

func srgb(_ c: (r: Double, g: Double, b: Double)) -> String {
    String(format: "srgb:%.5f,%.5f,%.5f,1.00000", c.r, c.g, c.b)
}

let iconJSON = """
{
  "fill" : {
    "linear-gradient" : [
      "\(srgb(blueTop))",
      "\(srgb(blueBottom))"
    ]
  },
  "groups" : [
    {
      "name" : "Letters",
      "layers" : [
        { "image-name" : "letters.png", "name" : "letters", "glass" : false }
      ],
      "shadow" : { "kind" : "none", "opacity" : 0 }
    },
    {
      "name" : "Liquid",
      "layers" : [
        { "image-name" : "liquid.png", "name" : "liquid", "glass" : true, "opacity" : 0.75 }
      ],
      "shadow" : { "kind" : "neutral", "opacity" : 0.5 },
      "translucency" : { "enabled" : true, "value" : 0.7 },
      "specular" : true
    }
  ],
  "supported-platforms" : {
    "squares" : [ "macOS" ]
  }
}
"""

MainActor.assumeIsolated {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    let icon = root.appendingPathComponent("Resources/AppIcon.icon")
    let assets = icon.appendingPathComponent("Assets")
    try? FileManager.default.removeItem(at: icon)
    try! FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
    try! png(Liquid()).write(to: assets.appendingPathComponent("liquid.png"))
    try! png(Letters()).write(to: assets.appendingPathComponent("letters.png"))
    try! iconJSON.write(to: icon.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
    print("wrote \(icon.path)")
    if CommandLine.arguments.count > 1 {
        try! png(Preview()).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("wrote \(CommandLine.arguments[1])")
    }
}
