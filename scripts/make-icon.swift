// 共通の BrandMark から、アプリアイコンと README 用 PNG を書き出す。
// 使い方は scripts/make-icon.sh を参照。
import AppKit
import SwiftUI

@main
struct MakeIcon {
    @MainActor
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let iconset = root.appendingPathComponent("build/BrandIcon.iconset")
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                let suffix = scale == 2 ? "@2x" : ""
                try render(size: pixels).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
            }
        }
        try render(size: 1024).write(to: root.appendingPathComponent("docs/icon.png"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        print("wrote Resources/AppIcon.icns and docs/icon.png")
    }

    @MainActor
    static func render(size: Int) -> Data {
        let side = CGFloat(size)
        let renderer = ImageRenderer(content:
            BrandMark(size: side * 0.82).frame(width: side, height: side)
        )
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { fatalError("アイコンを描画できませんでした") }
        return data
    }
}
