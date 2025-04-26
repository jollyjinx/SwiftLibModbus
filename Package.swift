// swift-tools-version: 6.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(name: "SwiftLibModbus",
                      platforms: [
                          .iOS(.v18),
                          .macOS(.v15),
                      ],
                      products: [
                          .library(name: "CModbus",
                                   targets: ["CModbus"]),
                          .library(name: "SwiftLibModbus",
                                   targets: ["SwiftLibModbus"]),
                      ],
                      dependencies: [],
                      targets: [
                          .target(name: "CModbus",
                                  swiftSettings: [
                                      .enableExperimentalFeature("StrictConcurrency"),
                                  ]),
                          .target(name: "SwiftLibModbus",
                                  dependencies: ["CModbus"],
                                  swiftSettings: [
                                      .enableExperimentalFeature("StrictConcurrency"),
                                  ]),
                          .testTarget(name: "SwiftLibModbusTests",
                                      dependencies: ["SwiftLibModbus"]),
                      ])
