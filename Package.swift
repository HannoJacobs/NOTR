// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NOTR",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "NOTR",
            path: "Sources/NOTR",
            exclude: ["Info.plist"]
        )
    ]
)
