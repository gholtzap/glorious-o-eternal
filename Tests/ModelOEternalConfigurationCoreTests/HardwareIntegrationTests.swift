import Foundation
import Testing

@testable import ModelOEternalConfigurationCore

@Suite(.serialized)
struct HardwareIntegrationTests {
  @Test(
    .enabled(if: ProcessInfo.processInfo.environment["MODEL_O_ETERNAL_HARDWARE_TEST"] == "1"))
  func readsConnectedModelOEternalWithoutWriting() throws {
    let raw = try ModelOEternalDevice().readRawConfigurationSnapshot()

    let report = try ModelOEternalConfiguration(bytes: raw.bytes, configurationLength: raw.length)
    let state = try ModelOEternalDevice().readState()
    #expect(raw.length == ModelOEternalConfiguration.configurationLength)
    #expect(report.sensitivitySettings.stages[0].dpi % 50 == 0)
    #expect(state.buttons.actions.count == 6)
    #expect(!state.firmwareVersion.isEmpty)
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

  @Test(
    .enabled(
      if: ProcessInfo.processInfo.environment["MODEL_O_ETERNAL_HARDWARE_WRITE_TEST"] == "1"))
  func writesVerifiesAndRestoresOtherSettings() throws {
    let mouse = ModelOEternalDevice()
    let original = try mouse.readState()
    defer {
      try? mouse.apply(original.sensitivity)
      try? mouse.apply(original.buttons)
      if original.advanced.debounceMilliseconds >= 4 {
        try? mouse.applyDebounce(milliseconds: original.advanced.debounceMilliseconds)
      }
      try? mouse.apply(original.advanced.liftOffDistance)
    }

    var sensitivity = original.sensitivity
    sensitivity.pollingRate = sensitivity.pollingRate == .hz500 ? .hz1000 : .hz500
    sensitivity.stages[sensitivity.activeStage - 1].dpi += 50
    try mouse.apply(sensitivity)
    #expect(try mouse.readSensitivity() == sensitivity)

    var buttons = original.buttons
    buttons.actions[ButtonControl.dpi.rawValue] = ButtonAction(identifier: "dpi-up")!
    try mouse.apply(buttons)
    #expect(try mouse.readButtons() == buttons)

    if original.advanced.debounceMilliseconds >= 4 {
      let debounce = original.advanced.debounceMilliseconds == 4 ? 6 : 4
      try mouse.applyDebounce(milliseconds: debounce)
      #expect(try mouse.readAdvanced().debounceMilliseconds == debounce)
    }

    let liftOffDistance: LiftOffDistance =
      original.advanced.liftOffDistance == .twoMillimeters ? .threeMillimeters : .twoMillimeters
    try mouse.apply(liftOffDistance)
    #expect(try mouse.readAdvanced().liftOffDistance == liftOffDistance)
  }
}
