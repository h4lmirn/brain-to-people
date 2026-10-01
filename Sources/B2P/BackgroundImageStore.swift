import AppKit
import ImageIO
import UniformTypeIdentifiers

/// 選んだ画像を縮小してアプリ内に保存する。元ファイルへのアクセスは選択時だけ。
struct BackgroundImageStore {
    let fileURL: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("B2P", isDirectory: true)
        fileURL = base.appendingPathComponent("background.png")
    }

    func load() -> NSImage? { NSImage(contentsOf: fileURL) }

    func save(from url: URL) throws -> NSImage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let image = Self.thumbnail(at: url),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        return NSImage(cgImage: image, size: .zero)
    }

    /// 画面に出す大きさまで縮小して読み込む。フォルダ背景でも同じ処理を使う。
    static func thumbnail(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2560,
        ] as CFDictionary)
    }

    func remove() throws {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
    }
}

/// 登録したフォルダの直下にある画像を数える。サブフォルダは見ない。
enum BackgroundFolder {
    static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff"]

    static func images(in folder: URL) -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files
            .filter { extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    /// 今の画像の次を返す。順番どおり、またはランダム（今の画像は避ける）。
    static func next(after current: URL?, in images: [URL], shuffle: Bool) -> URL? {
        guard !images.isEmpty else { return nil }
        if shuffle {
            let others = images.filter { $0 != current }
            return (others.isEmpty ? images : others).randomElement()
        }
        guard let current, let index = images.firstIndex(of: current) else { return images[0] }
        return images[(index + 1) % images.count]
    }
}
