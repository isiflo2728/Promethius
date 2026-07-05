// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentKit",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "AgentKit", targets: ["AgentKit"]),
    ],
    dependencies: [
        // Shared, cross-platform code only. Anything Mac-only (inference,
        // FSEvents, EventKit tools, the Composio API key) lives in the
        // AgentHubMac target — NOT here.
    ],
    targets: [
        .target(
            name: "AgentKit",
            dependencies: []
        ),
        .testTarget(
            name: "AgentKitTests",
            dependencies: ["AgentKit"]
        ),
    ]
)
