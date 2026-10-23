// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rayclone",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "Rayclone",
            path: "Sources/Rayclone",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]),
        .testTarget(
            name: "RaycloneTests",
            dependencies: ["Rayclone"],
            path: "Tests/RaycloneTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ])
    ]
)
