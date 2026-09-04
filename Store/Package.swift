// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CardCopilotStore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "CardCopilotStore", targets: ["CardCopilotStore"]),
        .library(name: "CardCopilotCapture", targets: ["CardCopilotCapture"]),
    ],
    dependencies: [.package(path: "../Engine")],
    targets: [
        .target(name: "CardCopilotStore",
                dependencies: [.product(name: "CardCopilotEngine", package: "Engine")],
                resources: [.process("Resources")]),
        .target(name: "CardCopilotCapture",
                dependencies: [.product(name: "CardCopilotEngine", package: "Engine")]),
        .testTarget(name: "CardCopilotStoreTests", dependencies: ["CardCopilotStore"]),
        .testTarget(name: "CardCopilotCaptureTests", dependencies: ["CardCopilotCapture"]),
    ]
)
