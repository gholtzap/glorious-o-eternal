import ModelOEternalConfigurationCore
import Testing

@testable import ModelOEternalConfigurationCLI

struct ArgumentsTests {
  @Test
  func parsesACompleteSetRequest() throws {
    #expect(
      try Arguments.parse([
        "set", "--effect", "single-color", "--color", "#7c3aed", "--brightness", "4",
        "--dry-run",
      ])
        == .set(
          SettingsPatch(
            effect: .singleColor,
            color: .init(red: 124, green: 58, blue: 237),
            brightness: 4,
            dryRun: true
          )))
  }

  @Test
  func rejectsInvalidAndAmbiguousInput() {
    #expect(throws: CLIError.self) { try Arguments.parse(["set"]) }
    #expect(throws: CLIError.self) { try Arguments.parse(["set", "--brightness", "0"]) }
    #expect(throws: CLIError.self) {
      try Arguments.parse(["set", "--color", "12345g"])
    }
    #expect(throws: CLIError.self) {
      try Arguments.parse(["set", "--effect", "wave", "--effect", "tail"])
    }
  }

  @Test
  func parsesAgentConfigurationCommands() throws {
    #expect(
      try Arguments.parse(["set-polling-rate", "--hz", "500", "--dry-run"])
        == .setPolling(.hz500, dryRun: true))
    #expect(
      try Arguments.parse(["set-button", "--button", "dpi", "--action", "dpi-up"])
        == .setButton(.dpi, ButtonAction(identifier: "dpi-up")!, dryRun: false))
    #expect(
      try Arguments.parse(["set-dpi", "--stage", "3", "--dpi", "1650", "--active"])
        == .setDPI(.init(stage: 3, dpi: 1650, active: true)))
    #expect(
      try Arguments.parse(["set-debounce", "--milliseconds", "4"]) == .setDebounce(4, dryRun: false)
    )
    #expect(
      try Arguments.parse(["set-lift-off-distance", "--millimeters", "2"])
        == .setLiftOffDistance(.twoMillimeters, dryRun: false))
  }

  @Test
  func rejectsUnsafeAgentValues() {
    #expect(throws: CLIError.self) {
      try Arguments.parse(["set-dpi", "--stage", "1", "--dpi", "425"])
    }
    #expect(throws: CLIError.self) { try Arguments.parse(["set-polling-rate", "--hz", "2000"]) }
    #expect(throws: CLIError.self) {
      try Arguments.parse(["set-button", "--button", "unknown", "--action", "left-click"])
    }
    #expect(throws: CLIError.self) { try Arguments.parse(["set-debounce", "--milliseconds", "2"]) }
  }
}
