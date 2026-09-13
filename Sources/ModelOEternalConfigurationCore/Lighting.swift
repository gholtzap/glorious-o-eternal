import Foundation

public struct RGBColor: Equatable, Sendable {
  public var red: UInt8
  public var green: UInt8
  public var blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }
}

public enum LightingEffect: UInt8, CaseIterable, Identifiable, Sendable {
  case off = 0
  case glorious = 1
  case singleColor = 2
  case breathingRGB = 3
  case tail = 4
  case seamlessBreathing = 5
  case rave = 7
  case wave = 9
  case breathingSingleColor = 10

  public var id: UInt8 { rawValue }

  public var identifier: String {
    switch self {
    case .off: "off"
    case .glorious: "glorious"
    case .singleColor: "single-color"
    case .breathingRGB: "breathing-rgb"
    case .tail: "tail"
    case .seamlessBreathing: "seamless-breathing"
    case .rave: "rave"
    case .wave: "wave"
    case .breathingSingleColor: "breathing-single-color"
    }
  }

  public init?(identifier: String) {
    guard let effect = Self.allCases.first(where: { $0.identifier == identifier }) else {
      return nil
    }
    self = effect
  }

  public var name: String {
    switch self {
    case .off: "Off"
    case .glorious: "Glorious"
    case .singleColor: "Single color"
    case .breathingRGB: "Breathing"
    case .tail: "Tail"
    case .seamlessBreathing: "Seamless breathing"
    case .rave: "Rave"
    case .wave: "Wave"
    case .breathingSingleColor: "Breathing, single color"
    }
  }

  public var usesColor: Bool {
    self == .singleColor || self == .breathingSingleColor
  }

  public var usesSpeed: Bool {
    self == .tail || self == .rave || self == .wave
  }

  public var usesBrightness: Bool { self != .off }
}

public struct LightingSettings: Equatable, Sendable {
  public var effect: LightingEffect
  public var color: RGBColor
  public var brightness: UInt8
  public var speed: UInt8

  public init(
    effect: LightingEffect,
    color: RGBColor,
    brightness: UInt8,
    speed: UInt8
  ) {
    self.effect = effect
    self.color = color
    self.brightness = brightness
    self.speed = speed
  }

  public func hasSameEffectiveValues(as other: Self) -> Bool {
    guard effect == other.effect else { return false }
    if effect.usesBrightness, brightness != other.brightness { return false }
    if effect.usesSpeed, speed != other.speed { return false }
    if effect.usesColor, color != other.color { return false }
    return true
  }
}

public enum PollingRate: UInt8, CaseIterable, Identifiable, Sendable {
  case hz125 = 1
  case hz250 = 2
  case hz500 = 3
  case hz1000 = 4

  public var id: UInt8 { rawValue }

  public var hertz: Int {
    switch self {
    case .hz125: 125
    case .hz250: 250
    case .hz500: 500
    case .hz1000: 1000
    }
  }

  public init?(hertz: Int) {
    guard let rate = Self.allCases.first(where: { $0.hertz == hertz }) else { return nil }
    self = rate
  }
}

public struct DPIStage: Equatable, Identifiable, Sendable {
  public let id: Int
  public var dpi: Int
  public var color: RGBColor
  public var isEnabled: Bool

  public init(id: Int, dpi: Int, color: RGBColor, isEnabled: Bool) {
    self.id = id
    self.dpi = dpi
    self.color = color
    self.isEnabled = isEnabled
  }
}

public struct SensitivitySettings: Equatable, Sendable {
  public var stages: [DPIStage]
  public var activeStage: Int
  public var pollingRate: PollingRate

  public init(stages: [DPIStage], activeStage: Int, pollingRate: PollingRate) {
    self.stages = stages
    self.activeStage = activeStage
    self.pollingRate = pollingRate
  }
}

public enum LiftOffDistance: UInt8, CaseIterable, Identifiable, Sendable {
  case twoMillimeters = 1
  case threeMillimeters = 2

  public var id: UInt8 { rawValue }
  public var millimeters: Int { self == .twoMillimeters ? 2 : 3 }

  public init?(millimeters: Int) {
    switch millimeters {
    case 2: self = .twoMillimeters
    case 3: self = .threeMillimeters
    default: return nil
    }
  }
}

