// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Headroom",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "3.0.1"),
    ],
    targets: [
        .target(
            name: "HeadroomCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "Headroom",
            dependencies: [
                "HeadroomCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "HeadroomCoreTests",
            dependencies: ["HeadroomCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
