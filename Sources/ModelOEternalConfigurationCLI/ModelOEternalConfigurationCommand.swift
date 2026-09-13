import Foundation
import ModelOEternalConfigurationCore

enum Command: Equatable {
  case capabilities, effects, status, sensitivity, buttons, buttonActions, advanced, device, help,
    version
  case set(LightingPatch)
  case setDPI(DPIPatch)
  case setPolling(PollingRate, dryRun: Bool)
  case setButton(ButtonControl, ButtonAction, dryRun: Bool)
  case setDebounce(Int, dryRun: Bool)
  case setLiftOffDistance(LiftOffDistance, dryRun: Bool)
}

struct LightingPatch: Equatable {
  var effect: LightingEffect?
  var color: RGBColor?
  var brightness: UInt8?
  var speed: UInt8?
  var dryRun = false
}

typealias SettingsPatch = LightingPatch

struct DPIPatch: Equatable {
  var stage: Int
  var dpi: Int?
  var color: RGBColor?
  var enabled: Bool?
  var active = false
  var dryRun = false
}

enum CLIError: LocalizedError, Equatable {
  case usage(String)
  var errorDescription: String? { if case .usage(let message) = self { message } else { nil } }
}

enum Arguments {
  static func parse(_ arguments: [String]) throws -> Command {
    guard let name = arguments.first else { return .help }
    let rest = Array(arguments.dropFirst())
    switch name {
    case "capabilities":
      try none(rest, name)
      return .capabilities
    case "effects":
      try none(rest, name)
      return .effects
    case "status":
      try none(rest, name)
      return .status
    case "sensitivity":
      try none(rest, name)
      return .sensitivity
    case "buttons":
      try none(rest, name)
      return .buttons
    case "button-actions":
      try none(rest, name)
      return .buttonActions
    case "advanced":
      try none(rest, name)
      return .advanced
    case "device":
      try none(rest, name)
      return .device
    case "set": return .set(try parseLighting(rest))
    case "set-dpi": return .setDPI(try parseDPI(rest))
    case "set-polling-rate":
      let values = try options(rest, flags: ["--dry-run"])
      guard let text = values["--hz"] ?? nil, let hertz = Int(text),
        let rate = PollingRate(hertz: hertz)
      else {
        throw usage("--hz must be 125, 250, 500, or 1000.")
      }
      try exact(values, ["--hz", "--dry-run"])
      return .setPolling(rate, dryRun: values["--dry-run"] != nil)
    case "set-button":
      let values = try options(rest, flags: ["--dry-run"])
      guard let text = values["--button"] ?? nil, let button = ButtonControl(identifier: text)
      else {
        throw usage("--button must name one of the six controls.")
      }
      guard let text = values["--action"] ?? nil, let action = ButtonAction(identifier: text) else {
        throw usage("--action must be an ID from button-actions.")
      }
      try exact(values, ["--button", "--action", "--dry-run"])
      return .setButton(button, action, dryRun: values["--dry-run"] != nil)
    case "set-debounce":
      let values = try options(rest, flags: ["--dry-run"])
      guard let text = values["--milliseconds"] ?? nil, let value = Int(text),
        stride(from: 4, through: 16, by: 2).contains(value)
      else { throw usage("--milliseconds must be 4, 6, 8, 10, 12, 14, or 16.") }
      try exact(values, ["--milliseconds", "--dry-run"])
      return .setDebounce(value, dryRun: values["--dry-run"] != nil)
    case "set-lift-off-distance":
      let values = try options(rest, flags: ["--dry-run"])
      guard let text = values["--millimeters"] ?? nil, let value = Int(text),
        let distance = LiftOffDistance(millimeters: value)
      else { throw usage("--millimeters must be 2 or 3.") }
      try exact(values, ["--millimeters", "--dry-run"])
      return .setLiftOffDistance(distance, dryRun: values["--dry-run"] != nil)
    case "help", "--help", "-h":
      try none(rest, name)
      return .help
    case "--version", "version":
      try none(rest, name)
      return .version
    default: throw usage("Unknown command '\(name)'. Run 'model-o-eternal-config help'.")
    }
  }

