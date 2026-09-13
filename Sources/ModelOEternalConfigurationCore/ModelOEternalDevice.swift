import Foundation
import IOKit.hid

public enum ModelOEternalDeviceError: LocalizedError {
  case notConnected
  case cannotOpenManager(IOReturn)
  case cannotOpenDevice(IOReturn)
  case inputMonitoringRequired
  case commandFailed(IOReturn)
  case readFailed(IOReturn)
  case writeFailed(IOReturn)
  case invalidReadLength(Int)
  case invalidFirmwareVersion
  case verificationFailed(String)

  public var errorDescription: String? {
    switch self {
    case .notConnected:
      "Connect a Model O Eternal, then try again."
    case .cannotOpenManager(let code):
      "macOS could not open the HID manager (\(Self.hex(code)))."
    case .cannotOpenDevice(let code):
      "macOS could not open the mouse control interface (\(Self.hex(code)))."
    case .inputMonitoringRequired:
      "Allow Model O Eternal Configuration in Input Monitoring, then reopen the app."
    case .commandFailed(let code):
      "The mouse rejected the configuration request (\(Self.hex(code)))."
    case .readFailed(let code):
      "The mouse configuration could not be read (\(Self.hex(code)))."
    case .writeFailed(let code):
      "The mouse configuration could not be written (\(Self.hex(code)))."
    case .invalidReadLength(let length):
      "The mouse returned \(length) configuration bytes."
    case .invalidFirmwareVersion:
      "The mouse returned an invalid firmware version."
    case .verificationFailed(let setting):
      "The mouse did not save the requested \(setting) settings."
    }
  }

  private static func hex(_ code: IOReturn) -> String {
    String(format: "0x%08x", code)
  }
}

public struct ModelOEternalState: Equatable, Sendable {
  public var lighting: LightingSettings
  public var sensitivity: SensitivitySettings
  public var buttons: ButtonSettings
  public var advanced: AdvancedSettings
  public var firmwareVersion: String
}

public struct ModelOEternalDevice {
  public static let vendorID = 0x3794
  public static let productID = 0xa000

  public init() {}

  public func readSettings() throws -> LightingSettings {
    try readConfigurationSnapshot().settings
  }

  public func readState() throws -> ModelOEternalState {
    try withControlDevice { device in
      let configuration = try readConfiguration(from: device)
      let buttonRaw = try readRawSnapshot(
        command: 0x12, expectedLength: ModelOEternalButtonConfiguration.configurationLength,
        from: device)
      let buttons = try ModelOEternalButtonConfiguration(
        bytes: buttonRaw.bytes, configurationLength: buttonRaw.length)
      return ModelOEternalState(
        lighting: configuration.settings,
        sensitivity: configuration.sensitivitySettings,
        buttons: buttons.settings,
        advanced: AdvancedSettings(
          debounceMilliseconds: try readDebounce(from: device),
          liftOffDistance: configuration.liftOffDistance),
        firmwareVersion: try readFirmwareVersion(from: device)
      )
    }
  }

  public func readSensitivity() throws -> SensitivitySettings {
    try readConfigurationSnapshot().sensitivitySettings
  }

  public func readButtons() throws -> ButtonSettings {
    let raw = try readRawButtonSnapshot()
    return try ModelOEternalButtonConfiguration(
      bytes: raw.bytes, configurationLength: raw.length
    ).settings
  }

  public func readAdvanced() throws -> AdvancedSettings {
    try withControlDevice { device in
      let configuration = try readConfiguration(from: device)
      return AdvancedSettings(
        debounceMilliseconds: try readDebounce(from: device),
        liftOffDistance: configuration.liftOffDistance)
    }
  }

  public func readFirmwareVersion() throws -> String {
    try withControlDevice { try readFirmwareVersion(from: $0) }
  }

  func readConfigurationSnapshot() throws -> ModelOEternalConfiguration {
    try withControlDevice { device in
      try readConfiguration(from: device)
    }
  }

