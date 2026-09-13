import Testing

@testable import EternalLightsCLI

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
}
