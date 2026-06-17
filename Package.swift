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
            exclude: [
                "App",
                "Assets.xcassets",
                "Modules/Codex/Models/CodexModuleModel.swift",
                "Modules/Codex/Monitoring/CodexAppServerCoordinator.swift",
                "Modules/Codex/Monitoring/CodexCLIReplySender.swift",
                "Modules/Codex/Monitoring/CodexMonitoringEngine.swift",
                "Modules/Codex/Monitoring/CodexRolloutTailer.swift",
                "Modules/Codex/Monitoring/CodexSessionReducer.swift",
                "Modules/Codex/Monitoring/CodexTerminalJumpService.swift",
                "Modules/Codex/Monitoring/CodexTerminalTextSender.swift",
                "Modules/Codex/Monitoring/CodexTokenUsageHistoryScanner.swift",
                "Modules/Codex/Views",
                "Modules/Diagnostics",
                "Modules/Horizon/Models/HorizonModuleModel.swift",
                "Modules/Horizon/Services",
                "Modules/Placeholder",
                "Modules/Player",
                "Modules/System",
                "Modules/XPost/Models/XPostModuleModel.swift",
                "Modules/XPost/Models/XPostModuleSettings.swift",
                "Modules/XPost/Networking",
                "Modules/XPost/Views",
                "Shared/Audio",
                "Shared/CapsuleMenuPicker.swift",
                "Shared/HUD",
                "Shared/IslandModuleScrollAction.swift",
                "Shared/IslandSwitch.swift",
                "Shared/IslandVisualLanguage.swift",
                "Shared/Keyboard",
                "Shared/Models",
                "Shared/System",
                "Shell",
                "UI",
                "source",
            ],
            sources: [
                "Modules/Codex/Models/AgentProvider.swift",
                "Modules/Codex/Models/AgentProviderUsageCacheLoader.swift",
                "Modules/Codex/Models/AgentSessionLauncher.swift",
                "Modules/Codex/Models/CodexSessionSummary.swift",
                "Modules/Codex/Hooks/CodexHookManager.swift",
                "Modules/Codex/Hooks/CodexHookModels.swift",
                "Modules/Codex/Hooks/HookBridgeServer.swift",
                "Modules/Codex/Monitoring/CodexAppServer.swift",
                "Modules/Codex/Monitoring/CodexMonitoringParsing.swift",
                "Modules/Codex/Monitoring/CodexSessionModels.swift",
                "Modules/Codex/Monitoring/AgentActivityModel.swift",
                "Modules/Codex/Monitoring/AgentSessionStore.swift",
                "Modules/Codex/Monitoring/AgentTranscriptParser.swift",
                "Modules/Codex/Monitoring/CodexTerminalDiscovery.swift",
                "Modules/Codex/Monitoring/CodexSessionDiscovery.swift",
                "Modules/Horizon/Models/HorizonTimerState.swift",
                "Modules/XPost/Models/XPostTextValidation.swift",
                "Shared/Navigation/IslandHorizontalModuleSwipeGate.swift",
                "Shared/Security/KeychainSecretStore.swift",
            ]
        ),
        .testTarget(
            name: "IslandLogicTests",
            dependencies: ["IslandLogic"],
            path: "Tests/IslandLogicTests"
        ),
    ]
)
