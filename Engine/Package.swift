// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CardCopilotEngine",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "CardCopilotEngine", targets: ["CardCopilotEngine"])],
    targets: [
        .target(name: "CardCopilotEngine", resources: [.process("Resources")]),
        .testTarget(
            name: "CardCopilotEngineTests",
            dependencies: ["CardCopilotEngine"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
