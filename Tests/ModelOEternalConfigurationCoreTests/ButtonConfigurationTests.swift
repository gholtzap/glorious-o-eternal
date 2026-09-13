import Testing

@testable import ModelOEternalConfigurationCore

struct ButtonConfigurationTests {
  @Test
  func readsAndWritesSixButtons() throws {
    var bytes = [UInt8](repeating: 0, count: 520)
    bytes[0] = 4
    bytes[1] = 0x12
    let ids = ["left-click", "right-click", "middle-click", "back", "forward", "dpi-cycle"]
    for (index, id) in ids.enumerated() {
      let action = ButtonAction(identifier: id)!
      bytes.replaceSubrange((8 + index * 4)..<(12 + index * 4), with: action.bytes)
    }
    let report = try ModelOEternalButtonConfiguration(bytes: bytes, configurationLength: 88)
    #expect(report.settings.actions.map(\.id) == ids)

    var settings = report.settings
    settings.actions[5] = ButtonAction(identifier: "dpi-up")!
    let changed = try report.applying(settings)
    let readBack = try ModelOEternalButtonConfiguration(bytes: changed, configurationLength: 88)
    #expect(readBack.settings == settings)
    #expect(changed[3] == 80)
  }

  @Test
  func rejectsUnknownButtonData() {
    var bytes = [UInt8](repeating: 0, count: 520)
    bytes[0] = 4
    bytes[1] = 0x12
    #expect(throws: ButtonConfigurationError.unsupportedAction(button: 1)) {
      try ModelOEternalButtonConfiguration(bytes: bytes, configurationLength: 88)
    }
  }
}
