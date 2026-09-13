// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "ModelOEternalConfiguration",
  platforms: [.macOS(.v15)],
  products: [
    .executable(
      name: "ModelOEternalConfiguration", targets: ["ModelOEternalConfigurationApp"]),
    .executable(name: "model-o-eternal-config", targets: ["ModelOEternalConfigurationCLI"]),
  ],
  targets: [
    .target(
      name: "ModelOEternalConfigurationCore",
      linkerSettings: [.linkedFramework("IOKit")]
    ),
    .executableTarget(
      name: "ModelOEternalConfigurationApp",
      dependencies: ["ModelOEternalConfigurationCore"]
    ),
    .executableTarget(
      name: "ModelOEternalConfigurationCLI",
      dependencies: ["ModelOEternalConfigurationCore"]
    ),
    .testTarget(
      name: "ModelOEternalConfigurationCoreTests",
      dependencies: ["ModelOEternalConfigurationCore"]
    ),
    .testTarget(
      name: "ModelOEternalConfigurationCLITests",
      dependencies: ["ModelOEternalConfigurationCLI"]
    ),
  ]
)
