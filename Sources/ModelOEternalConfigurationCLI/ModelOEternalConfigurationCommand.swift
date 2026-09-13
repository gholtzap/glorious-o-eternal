import Foundation
import ModelOEternalConfigurationCore

enum Command: Equatable {
  case capabilities
  case effects
  case status
  case set(SettingsPatch)
  case help
  case version
}

struct SettingsPatch: Equatable {
  var effect: LightingEffect?
  var color: RGBColor?
  var brightness: UInt8?
  var speed: UInt8?
  var dryRun = false
}

enum CLIError: LocalizedError, Equatable {
  case usage(String)

  var errorDescription: String? {
    switch self {
    case .usage(let message): message
    }
  }
}

enum Arguments {
  static func parse(_ arguments: [String]) throws -> Command {
    guard let name = arguments.first else { return .help }
    let rest = Array(arguments.dropFirst())

    switch name {
    case "capabilities":
      try requireNoArguments(rest, command: name)
      return .capabilities
    case "effects":
      try requireNoArguments(rest, command: name)
      return .effects
    case "status":
      try requireNoArguments(rest, command: name)
      return .status
    case "set":
      return .set(try parseSet(rest))
    case "help", "--help", "-h":
      try requireNoArguments(rest, command: name)
      return .help
    case "--version", "version":
      try requireNoArguments(rest, command: name)
      return .version
    default:
      throw CLIError.usage("Unknown command '\(name)'. Run 'model-o-eternal-config help'.")
    }
  }

  private static func parseSet(_ arguments: [String]) throws -> SettingsPatch {
    var patch = SettingsPatch()
    var index = 0

    while index < arguments.count {
      let option = arguments[index]
      if option == "--dry-run" {
        guard !patch.dryRun else { throw duplicate(option) }
        patch.dryRun = true
        index += 1
        continue
      }

      guard index + 1 < arguments.count else {
        throw CLIError.usage("Option '\(option)' needs a value.")
      }
      let value = arguments[index + 1]
      switch option {
      case "--effect":
        guard patch.effect == nil else { throw duplicate(option) }
        guard let effect = LightingEffect(identifier: value) else {
          throw CLIError.usage(
            "Unknown effect '\(value)'. Run 'model-o-eternal-config effects'.")
        }
        patch.effect = effect
      case "--color":
        guard patch.color == nil else { throw duplicate(option) }
        patch.color = try parseColor(value)
      case "--brightness":
        guard patch.brightness == nil else { throw duplicate(option) }
        patch.brightness = try parseLevel(value, option: option, range: 1...4)
      case "--speed":
        guard patch.speed == nil else { throw duplicate(option) }
        patch.speed = try parseLevel(value, option: option, range: 1...3)
      default:
        throw CLIError.usage("Unknown option '\(option)'. Run 'model-o-eternal-config help'.")
      }
      index += 2
    }

    guard patch.effect != nil || patch.color != nil || patch.brightness != nil || patch.speed != nil
    else {
      throw CLIError.usage("The set command needs at least one setting.")
    }
    return patch
  }

  private static func parseColor(_ value: String) throws -> RGBColor {
    let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
    guard hex.count == 6, let number = UInt32(hex, radix: 16) else {
      throw CLIError.usage("Color must be six hexadecimal digits, for example '#7c3aed'.")
    }
    return RGBColor(
      red: UInt8((number >> 16) & 0xff),
      green: UInt8((number >> 8) & 0xff),
      blue: UInt8(number & 0xff)
    )
  }

  private static func parseLevel(_ value: String, option: String, range: ClosedRange<UInt8>) throws
    -> UInt8
  {
    guard let level = UInt8(value), range.contains(level) else {
      throw CLIError.usage(
        "\(option) must be in the range \(range.lowerBound) through \(range.upperBound).")
    }
    return level
  }

  private static func requireNoArguments(_ arguments: [String], command: String) throws {
    guard arguments.isEmpty else {
      throw CLIError.usage("The \(command) command does not accept arguments.")
    }
  }

  private static func duplicate(_ option: String) -> CLIError {
    .usage("Option '\(option)' was specified more than once.")
  }
}

@main
enum ModelOEternalConfigurationCommand {
  static let version = "0.1.0"

  static func main() {
    do {
      let command = try Arguments.parse(Array(CommandLine.arguments.dropFirst()))
      try run(command)
    } catch {
      writeJSON(
        [
          "ok": false,
          "error": [
            "code": errorCode(for: error),
            "message": error.localizedDescription,
            "remediation": remediation(for: error),
          ],
        ], to: .standardError)
      exit(error is CLIError ? 2 : 3)
    }
  }

