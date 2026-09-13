import Foundation
import Testing

@testable import ModelOEternalConfigurationCore

struct HardwareIntegrationTests {
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["MODEL_O_ETERNAL_HARDWARE_TEST"] == "1"))
  func readsConnectedModelOEternalWithoutWriting() throws {
    let raw = try ModelOEternalDevice().readRawConfigurationSnapshot()

    let report = try ModelOEternalConfiguration(bytes: raw.bytes, configurationLength: raw.length)
    print("Connected configuration length: \(raw.length)")
    print("Current lighting settings: \(report.settings)")
    #expect(raw.length == ModelOEternalConfiguration.configurationLength)
  }

  @Test(
    .enabled(
      if: ProcessInfo.processInfo.environment["MODEL_O_ETERNAL_HARDWARE_WRITE_TEST"] == "1"))
  func writesVerifiesAndRestoresEveryLightingEffect() throws {
    let mouse = ModelOEternalDevice()
    let original = try mouse.readSettings()
    defer { try? mouse.apply(original) }

    for effect in LightingEffect.allCases {
      let testSettings = LightingSettings(
        effect: effect,
        color: RGBColor(red: 124, green: 58, blue: 237),
        brightness: 1,
        speed: 3
      )
      try mouse.apply(testSettings)
      #expect(try mouse.readSettings().effect == effect)
    }

    try mouse.apply(original)
    #expect(try mouse.readSettings().effect == original.effect)
  }
}
