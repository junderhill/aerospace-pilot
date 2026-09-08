// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AeroSpacePilot",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AeroSpacePilot", targets: ["PilotApp"]),
        .executable(name: "pilot", targets: ["PilotDiagnostics"]),
        .executable(name: "PilotWindowFixture", targets: ["PilotWindowFixture"]),
        .executable(name: "pilot-desktop-tests", targets: ["PilotDesktopTests"]),
    ],
    targets: [
        .target(name: "PilotCore"),
        .target(name: "PilotIntegration", dependencies: ["PilotCore"], resources: [.process("Resources")]),
        .target(name: "PilotProfiles", dependencies: ["PilotCore"], resources: [.process("Resources")]),
        .target(name: "PilotOverview", dependencies: ["PilotCore"]),
        .target(name: "PilotTestSupport", dependencies: ["PilotCore", "PilotIntegration", "PilotProfiles"]),
        .executableTarget(name: "PilotApp", dependencies: ["PilotCore", "PilotIntegration", "PilotProfiles", "PilotOverview"]),
        .executableTarget(name: "PilotDiagnostics", dependencies: ["PilotCore", "PilotIntegration", "PilotProfiles", "PilotOverview"]),
        .executableTarget(name: "PilotWindowFixture"),
        .executableTarget(name: "PilotDesktopTests", dependencies: ["PilotCore", "PilotIntegration", "PilotProfiles", "PilotOverview"]),
        .testTarget(name: "PilotCoreTests", dependencies: ["PilotCore"]),
        .testTarget(name: "PilotIntegrationTests", dependencies: ["PilotIntegration", "PilotTestSupport"]),
        .testTarget(name: "PilotProfilesTests", dependencies: ["PilotProfiles", "PilotTestSupport"]),
        .testTarget(name: "PilotOverviewTests", dependencies: ["PilotOverview"]),
        .testTarget(name: "PilotAppTests", dependencies: ["PilotApp", "PilotProfiles", "PilotCore"]),
    ]
)