  func readRawConfigurationSnapshot() throws -> (bytes: [UInt8], length: Int) {
    try withControlDevice { device in
      try readRawSnapshot(
        command: 0x11, expectedLength: ModelOEternalConfiguration.configurationLength, from: device)
    }
  }

  func readRawButtonSnapshot() throws -> (bytes: [UInt8], length: Int) {
    try withControlDevice { device in
      try readRawSnapshot(command: 0x12, expectedLength: 88, from: device)
    }
  }

  func readRawCommand(_ command: UInt8) throws -> [UInt8] {
    try withControlDevice { device in
      try query(command: command, from: device)
    }
  }

  public func apply(_ settings: LightingSettings) throws {
    try withControlDevice { device in
      let current = try readConfiguration(from: device)
      try writeAndVerify(
        try current.applying(settings), reportID: 4, setting: "lighting", to: device
      ) { try readConfiguration(from: device).settings.hasSameEffectiveValues(as: settings) }
    }
  }

  public func apply(_ settings: SensitivitySettings) throws {
    try withControlDevice { device in
      let current = try readConfiguration(from: device)
      try writeAndVerify(
        try current.applying(settings), reportID: 4, setting: "sensitivity", to: device
      ) { current.verifies(settings, in: try readConfiguration(from: device)) }
    }
  }

  public func apply(_ settings: ButtonSettings) throws {
    try withControlDevice { device in
      let raw = try readRawSnapshot(
        command: 0x12, expectedLength: ModelOEternalButtonConfiguration.configurationLength,
        from: device)
      let current = try ModelOEternalButtonConfiguration(
        bytes: raw.bytes, configurationLength: raw.length)
      try writeAndVerify(
        try current.applying(settings), reportID: 4, setting: "button", to: device
      ) {
        let readBack = try readRawSnapshot(
          command: 0x12, expectedLength: ModelOEternalButtonConfiguration.configurationLength,
          from: device)
        return try ModelOEternalButtonConfiguration(
          bytes: readBack.bytes, configurationLength: readBack.length
        ).settings == settings
      }
    }
  }

  public func apply(_ liftOffDistance: LiftOffDistance) throws {
    try withControlDevice { device in
      let current = try readConfiguration(from: device)
      try writeAndVerify(
        current.applying(liftOffDistance), reportID: 4, setting: "lift-off distance", to: device
      ) { current.verifies(liftOffDistance, in: try readConfiguration(from: device)) }
    }
  }

  public func applyDebounce(milliseconds: Int) throws {
    guard stride(from: 4, through: 16, by: 2).contains(milliseconds) else {
      throw ConfigurationError.invalidDebounce(milliseconds)
    }
    try withControlDevice { device in
      let report: [UInt8] = [5, 0x1a, UInt8(milliseconds / 2), 0, 0, 0]
      try writeAndVerify(report, reportID: 5, setting: "debounce", to: device) {
        try readDebounce(from: device) == milliseconds
      }
    }
  }

  public func isConnected() -> Bool {
    (try? withControlDevice { _ in true }) ?? false
  }

  private func readConfiguration(from device: IOHIDDevice) throws -> ModelOEternalConfiguration {
    let raw = try readRawConfiguration(from: device)
    return try ModelOEternalConfiguration(bytes: raw.bytes, configurationLength: raw.length)
  }

  private func readRawConfiguration(from device: IOHIDDevice) throws -> (
    bytes: [UInt8], length: Int
  ) {
    try readRawSnapshot(
      command: 0x11, expectedLength: ModelOEternalConfiguration.configurationLength, from: device)
  }

  private func readRawSnapshot(command: UInt8, expectedLength: Int, from device: IOHIDDevice) throws
    -> (bytes: [UInt8], length: Int)
  {
    let request: [UInt8] = [5, command, 0, 0, 0, 0]
    let commandResult = request.withUnsafeBytes { buffer in
      IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeFeature,
        5,
        buffer.bindMemory(to: UInt8.self).baseAddress!,
        request.count
      )
    }
    guard commandResult == kIOReturnSuccess else {
      throw ModelOEternalDeviceError.commandFailed(commandResult)
    }