public struct AdvancedSettings: Equatable, Sendable {
  public var debounceMilliseconds: Int
  public var liftOffDistance: LiftOffDistance

  public init(debounceMilliseconds: Int, liftOffDistance: LiftOffDistance) {
    self.debounceMilliseconds = debounceMilliseconds
    self.liftOffDistance = liftOffDistance
  }
}

public enum ConfigurationError: LocalizedError, Equatable {
  case invalidReportSize(Int)
  case invalidLength(Int)
  case invalidHeader(reportID: UInt8, command: UInt8)
  case unsupportedSensor(UInt8)
  case unsupportedEffect(UInt8)
  case invalidBrightness(UInt8)
  case invalidSpeed(UInt8)
  case unsupportedPollingRate(UInt8)
  case unsupportedIndependentDPI
  case invalidDPIStageCount(Int)
  case invalidDPI(stage: Int, dpi: Int)
  case invalidDPIConfiguration
  case invalidActiveDPIStage(Int)
  case invalidLiftOffDistance(UInt8)
  case invalidDebounce(Int)

  public var errorDescription: String? {
    switch self {
    case .invalidReportSize(let size):
      "The mouse returned an invalid report size: \(size)."
    case .invalidLength(let length):
      "The mouse returned an invalid configuration length: \(length)."
    case .invalidHeader(let reportID, let command):
      "The mouse returned report \(reportID), command \(command)."
    case .unsupportedSensor(let sensor):
      "The connected device has unsupported sensor code \(sensor)."
    case .unsupportedEffect(let effect):
      "The mouse uses unsupported lighting effect \(effect)."
    case .invalidBrightness(let brightness):
      "Brightness \(brightness) is outside the supported range 1 through 4."
    case .invalidSpeed(let speed):
      "Speed \(speed) is outside the supported range 1 through 3."
    case .unsupportedPollingRate(let rate):
      "The mouse uses unsupported polling-rate code \(rate)."
    case .unsupportedIndependentDPI:
      "Separate horizontal and vertical DPI values are not supported."
    case .invalidDPIStageCount(let count):
      "The mouse returned \(count) DPI stages instead of 8."
    case .invalidDPI(let stage, let dpi):
      "DPI stage \(stage) has invalid value \(dpi). Use 50 through 12000 in steps of 50."
    case .invalidDPIConfiguration:
      "At least one DPI stage must be enabled."
    case .invalidActiveDPIStage(let stage):
      "Active DPI stage \(stage) is not enabled."
    case .invalidLiftOffDistance(let value):
      "The mouse uses unsupported lift-off-distance code \(value)."
    case .invalidDebounce(let milliseconds):
      "Debounce \(milliseconds) ms is invalid. Use 4 through 16 in steps of 2."
    }
  }
}

public struct ModelOEternalConfiguration: Equatable, Sendable {
  public static let reportSize = 520
  public static let configurationLength = 131

  private enum Offset {
    static let reportID = 0
    static let command = 1
    static let writeLength = 3
    static let sensor = 9
    static let pollingRate = 10
    static let dpiState = 11
    static let disabledDPIStages = 12
    static let dpi = 13
    static let dpiColor = 29
    static let effect = 53
    static let gloriousMode = 54
    static let singleMode = 56
    static let singleColor = 57
    static let breathingRGBMode = 60
    static let tailMode = 83
    static let seamlessBreathingMode = 84
    static let raveMode = 116
    static let waveMode = 124
    static let breathingSingleMode = 125
    static let breathingSingleColor = 126
    static let liftOffDistance = 129
  }

  private let bytes: [UInt8]
  private let effect: LightingEffect
  private let pollingRate: PollingRate
  private let liftOffDistanceValue: LiftOffDistance

