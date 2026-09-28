// swift-tools-version:5.10
import Foundation
import PackageDescription

// Command Line Tools だけの環境では、Swift Testing のマクロ（@Test、@Suite）の実装を
// ビルドがときどき見つけられない。見つかる場所を明示して渡す（Xcode では不要なので、あるときだけ）。
let testingPlugins = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing"
let testSettings: [SwiftSetting] = FileManager.default.fileExists(atPath: testingPlugins)
    ? [.unsafeFlags(["-plugin-path", testingPlugins])]
    : []

let package = Package(
    name: "B2P",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "B2P", targets: ["B2P"]),
    ],
    targets: [
        .target(name: "B2PCore"),
        .executableTarget(name: "B2P", dependencies: ["B2PCore"]),
        .testTarget(name: "B2PCoreTests", dependencies: ["B2PCore"], swiftSettings: testSettings),
    ]
)
