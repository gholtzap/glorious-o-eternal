import Foundation

public enum ButtonControl: Int, CaseIterable, Identifiable, Sendable {
  case left, right, middle, back, forward, dpi

  public var id: Int { rawValue }

  public var identifier: String {
    switch self {
    case .left: "left"
    case .right: "right"
    case .middle: "middle"
    case .back: "back"
    case .forward: "forward"
    case .dpi: "dpi"
    }
  }

  public var name: String {
    switch self {
    case .left: "Left button"
    case .right: "Right button"
    case .middle: "Scroll click"
    case .back: "Back button"
    case .forward: "Forward button"
    case .dpi: "DPI button"
    }
  }

  public init?(identifier: String) {
    guard let value = Self.allCases.first(where: { $0.identifier == identifier }) else {
      return nil
    }
    self = value
  }
}

public struct ButtonAction: Equatable, Hashable, Identifiable, Sendable {
  public let id: String
  public let name: String
  public let category: String
  let bytes: [UInt8]

  private init(_ id: String, _ name: String, _ category: String, _ bytes: [UInt8]) {
    self.id = id
    self.name = name
    self.category = category
    self.bytes = bytes
  }

  public static let supported: [Self] = {
    var actions = [
      Self("disabled", "Disabled", "General", [0x50, 1, 0, 0]),
      Self("left-click", "Left click", "Clicks", [0x11, 1, 0, 0]),
      Self("right-click", "Right click", "Clicks", [0x11, 2, 0, 0]),
      Self("middle-click", "Middle click", "Clicks", [0x11, 4, 0, 0]),
      Self("back", "Back", "Clicks", [0x11, 8, 0, 0]),
      Self("forward", "Forward", "Clicks", [0x11, 16, 0, 0]),
      Self("scroll-up", "Scroll up", "Clicks", [0x12, 1, 0, 0]),
      Self("scroll-down", "Scroll down", "Clicks", [0x12, 0xff, 0, 0]),
      Self("media-next", "Next track", "Media", [0x22, 1, 0, 0]),
      Self("media-previous", "Previous track", "Media", [0x22, 2, 0, 0]),
      Self("media-stop", "Stop", "Media", [0x22, 4, 0, 0]),
      Self("media-play-pause", "Play or pause", "Media", [0x22, 8, 0, 0]),
      Self("media-mute", "Mute", "Media", [0x22, 0x10, 0, 0]),
      Self("media-volume-up", "Volume up", "Media", [0x22, 0x40, 0, 0]),
      Self("media-volume-down", "Volume down", "Media", [0x22, 0x80, 0, 0]),
      Self("dpi-cycle", "Cycle DPI", "DPI", [0x41, 0, 0, 0]),
      Self("dpi-up", "DPI up", "DPI", [0x41, 1, 0, 0]),
      Self("dpi-down", "DPI down", "DPI", [0x41, 2, 0, 0]),
    ]
    let keys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").enumerated().map {
      Self(
        "key-\($0.element.lowercased())", "Key \($0.element)", "Keyboard",
        [0x21, 0, UInt8(0x04 + $0.offset), 0])
    }
    let digits = Array("1234567890").enumerated().map {
      Self(
        "key-\($0.element)", "Key \($0.element)", "Keyboard", [0x21, 0, UInt8(0x1e + $0.offset), 0])
    }
    actions +=
      keys + digits + [
        Self("key-return", "Return", "Keyboard", [0x21, 0, 0x28, 0]),
        Self("key-escape", "Escape", "Keyboard", [0x21, 0, 0x29, 0]),
        Self("key-delete", "Delete", "Keyboard", [0x21, 0, 0x2a, 0]),
        Self("key-tab", "Tab", "Keyboard", [0x21, 0, 0x2b, 0]),
        Self("key-space", "Space", "Keyboard", [0x21, 0, 0x2c, 0]),
        Self("key-right-arrow", "Right arrow", "Keyboard", [0x21, 0, 0x4f, 0]),
        Self("key-left-arrow", "Left arrow", "Keyboard", [0x21, 0, 0x50, 0]),
        Self("key-down-arrow", "Down arrow", "Keyboard", [0x21, 0, 0x51, 0]),
        Self("key-up-arrow", "Up arrow", "Keyboard", [0x21, 0, 0x52, 0]),
      ]
    return actions
  }()

  public init?(identifier: String) {
    guard let action = Self.supported.first(where: { $0.id == identifier }) else { return nil }
    self = action
  }

  fileprivate init?(bytes: ArraySlice<UInt8>) {
    guard let action = Self.supported.first(where: { $0.bytes == Array(bytes) }) else { return nil }
    self = action
  }
}

public struct ButtonSettings: Equatable, Sendable {
  public var actions: [ButtonAction]
  public init(actions: [ButtonAction]) { self.actions = actions }
}

public enum ButtonConfigurationError: LocalizedError, Equatable {
  case invalidReportSize(Int)
  case invalidLength(Int)
  case invalidHeader
  case invalidButtonCount(Int)
  case unsupportedAction(button: Int)

  public var errorDescription: String? {
    switch self {
    case .invalidReportSize(let size): "The mouse returned an invalid button report size: \(size)."
    case .invalidLength(let length):
      "The mouse returned an invalid button report length: \(length)."
    case .invalidHeader: "The mouse returned an invalid button report header."
    case .invalidButtonCount(let count): "The request has \(count) button actions instead of 6."
    case .unsupportedAction(let button):
      "Button \(button) uses an action that this app cannot change safely."
    }
  }
}

public struct ModelOEternalButtonConfiguration: Equatable, Sendable {
  public static let reportSize = 520
  public static let configurationLength = 88
  private let bytes: [UInt8]
  public let settings: ButtonSettings

  public init(bytes: [UInt8], configurationLength: Int) throws {
    guard bytes.count == Self.reportSize else {
      throw ButtonConfigurationError.invalidReportSize(bytes.count)
    }
    guard configurationLength == Self.configurationLength else {
      throw ButtonConfigurationError.invalidLength(configurationLength)
    }
    guard bytes[0] == 4, bytes[1] == 0x12 else { throw ButtonConfigurationError.invalidHeader }
    var actions: [ButtonAction] = []
    for index in 0..<6 {
      let offset = 8 + index * 4
      guard let action = ButtonAction(bytes: bytes[offset..<(offset + 4)]) else {
        throw ButtonConfigurationError.unsupportedAction(button: index + 1)
      }
      actions.append(action)
    }
    self.bytes = bytes
    settings = ButtonSettings(actions: actions)
  }

  public func applying(_ settings: ButtonSettings) throws -> [UInt8] {
    guard settings.actions.count == 6 else {
      throw ButtonConfigurationError.invalidButtonCount(settings.actions.count)
    }
    var result = bytes
    result[0] = 4
    result[1] = 0x12
    result[3] = 80
    for (index, action) in settings.actions.enumerated() {
      result.replaceSubrange((8 + index * 4)..<(12 + index * 4), with: action.bytes)
    }
    return result
  }
}