  public init(bytes: [UInt8], configurationLength: Int) throws {
    guard bytes.count == Self.reportSize else {
      throw ConfigurationError.invalidReportSize(bytes.count)
    }
    guard configurationLength == Self.configurationLength else {
      throw ConfigurationError.invalidLength(configurationLength)
    }
    guard bytes[Offset.reportID] == 4, bytes[Offset.command] == 0x11 else {
      throw ConfigurationError.invalidHeader(
        reportID: bytes[Offset.reportID],
        command: bytes[Offset.command]
      )
    }
    guard bytes[Offset.sensor] == 0x18 else {
      throw ConfigurationError.unsupportedSensor(bytes[Offset.sensor])
    }
    guard let pollingRate = PollingRate(rawValue: bytes[Offset.pollingRate] & 0x0f) else {
      throw ConfigurationError.unsupportedPollingRate(bytes[Offset.pollingRate] & 0x0f)
    }
    guard bytes[Offset.pollingRate] & 0x80 == 0 else {
      throw ConfigurationError.unsupportedIndependentDPI
    }
    guard let liftOffDistance = LiftOffDistance(rawValue: bytes[Offset.liftOffDistance]) else {
      throw ConfigurationError.invalidLiftOffDistance(bytes[Offset.liftOffDistance])
    }
    guard let effect = LightingEffect(rawValue: bytes[Offset.effect]) else {
      throw ConfigurationError.unsupportedEffect(bytes[Offset.effect])
    }
    let mode = bytes[Self.modeOffset(for: effect)]
    if effect.usesBrightness, !(1...4).contains(mode >> 4) {
      throw ConfigurationError.invalidBrightness(mode >> 4)
    }
    if effect.usesSpeed, !(1...3).contains(mode & 0x0f) {
      throw ConfigurationError.invalidSpeed(mode & 0x0f)
    }

    let enabledCount = (0..<8).count { bytes[Offset.disabledDPIStages] & (1 << $0) == 0 }
    let reportedCount = Int(bytes[Offset.dpiState] & 0x0f)
    let activeOrdinal = Int(bytes[Offset.dpiState] >> 4)
    guard enabledCount > 0, enabledCount == reportedCount else {
      throw ConfigurationError.invalidDPIConfiguration
    }
    guard (1...enabledCount).contains(activeOrdinal) else {
      throw ConfigurationError.invalidActiveDPIStage(activeOrdinal)
    }

    self.bytes = bytes
    self.effect = effect
    self.pollingRate = pollingRate
    self.liftOffDistanceValue = liftOffDistance
  }

  public var settings: LightingSettings {
    let mode = bytes[Self.modeOffset(for: effect)]
    let colorOffset =
      effect == .breathingSingleColor
      ? Offset.breathingSingleColor
      : Offset.singleColor

    return LightingSettings(
      effect: effect,
      color: readRBGColor(at: colorOffset),
      brightness: max(mode >> 4, 1),
      speed: max(mode & 0x0f, 1)
    )
  }

  public var sensitivitySettings: SensitivitySettings {
    let disabled = bytes[Offset.disabledDPIStages]
    let activeOrdinal = Int(bytes[Offset.dpiState] >> 4)
    var enabledOrdinal = 0
    var activeStage = 1
    let stages = (0..<8).map { index in
      let isEnabled = disabled & (1 << index) == 0
      if isEnabled {
        enabledOrdinal += 1
        if enabledOrdinal == activeOrdinal { activeStage = index + 1 }
      }
      return DPIStage(
        id: index + 1,
        dpi: (Int(bytes[Offset.dpi + index]) + 1) * 50,
        color: readRBGColor(at: Offset.dpiColor + index * 3),
        isEnabled: isEnabled
      )
    }
    return SensitivitySettings(
      stages: stages,
      activeStage: activeStage,
      pollingRate: pollingRate
    )
  }

  public var liftOffDistance: LiftOffDistance {
    liftOffDistanceValue
  }

  public func applying(_ settings: LightingSettings) throws -> [UInt8] {
    guard (1...4).contains(settings.brightness) else {
      throw ConfigurationError.invalidBrightness(settings.brightness)
    }
    guard (1...3).contains(settings.speed) else {
      throw ConfigurationError.invalidSpeed(settings.speed)
    }

    var result = bytes
    prepareWrite(&result)
    result[Offset.effect] = settings.effect.rawValue

    if settings.effect != .off {
      let offset = Self.modeOffset(for: settings.effect)
      let oldMode = result[offset]
      let speed = settings.effect.usesSpeed ? settings.speed : oldMode & 0x0f
      result[offset] = (settings.brightness << 4) | speed
    }

    if settings.effect.usesColor {
      let colorOffset =
        settings.effect == .breathingSingleColor
        ? Offset.breathingSingleColor
        : Offset.singleColor
      writeRBGColor(settings.color, to: &result, at: colorOffset)
    }

    return result
  }

