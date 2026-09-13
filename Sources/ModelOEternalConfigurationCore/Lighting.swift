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

public enum ConfigurationError: LocalizedError, Equatable {
  case invalidReportSize(Int)
  case invalidLength(Int)
  case invalidHeader(reportID: UInt8, command: UInt8)
  case unsupportedSensor(UInt8)
  case unsupportedEffect(UInt8)
  case invalidBrightness(UInt8)
  case invalidSpeed(UInt8)

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
  }

  private let bytes: [UInt8]
  private let effect: LightingEffect

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

    self.bytes = bytes
    self.effect = effect
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

  public func applying(_ settings: LightingSettings) throws -> [UInt8] {
    guard (1...4).contains(settings.brightness) else {
      throw ConfigurationError.invalidBrightness(settings.brightness)
    }
    guard (1...3).contains(settings.speed) else {
      throw ConfigurationError.invalidSpeed(settings.speed)
    }

    var result = bytes
    result[Offset.reportID] = 4
    result[Offset.command] = 0x11
    result[Offset.writeLength] = UInt8(Self.configurationLength - 8)
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

  public func verifies(_ expected: LightingSettings, in readBack: ModelOEternalConfiguration)
    -> Bool
  {
    readBack.settings.hasSameEffectiveValues(as: expected)
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