    var report = [UInt8](repeating: 0, count: ModelOEternalConfiguration.reportSize)
    report[0] = 4
    var reportLength = report.count
    let readResult = report.withUnsafeMutableBytes { buffer in
      IOHIDDeviceGetReport(
        device,
        kIOHIDReportTypeFeature,
        4,
        buffer.bindMemory(to: UInt8.self).baseAddress!,
        &reportLength
      )
    }
    guard readResult == kIOReturnSuccess else {
      throw ModelOEternalDeviceError.readFailed(readResult)
    }
    guard reportLength == expectedLength else {
      throw ModelOEternalDeviceError.invalidReadLength(reportLength)
    }

    return (report, reportLength)
  }

  private func query(command: UInt8, from device: IOHIDDevice) throws -> [UInt8] {
    var report: [UInt8] = [5, command, 0, 0, 0, 0]
    let commandResult = report.withUnsafeBytes { buffer in
      IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeFeature,
        5,
        buffer.bindMemory(to: UInt8.self).baseAddress!,
        report.count
      )
    }
    guard commandResult == kIOReturnSuccess else {
      throw ModelOEternalDeviceError.commandFailed(commandResult)
    }

    var reportLength = report.count
    let readResult = report.withUnsafeMutableBytes { buffer in
      IOHIDDeviceGetReport(
        device,
        kIOHIDReportTypeFeature,
        5,
        buffer.bindMemory(to: UInt8.self).baseAddress!,
        &reportLength
      )
    }
    guard readResult == kIOReturnSuccess else {
      throw ModelOEternalDeviceError.readFailed(readResult)
    }
    guard reportLength == report.count, report[0] == 5, report[1] == command else {
      throw ModelOEternalDeviceError.invalidReadLength(reportLength)
    }
    return report
  }

  private func readFirmwareVersion(from device: IOHIDDevice) throws -> String {
    let report = try query(command: 0x01, from: device)
    guard let version = String(bytes: report[2...5], encoding: .ascii),
      version.allSatisfy(\.isNumber)
    else { throw ModelOEternalDeviceError.invalidFirmwareVersion }
    return version
  }

  private func readDebounce(from device: IOHIDDevice) throws -> Int {
    Int(try query(command: 0x1a, from: device)[2]) * 2
  }

  private func writeAndVerify(
    _ report: [UInt8], reportID: CFIndex, setting: String, to device: IOHIDDevice,
    verify: () throws -> Bool
  ) throws {
    let result = report.withUnsafeBytes { buffer in
      IOHIDDeviceSetReport(
        device, kIOHIDReportTypeFeature, reportID,
        buffer.bindMemory(to: UInt8.self).baseAddress!, report.count)
    }
    guard result == kIOReturnSuccess else { throw ModelOEternalDeviceError.writeFailed(result) }
    for _ in 0..<5 {
      Thread.sleep(forTimeInterval: 0.1)
      if try verify() { return }
    }
    throw ModelOEternalDeviceError.verificationFailed(setting)
  }

  private func withControlDevice<T>(_ operation: (IOHIDDevice) throws -> T) throws -> T {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching: [String: Any] = [
      kIOHIDVendorIDKey as String: Self.vendorID,
      kIOHIDProductIDKey as String: Self.productID,
      kIOHIDPrimaryUsagePageKey as String: kHIDPage_GenericDesktop,
      kIOHIDPrimaryUsageKey as String: kHIDUsage_GD_Keyboard,
    ]
    IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

    let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    if managerResult == kIOReturnNotPermitted {
      throw ModelOEternalDeviceError.inputMonitoringRequired
    }
    guard managerResult == kIOReturnSuccess else {
      throw ModelOEternalDeviceError.cannotOpenManager(managerResult)
    }
    defer { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }

    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
      let device = devices.first
    else {
      throw ModelOEternalDeviceError.notConnected
    }

    let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
    guard deviceResult == kIOReturnSuccess else {
      throw ModelOEternalDeviceError.cannotOpenDevice(deviceResult)
    }
    defer { IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone)) }

    return try operation(device)
  }
}