  public func applying(_ settings: SensitivitySettings) throws -> [UInt8] {
    try Self.validate(settings)
    var result = bytes
    prepareWrite(&result)
    result[Offset.pollingRate] =
      (result[Offset.pollingRate] & 0xf0) | settings.pollingRate.rawValue

    let enabled = settings.stages.filter(\.isEnabled)
    guard let activeIndex = enabled.firstIndex(where: { $0.id == settings.activeStage }) else {
      throw ConfigurationError.invalidActiveDPIStage(settings.activeStage)
    }
    let activeOrdinal = activeIndex + 1
    result[Offset.dpiState] = UInt8((activeOrdinal << 4) | enabled.count)
    result[Offset.disabledDPIStages] = settings.stages.reduce(0) { mask, stage in
      stage.isEnabled ? mask : mask | UInt8(1 << (stage.id - 1))
    }

    for stage in settings.stages {
      result[Offset.dpi + stage.id - 1] = UInt8(stage.dpi / 50 - 1)
      writeRBGColor(stage.color, to: &result, at: Offset.dpiColor + (stage.id - 1) * 3)
    }
    return result
  }

  public func applying(_ liftOffDistance: LiftOffDistance) -> [UInt8] {
    var result = bytes
    prepareWrite(&result)
    result[Offset.liftOffDistance] = liftOffDistance.rawValue
    return result
  }

  public func verifies(_ expected: LightingSettings, in readBack: ModelOEternalConfiguration)
    -> Bool
  {
    readBack.settings.hasSameEffectiveValues(as: expected)
  }

  public func verifies(
    _ expected: SensitivitySettings, in readBack: ModelOEternalConfiguration
  ) -> Bool {
    readBack.sensitivitySettings == expected
  }

  public func verifies(
    _ expected: LiftOffDistance, in readBack: ModelOEternalConfiguration
  ) -> Bool {
    readBack.liftOffDistance == expected
  }

  public static func validate(_ settings: SensitivitySettings) throws {
    guard settings.stages.count == 8,
      settings.stages.map(\.id) == Array(1...8)
    else {
      throw ConfigurationError.invalidDPIStageCount(settings.stages.count)
    }
    for stage in settings.stages
    where !(50...12_000).contains(stage.dpi) || stage.dpi % 50 != 0 {
      throw ConfigurationError.invalidDPI(stage: stage.id, dpi: stage.dpi)
    }
    guard settings.stages.contains(where: \.isEnabled) else {
      throw ConfigurationError.invalidDPIConfiguration
    }
    guard (1...8).contains(settings.activeStage),
      settings.stages[settings.activeStage - 1].isEnabled
    else {
      throw ConfigurationError.invalidActiveDPIStage(settings.activeStage)
    }
  }

  private func prepareWrite(_ result: inout [UInt8]) {
    result[Offset.reportID] = 4
    result[Offset.command] = 0x11
    result[Offset.writeLength] = UInt8(Self.configurationLength - 8)
  }

  private static func modeOffset(for effect: LightingEffect) -> Int {
    switch effect {
    case .off, .glorious: Offset.gloriousMode
    case .singleColor: Offset.singleMode
    case .breathingRGB: Offset.breathingRGBMode
    case .tail: Offset.tailMode
    case .seamlessBreathing: Offset.seamlessBreathingMode
    case .rave: Offset.raveMode
    case .wave: Offset.waveMode
    case .breathingSingleColor: Offset.breathingSingleMode
    }
  }

  private func readRBGColor(at offset: Int) -> RGBColor {
    RGBColor(red: bytes[offset], green: bytes[offset + 2], blue: bytes[offset + 1])
  }

  private func writeRBGColor(_ color: RGBColor, to bytes: inout [UInt8], at offset: Int) {
    bytes[offset] = color.red
    bytes[offset + 1] = color.blue
    bytes[offset + 2] = color.green
  }
}