  private static func parseLighting(_ arguments: [String]) throws -> LightingPatch {
    let values = try options(arguments, flags: ["--dry-run"])
    try exact(values, ["--effect", "--color", "--brightness", "--speed", "--dry-run"])
    var patch = LightingPatch(dryRun: values["--dry-run"] != nil)
    if let value = values["--effect"] ?? nil {
      guard let effect = LightingEffect(identifier: value) else {
        throw usage("Unknown effect '\(value)'.")
      }
      patch.effect = effect
    }
    if let value = values["--color"] ?? nil { patch.color = try color(value) }
    if let value = values["--brightness"] ?? nil {
      patch.brightness = try level(value, "--brightness", 1...4)
    }
    if let value = values["--speed"] ?? nil { patch.speed = try level(value, "--speed", 1...3) }
    guard patch.effect != nil || patch.color != nil || patch.brightness != nil || patch.speed != nil
    else {
      throw usage("The set command needs at least one setting.")
    }
    return patch
  }

  private static func parseDPI(_ arguments: [String]) throws -> DPIPatch {
    let values = try options(arguments, flags: ["--active", "--dry-run"])
    try exact(values, ["--stage", "--dpi", "--color", "--enabled", "--active", "--dry-run"])
    guard let text = values["--stage"] ?? nil, let stage = Int(text), (1...8).contains(stage) else {
      throw usage("--stage must be 1 through 8.")
    }
    var patch = DPIPatch(
      stage: stage, active: values["--active"] != nil, dryRun: values["--dry-run"] != nil)
    if let text = values["--dpi"] ?? nil {
      guard let dpi = Int(text), (50...12_000).contains(dpi), dpi % 50 == 0 else {
        throw usage("--dpi must be 50 through 12000 in steps of 50.")
      }
      patch.dpi = dpi
    }
    if let text = values["--color"] ?? nil { patch.color = try color(text) }
    if let text = values["--enabled"] ?? nil {
      guard let enabled = Bool(text) else { throw usage("--enabled must be true or false.") }
      patch.enabled = enabled
    }
    guard patch.dpi != nil || patch.color != nil || patch.enabled != nil || patch.active else {
      throw usage("set-dpi needs a value to change.")
    }
    return patch
  }

  private static func options(_ arguments: [String], flags: Set<String>) throws -> [String: String?]
  {
    var result: [String: String?] = [:]
    var index = 0
    while index < arguments.count {
      let option = arguments[index]
      guard option.hasPrefix("--"), result[option] == nil else {
        throw usage("Option '\(option)' is invalid or repeated.")
      }
      if flags.contains(option) {
        result[option] = .some(nil)
        index += 1
        continue
      }
      guard index + 1 < arguments.count else { throw usage("Option '\(option)' needs a value.") }
      result[option] = .some(arguments[index + 1])
      index += 2
    }
    return result
  }

  private static func exact(_ values: [String: String?], _ allowed: Set<String>) throws {
    guard let unknown = values.keys.first(where: { !allowed.contains($0) }) else { return }
    throw usage("Unknown option '\(unknown)'.")
  }

  private static func color(_ value: String) throws -> RGBColor {
    let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
    guard hex.count == 6, let number = UInt32(hex, radix: 16) else {
      throw usage("Color must be six hexadecimal digits.")
    }
    return RGBColor(
      red: UInt8(number >> 16), green: UInt8((number >> 8) & 0xff), blue: UInt8(number & 0xff))
  }

  private static func level(_ value: String, _ option: String, _ range: ClosedRange<UInt8>) throws
    -> UInt8
  {
    guard let number = UInt8(value), range.contains(number) else {
      throw usage("\(option) must be in the range \(range.lowerBound) through \(range.upperBound).")
    }
    return number
  }

  private static func none(_ arguments: [String], _ command: String) throws {
    guard arguments.isEmpty else {
      throw usage("The \(command) command does not accept arguments.")
    }
  }
  private static func usage(_ message: String) -> CLIError { .usage(message) }
}

@main
enum ModelOEternalConfigurationCommand {
  static let version = "0.2.0"

  static func main() {
    do { try run(Arguments.parse(Array(CommandLine.arguments.dropFirst()))) } catch {
      writeJSON(
        [
          "ok": false,
          "error": [
            "code": errorCode(error), "message": error.localizedDescription,
            "remediation": remediation(error),
          ],
        ], to: .standardError)
      exit(error is CLIError ? 2 : 3)
    }
  }

