// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TimesShot",
    defaultLocalization: "ja",
    platforms: [.macOS("27.0")],
    products: [.executable(name: "TimesShot", targets: ["TimesShot"])],
    targets: [
        .target(name: "TimesShotCore"),
        .executableTarget(name: "TimesShot", dependencies: ["TimesShotCore"], resources: [.process("Resources")]),
        .testTarget(name: "TimesShotCoreTests", dependencies: ["TimesShotCore"]),
        .testTarget(name: "TimesShotTests", dependencies: ["TimesShot"])
    ]
)
