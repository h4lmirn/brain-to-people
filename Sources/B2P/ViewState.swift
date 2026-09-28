import SwiftUI

/// SwiftUI の State をプロパティラッパーとして直接使うための別名。
/// macOS 27 SDK では `@State` がマクロになり、その実装は Xcode 本体にしか入っていない。
/// Command Line Tools だけでもビルドできるよう、マクロを通さずに同じ State 型を使う。
typealias ViewState = SwiftUI.State