  private static func run(_ command: Command) throws {
    let device = ModelOEternalDevice()
    switch command {
    case .help: print(help)
    case .version: print(version)
    case .capabilities:
      writeJSON([
        "ok": true,
        "result": [
          "name": "Model O Eternal Configuration", "version": version, "output": "JSON",
          "commands": [
            "capabilities", "effects", "status", "set", "sensitivity", "set-dpi",
            "set-polling-rate", "buttons", "button-actions", "set-button", "advanced",
            "set-debounce", "set-lift-off-distance", "device",
          ], "dpi": ["minimum": 50, "maximum": 12000, "step": 50, "stages": 8],
          "pollingRates": [125, 250, 500, 1000],
          "debounceMilliseconds": [4, 6, 8, 10, 12, 14, 16],
          "factoryDebounceMayReadAsZero": true,
          "liftOffDistanceMillimeters": [2, 3], "writesUseReadBackVerification": true,
          "writesSupportDryRun": true,
        ],
      ])
    case .effects: writeJSON(["ok": true, "result": LightingEffect.allCases.map(effectJSON)])
    case .status:
      writeJSON([
        "ok": true,
        "result": [
          "connected": true,
          "device": ["vendorId": "3794", "productId": "a000"],
          "settings": lightingJSON(try device.readSettings()),
        ],
      ])
    case .sensitivity:
      writeJSON(["ok": true, "result": sensitivityJSON(try device.readSensitivity())])
    case .buttons: writeJSON(["ok": true, "result": buttonsJSON(try device.readButtons())])
    case .buttonActions:
      writeJSON([
        "ok": true,
        "result": ButtonAction.supported.map {
          ["id": $0.id, "name": $0.name, "category": $0.category]
        },
      ])
    case .advanced: writeJSON(["ok": true, "result": advancedJSON(try device.readAdvanced())])
    case .device:
      writeJSON([
        "ok": true,
        "result": [
          "connected": true, "vendorId": "3794", "productId": "a000",
          "firmwareVersion": try device.readFirmwareVersion(),
          "factoryReset":
            "Hold the left, right, and scroll buttons for 5 seconds. The LEDs flash green.",
        ],
      ])
    case .set(let patch): try setLighting(patch, device)
    case .setDPI(let patch):
      let before = try device.readSensitivity()
      var requested = before
      let index = patch.stage - 1
      if let value = patch.dpi { requested.stages[index].dpi = value }
      if let value = patch.color { requested.stages[index].color = value }
      if let value = patch.enabled { requested.stages[index].isEnabled = value }
      if patch.active { requested.activeStage = patch.stage }
      try ModelOEternalConfiguration.validate(requested)
      try finish(before, requested, patch.dryRun, device.apply, sensitivityJSON)
    case .setPolling(let rate, let dryRun):
      let before = try device.readSensitivity()
      var requested = before
      requested.pollingRate = rate
      try finish(before, requested, dryRun, device.apply, sensitivityJSON)
    case .setButton(let button, let action, let dryRun):
      let before = try device.readButtons()
      var requested = before
      requested.actions[button.rawValue] = action
      try finish(before, requested, dryRun, device.apply, buttonsJSON)
    case .setDebounce(let value, let dryRun):
      let before = try device.readAdvanced()
      if before.debounceMilliseconds != value && !dryRun {
        try device.applyDebounce(milliseconds: value)
      }
      let final =
        dryRun
        ? AdvancedSettings(debounceMilliseconds: value, liftOffDistance: before.liftOffDistance)
        : try device.readAdvanced()
      writeChange(
        before: advancedJSON(before), final: advancedJSON(final),
        changed: before.debounceMilliseconds != value, dryRun: dryRun)
    case .setLiftOffDistance(let value, let dryRun):
      let before = try device.readAdvanced()
      if before.liftOffDistance != value && !dryRun { try device.apply(value) }
      let final =
        dryRun
        ? AdvancedSettings(
          debounceMilliseconds: before.debounceMilliseconds, liftOffDistance: value)
        : try device.readAdvanced()
      writeChange(
        before: advancedJSON(before), final: advancedJSON(final),
        changed: before.liftOffDistance != value, dryRun: dryRun)
    }
  }

