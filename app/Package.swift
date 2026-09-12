// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "WebPort",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "WebPort", targets: ["WebPort"])
    ],
    targets: [
        .executableTarget(
            name: "WebPort",
            path: "Sources/WebPort",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
