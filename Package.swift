// swift-tools-version: 5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftLibModbus",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
    ],
    products: [
        .library(
            name: "CModbus",
            targets: ["CModbus"]),
        .library(
            name: "SwiftLibModbus",
            targets: ["SwiftLibModbus"]),
    ],
    dependencies: [  ],
    targets: [
        .target(name: "CModbus"),
        .target(
            name: "SwiftLibModbus",
            dependencies: ["CModbus"]
            ),
        .testTarget(
            name: "SwiftLibModbusTests",
            dependencies: ["SwiftLibModbus"]
            )
    ]
)
