import Testing

@testable import ModelOEternalConfigurationCore

struct ModelOEternalConfigurationTests {
  @Test
  func readsSingleColorInRBGOrder() throws {
    var bytes = validReport()
    bytes[53] = LightingEffect.singleColor.rawValue
    bytes[56] = 0x40
    bytes[57...59] = [0x11, 0x33, 0x22]

    let report = try ModelOEternalConfiguration(bytes: bytes, configurationLength: 131)

    #expect(
      report.settings
        == LightingSettings(
          effect: .singleColor,
          color: RGBColor(red: 0x11, green: 0x22, blue: 0x33),
          brightness: 4,
          speed: 1
        ))
  }

  @Test
  func changesOnlyLightingAndWriteHeader() throws {
    var bytes = validReport()
    bytes[3] = 0
    let report = try ModelOEternalConfiguration(bytes: bytes, configurationLength: 131)
    let settings = LightingSettings(
      effect: .singleColor,
      color: RGBColor(red: 0xaa, green: 0xbb, blue: 0xcc),
      brightness: 3,
      speed: 2
    )

    let changed = try report.applying(settings)
    let changedIndices = zip(bytes, changed).indicesWhereValuesDiffer

    #expect(changedIndices == [3, 53, 56, 57, 58, 59])
    #expect(changed[3] == 123)
    #expect(changed[53] == LightingEffect.singleColor.rawValue)
    #expect(changed[56] == 0x30)
    #expect(Array(changed[57...59]) == [0xaa, 0xcc, 0xbb])
  }

  @Test
  func rejectsUnexpectedDeviceData() {
    var wrongSensor = validReport()
    wrongSensor[9] = 0x06
    #expect(throws: ConfigurationError.unsupportedSensor(0x06)) {
      try ModelOEternalConfiguration(bytes: wrongSensor, configurationLength: 131)
    }

    var unknownEffect = validReport()
    unknownEffect[53] = 0xff
    #expect(throws: ConfigurationError.unsupportedEffect(0xff)) {
      try ModelOEternalConfiguration(bytes: unknownEffect, configurationLength: 131)
    }

    #expect(throws: ConfigurationError.invalidReportSize(519)) {
      try ModelOEternalConfiguration(
        bytes: Array(validReport().dropLast()),
        configurationLength: 131
      )
    }
  }

  @Test
  func rejectsInvalidActiveModeValues() {
    var invalidBrightness = validReport()
    invalidBrightness[54] = 0x52
    #expect(throws: ConfigurationError.invalidBrightness(5)) {
      try ModelOEternalConfiguration(bytes: invalidBrightness, configurationLength: 131)
    }

    var invalidSpeed = validReport()
    invalidSpeed[53] = LightingEffect.wave.rawValue
    invalidSpeed[124] = 0x44
    #expect(throws: ConfigurationError.invalidSpeed(4)) {
      try ModelOEternalConfiguration(bytes: invalidSpeed, configurationLength: 131)
    }
  }

  @Test
  func validatesUserSettings() throws {
    let report = try ModelOEternalConfiguration(bytes: validReport(), configurationLength: 131)

    #expect(throws: ConfigurationError.invalidBrightness(0)) {
      try report.applying(
        LightingSettings(
          effect: .wave,
          color: RGBColor(red: 0, green: 0, blue: 0),
          brightness: 0,
          speed: 1
        ))
    }
    #expect(throws: ConfigurationError.invalidSpeed(4)) {
      try report.applying(
        LightingSettings(
          effect: .wave,
          color: RGBColor(red: 0, green: 0, blue: 0),
          brightness: 1,
          speed: 4
        ))
    }
  }

  @Test
  func turningLightingOffPreservesAllEffectParameters() throws {
    let bytes = validReport()
    let report = try ModelOEternalConfiguration(bytes: bytes, configurationLength: 131)

    let changed = try report.applying(
      LightingSettings(
        effect: .off,
        color: RGBColor(red: 0, green: 0, blue: 0),
        brightness: 1,
        speed: 1
      ))

    #expect(zip(bytes, changed).indicesWhereValuesDiffer == [3, 53])
  }

  @Test
  func verifiesOnlySettingsUsedByTheEffect() throws {
    let original = try ModelOEternalConfiguration(bytes: validReport(), configurationLength: 131)
    let expected = LightingSettings(
      effect: .wave,
      color: RGBColor(red: 1, green: 2, blue: 3),
      brightness: 2,
      speed: 3
    )
    let changed = try original.applying(expected)
    let readBack = try ModelOEternalConfiguration(bytes: changed, configurationLength: 131)

    #expect(original.verifies(expected, in: readBack))
  }

  @Test
  func readsAndWritesSensitivityAndLiftOffDistance() throws {
    let bytes = validReport()
    let report = try ModelOEternalConfiguration(bytes: bytes, configurationLength: 131)
    #expect(report.sensitivitySettings.stages.map(\.dpi) == [400, 800, 1600, 3200, 50, 50, 50, 50])
    #expect(report.sensitivitySettings.activeStage == 3)
    #expect(report.sensitivitySettings.pollingRate == .hz1000)
    #expect(report.liftOffDistance == .threeMillimeters)

    var settings = report.sensitivitySettings
    settings.stages[2].dpi = 1650
    settings.stages[4].isEnabled = true
    settings.activeStage = 5
    settings.pollingRate = .hz500
    let changed = try report.applying(settings)
    let readBack = try ModelOEternalConfiguration(bytes: changed, configurationLength: 131)
    #expect(readBack.sensitivitySettings == settings)
    #expect(
      report.verifies(
        .twoMillimeters,
        in: try .init(bytes: report.applying(.twoMillimeters), configurationLength: 131)))
  }

  @Test
  func rejectsInvalidSensitivity() throws {
    let report = try ModelOEternalConfiguration(bytes: validReport(), configurationLength: 131)
    var settings = report.sensitivitySettings
    settings.stages[0].dpi = 425
    #expect(throws: ConfigurationError.invalidDPI(stage: 1, dpi: 425)) {
      try report.applying(settings)
    }
    settings = report.sensitivitySettings
    settings.activeStage = 9
    #expect(throws: ConfigurationError.invalidActiveDPIStage(9)) {
      try report.applying(settings)
    }
  }

  private func validReport() -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: ModelOEternalConfiguration.reportSize)
    bytes[0] = 4
    bytes[1] = 0x11
    bytes[9] = 0x18
    bytes[10] = 4
    bytes[11] = 0x34
    bytes[12] = 0xf0
    bytes[13...16] = [7, 15, 31, 63]
    bytes[53] = LightingEffect.glorious.rawValue
    bytes[54] = 0x42
    bytes[56] = 0x40
    bytes[60] = 0x42
    bytes[83] = 0x42
    bytes[84] = 0x42
    bytes[116] = 0x42
    bytes[124] = 0x42
    bytes[125] = 0x42
    bytes[129] = 2
    return bytes
  }
}

extension Zip2Sequence<[UInt8], [UInt8]> {
  fileprivate var indicesWhereValuesDiffer: [Int] {
    enumerated().compactMap { index, pair in pair.0 == pair.1 ? nil : index }
  }
}
