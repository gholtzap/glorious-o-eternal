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
  case verificationFailed

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
    case .verificationFailed:
      "The mouse did not save the requested lighting settings."
    }
  }

  private static func hex(_ code: IOReturn) -> String {
    String(format: "0x%08x", code)
  }
}

public struct ModelOEternalDevice {
  public static let vendorID = 0x3794
  public static let productID = 0xa000

  public init() {}

  public func readSettings() throws -> LightingSettings {
    try readConfigurationSnapshot().settings
  }

  func readConfigurationSnapshot() throws -> ModelOEternalConfiguration {
    try withControlDevice { device in
      try readConfiguration(from: device)
    }
  }

  func readRawConfigurationSnapshot() throws -> (bytes: [UInt8], length: Int) {
    try withControlDevice { device in
      try readRawConfiguration(from: device)
    }
  }

  public func apply(_ settings: LightingSettings) throws {
    try withControlDevice { device in
      let current = try readConfiguration(from: device)
      let report = try current.applying(settings)
      let result = report.withUnsafeBytes { buffer in
        IOHIDDeviceSetReport(
          device,
          kIOHIDReportTypeFeature,
          4,
          buffer.bindMemory(to: UInt8.self).baseAddress!,
          report.count
        )
      }
      guard result == kIOReturnSuccess else {
        throw ModelOEternalDeviceError.writeFailed(result)
      }

      for _ in 0..<5 {
        Thread.sleep(forTimeInterval: 0.1)
        let readBack = try readConfiguration(from: device)
        if current.verifies(settings, in: readBack) {
          return
        }
      }
      throw ModelOEternalDeviceError.verificationFailed
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
    let command: [UInt8] = [5, 0x11, 0, 0, 0, 0]
    let commandResult = command.withUnsafeBytes { buffer in
      IOHIDDeviceSetReport(
        device,
        kIOHIDReportTypeFeature,
        5,
        buffer.bindMemory(to: UInt8.self).baseAddress!,
        command.count
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
    guard reportLength == ModelOEternalConfiguration.configurationLength else {
      throw ModelOEternalDeviceError.invalidReadLength(reportLength)
    }

    return (report, reportLength)
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
