// swift-tools-version: 6.0

// In-process multi-turn probe for a Core AI LLM bundle through FoundationModels
// (CoreAILanguageModel + LanguageModelSession). See coreai/env.md section 4.5.
// Build with Xcode-beta (DEVELOPER_DIR) and a scratch path outside this repo:
//   swift build -c release --package-path . --scratch-path ~/Developer/mlsys/serving/coreai-models/.build/fm-probe

import PackageDescription

let package = Package(
    name: "coreai-fm-probe",
    platforms: [.macOS("27.0")],
    dependencies: [
        // ~/Developer/mlsys/serving/coreai-models (apple/coreai-models clone)
        .package(path: "../../../../serving/coreai-models")
    ],
    targets: [
        .executableTarget(
            name: "coreai-fm-probe",
            dependencies: [
                .product(name: "CoreAILM", package: "coreai-models")
            ],
            path: "Sources/coreai-fm-probe"
        )
    ],
    swiftLanguageModes: [.v6]
)
