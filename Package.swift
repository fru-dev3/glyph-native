// swift-tools-version: 6.2
// Glyph Native: the family's launcher. On the Mac, one window to see every Glyph Native app and
// install or update each from its signed release; the iPhone launcher is in project.yml.
// NativeKit (the family list) is shared by both. Build the Mac app: scripts/build.sh.
import PackageDescription

let package = Package(
    name: "GlyphNative",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [.library(name: "NativeKit", targets: ["NativeKit"])],
    dependencies: [.package(path: "Packages/GlyphCore")],   // GlyphCapture: the family's one dictate button
    targets: [
        .target(name: "NativeKit", dependencies: [.product(name: "GlyphCapture", package: "GlyphCore"), .product(name: "GlyphVault", package: "GlyphCore"), .product(name: "GlyphAI", package: "GlyphCore")], path: "Shared"),
        .executableTarget(name: "GlyphNative", dependencies: ["NativeKit"], path: "Sources/GlyphNative"),
    ],
    swiftLanguageModes: [.v5]
)
