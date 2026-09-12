// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "StaticPageHub",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StaticPageHub", targets: ["StaticPageHub"])
    ],
    targets: [
        .executableTarget(
            name: "StaticPageHub",
            path: "Sources/StaticPageHub",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

