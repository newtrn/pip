// swift-tools-version:6.0
// Open this folder in Xcode to work on Pip. `scripts/build-app.sh` produces the
// .app bundle (Info.plist, LSUIElement, ad-hoc signature) that notifications
// and launch-at-login need.
import PackageDescription

let package = Package(
    name: "Pip",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Pip", targets: ["Pip"]),
    ],
    targets: [
        .target(name: "PipCore"),
        .executableTarget(name: "Pip", dependencies: ["PipCore"]),
        .testTarget(name: "PipCoreTests", dependencies: ["PipCore"]),
    ]
)
