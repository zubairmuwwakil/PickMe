// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CardCopilotStore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "CardCopilotStore", targets: ["CardCopilotStore"])],
    dependencies: [.package(path: "../Engine")],
    targets: [
        .target(name: "CardCopilotStore",
                dependencies: [.product(name: "CardCopilotEngine", package: "Engine")]),
        .testTarget(name: "CardCopilotStoreTests", dependencies: ["CardCopilotStore"]),
    ]
)
