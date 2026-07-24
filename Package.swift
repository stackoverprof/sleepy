// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Sleepy",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "SleepyCore", targets: ["SleepyCore"]),
        .executable(name: "Sleepy", targets: ["Sleepy"]),
        .executable(name: "SleepyHelper", targets: ["SleepyHelper"])
    ],
    targets: [
        .target(name: "SleepyCore"),
        .executableTarget(
            name: "Sleepy",
            dependencies: ["SleepyCore"]
        ),
        .executableTarget(
            name: "SleepyHelper",
            dependencies: ["SleepyCore"]
        ),
        .testTarget(
            name: "SleepyCoreTests",
            dependencies: ["SleepyCore"]
        )
    ]
)
