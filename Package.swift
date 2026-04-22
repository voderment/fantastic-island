// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "IslandLogic",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "IslandLogic", targets: ["IslandLogic"]),
    ],
    targets: [
        .target(
            name: "IslandLogic",
            path: "FantasticIsland/FantasticIsland",
            sources: [
                "Modules/Clash/Models/ClashControlState.swift",
                "Modules/Codex/Monitoring/CodexAppServer.swift",
                "Modules/Clash/Models/ClashConfigSupport.swift",
                "Modules/Clash/Models/ClashRuntimeModels.swift",
                "Modules/Clash/Models/ClashModuleSettings.swift",
            ]
        ),
        .testTarget(
            name: "IslandLogicTests",
            dependencies: ["IslandLogic"],
            path: "Tests/IslandLogicTests"
        ),
    ]
)
