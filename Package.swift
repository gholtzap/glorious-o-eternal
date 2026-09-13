// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "EternalLights",
  platforms: [.macOS(.v15)],
  products: [
    .executable(name: "EternalLights", targets: ["EternalLightsApp"]),
    .executable(name: "eternal-lights", targets: ["EternalLightsCLI"]),
  ],
  targets: [
    .target(
      name: "EternalLightsCore",
      linkerSettings: [.linkedFramework("IOKit")]
    ),
    .executableTarget(
      name: "EternalLightsApp",
      dependencies: ["EternalLightsCore"]
    ),
    .executableTarget(
      name: "EternalLightsCLI",
      dependencies: ["EternalLightsCore"]
    ),
    .testTarget(
      name: "EternalLightsCoreTests",
      dependencies: ["EternalLightsCore"]
    ),
    .testTarget(
      name: "EternalLightsCLITests",
      dependencies: ["EternalLightsCLI"]
    ),
  ]
)