  private static func run(_ command: Command) throws {
    switch command {
    case .help:
      print(help)
    case .version:
      print(version)
    case .capabilities:
      writeJSON([
        "ok": true,
        "result": [
          "name": "Model O Eternal Configuration",
          "version": version,
          "output": "JSON",
          "device": ["vendorId": "3794", "productId": "a000"],
          "commands": ["capabilities", "effects", "status", "set"],
          "brightnessRange": [1, 4],
          "speedRange": [1, 3],
          "setIsPartialUpdate": true,
          "setSupportsDryRun": true,
        ],
      ])
    case .effects:
      writeJSON([
        "ok": true,
        "result": LightingEffect.allCases.map(effectJSON),
      ])
    case .status:
      let settings = try ModelOEternalDevice().readSettings()
      writeJSON([
        "ok": true,
        "result": [
          "connected": true,
          "device": ["vendorId": "3794", "productId": "a000"],
          "settings": settingsJSON(settings),
        ],
      ])
    case .set(let patch):
      let device = ModelOEternalDevice()
      let before = try device.readSettings()
      let requestedEffect = patch.effect ?? before.effect
      if patch.color != nil, !requestedEffect.usesColor {
        throw CLIError.usage("Effect '\(requestedEffect.identifier)' does not use --color.")
      }
      if patch.brightness != nil, !requestedEffect.usesBrightness {
        throw CLIError.usage("Effect '\(requestedEffect.identifier)' does not use --brightness.")
      }
      if patch.speed != nil, !requestedEffect.usesSpeed {
        throw CLIError.usage("Effect '\(requestedEffect.identifier)' does not use --speed.")
      }

      let requested = LightingSettings(
        effect: requestedEffect,
        color: patch.color ?? before.color,
        brightness: patch.brightness ?? before.brightness,
        speed: patch.speed ?? before.speed
      )
      let changed = !before.hasSameEffectiveValues(as: requested)
      if changed && !patch.dryRun {
        try device.apply(requested)
      }
      let final = patch.dryRun ? requested : try device.readSettings()
      writeJSON([
        "ok": true,
        "result": [
          "changed": changed,
          "dryRun": patch.dryRun,
          "before": settingsJSON(before),
          "settings": settingsJSON(final),
        ],
      ])
    }
  }

  private static func effectJSON(_ effect: LightingEffect) -> [String: Any] {
    [
      "id": effect.identifier,
      "name": effect.name,
      "usesColor": effect.usesColor,
      "usesBrightness": effect.usesBrightness,
      "usesSpeed": effect.usesSpeed,
    ]
  }

  private static func settingsJSON(_ settings: LightingSettings) -> [String: Any] {
    [
      "effect": settings.effect.identifier,
      "color": String(
        format: "#%02x%02x%02x", settings.color.red, settings.color.green, settings.color.blue),
      "brightness": settings.brightness,
      "speed": settings.speed,
    ]
  }

  private static func writeJSON(_ value: Any, to handle: FileHandle = .standardOutput) {
    guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    else {
      handle.write(
        Data(
          "{\"error\":{\"code\":\"serialization_failed\",\"message\":\"The response could not be encoded.\"},\"ok\":false}\n"
            .utf8))
      return
    }
    handle.write(data)
    handle.write(Data([0x0a]))
  }

  private static func errorCode(for error: Error) -> String {
    if error is CLIError { return "invalid_arguments" }
    guard let deviceError = error as? ModelOEternalDeviceError else {
      return "device_error"
    }
    switch deviceError {
    case .notConnected: return "device_not_connected"
    case .inputMonitoringRequired: return "input_monitoring_required"
    case .verificationFailed: return "verification_failed"
    default: return "device_io_failed"
    }
  }

  private static func remediation(for error: Error) -> String {
    switch errorCode(for: error) {
    case "invalid_arguments":
      return "Run 'model-o-eternal-config help' and correct the request."
    case "device_not_connected": return "Connect a wired Model O Eternal and try again."
    case "input_monitoring_required":
      return
        "Allow the calling terminal or agent host in System Settings > Privacy & Security > Input Monitoring."
    default: return "Reconnect the mouse and try once more."
    }
  }

  private static let help = """
    Control the lighting on a wired Glorious Model O Eternal.

    Usage:
      model-o-eternal-config capabilities
      model-o-eternal-config effects
      model-o-eternal-config status
      model-o-eternal-config set [--effect ID] [--color RRGGBB] [--brightness 1-4] [--speed 1-3] [--dry-run]
      model-o-eternal-config --version

    Commands return one JSON object. The set command changes only the supplied settings.
    Use 'model-o-eternal-config effects' to see which settings each effect accepts.
    """
}