  private static func setLighting(_ patch: LightingPatch, _ device: ModelOEternalDevice) throws {
    let before = try device.readSettings()
    let effect = patch.effect ?? before.effect
    if patch.color != nil, !effect.usesColor {
      throw CLIError.usage("Effect '\(effect.identifier)' does not use --color.")
    }
    if patch.brightness != nil, !effect.usesBrightness {
      throw CLIError.usage("Effect '\(effect.identifier)' does not use --brightness.")
    }
    if patch.speed != nil, !effect.usesSpeed {
      throw CLIError.usage("Effect '\(effect.identifier)' does not use --speed.")
    }
    let requested = LightingSettings(
      effect: effect, color: patch.color ?? before.color,
      brightness: patch.brightness ?? before.brightness, speed: patch.speed ?? before.speed)
    let changed = !before.hasSameEffectiveValues(as: requested)
    if changed && !patch.dryRun { try device.apply(requested) }
    writeChange(
      before: lightingJSON(before),
      final: lightingJSON(patch.dryRun ? requested : try device.readSettings()), changed: changed,
      dryRun: patch.dryRun)
  }

  private static func finish<T: Equatable>(
    _ before: T, _ requested: T, _ dryRun: Bool, _ apply: (T) throws -> Void, _ encode: (T) -> Any
  ) throws {
    let changed = before != requested
    if changed && !dryRun { try apply(requested) }
    writeChange(before: encode(before), final: encode(requested), changed: changed, dryRun: dryRun)
  }

  private static func writeChange(before: Any, final: Any, changed: Bool, dryRun: Bool) {
    writeJSON([
      "ok": true,
      "result": ["changed": changed, "dryRun": dryRun, "before": before, "settings": final],
    ])
  }

  private static func effectJSON(_ value: LightingEffect) -> [String: Any] {
    [
      "id": value.identifier, "name": value.name, "usesColor": value.usesColor,
      "usesBrightness": value.usesBrightness, "usesSpeed": value.usesSpeed,
    ]
  }
  private static func colorJSON(_ value: RGBColor) -> String {
    String(format: "#%02x%02x%02x", value.red, value.green, value.blue)
  }
  private static func lightingJSON(_ value: LightingSettings) -> [String: Any] {
    [
      "effect": value.effect.identifier, "color": colorJSON(value.color),
      "brightness": value.brightness, "speed": value.speed,
    ]
  }
  private static func sensitivityJSON(_ value: SensitivitySettings) -> [String: Any] {
    [
      "activeStage": value.activeStage, "pollingRateHz": value.pollingRate.hertz,
      "stages": value.stages.map {
        ["stage": $0.id, "dpi": $0.dpi, "color": colorJSON($0.color), "enabled": $0.isEnabled]
      },
    ]
  }
  private static func buttonsJSON(_ value: ButtonSettings) -> [[String: Any]] {
    zip(ButtonControl.allCases, value.actions).map {
      ["button": $0.0.identifier, "action": $0.1.id]
    }
  }
  private static func advancedJSON(_ value: AdvancedSettings) -> [String: Any] {
    [
      "debounceMilliseconds": value.debounceMilliseconds,
      "liftOffDistanceMillimeters": value.liftOffDistance.millimeters,
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
  private static func errorCode(_ error: Error) -> String {
    if error is CLIError { return "invalid_arguments" }
    if case ModelOEternalDeviceError.notConnected = error { return "device_not_connected" }
    if case ModelOEternalDeviceError.inputMonitoringRequired = error {
      return "input_monitoring_required"
    }
    if case ModelOEternalDeviceError.verificationFailed = error { return "verification_failed" }
    return "device_io_failed"
  }
  private static func remediation(_ error: Error) -> String {
    switch errorCode(error) {
    case "invalid_arguments": "Run 'model-o-eternal-config help' and correct the request."
    case "device_not_connected": "Connect a wired Model O Eternal and try again."
    case "input_monitoring_required":
      "Allow the terminal or agent host in System Settings > Privacy & Security > Input Monitoring."
    default: "Reconnect the mouse and try once more."
    }
  }

  private static let help = """
    Configure a wired Glorious Model O Eternal. All data commands return JSON.

    Read: capabilities | effects | status | sensitivity | buttons | button-actions | advanced | device
    Write:
      set [--effect ID] [--color RRGGBB] [--brightness 1-4] [--speed 1-3] [--dry-run]
      set-dpi --stage 1-8 [--dpi 50-12000] [--color RRGGBB] [--enabled true|false] [--active] [--dry-run]
      set-polling-rate --hz 125|250|500|1000 [--dry-run]
      set-button --button ID --action ID [--dry-run]
      set-debounce --milliseconds 4|6|8|10|12|14|16 [--dry-run]
      set-lift-off-distance --millimeters 2|3 [--dry-run]
    """
}
