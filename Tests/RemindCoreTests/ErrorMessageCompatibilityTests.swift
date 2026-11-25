import Testing

@testable import RemindCore

@MainActor
struct ErrorMessageCompatibilityTests {
  @Test("Every error message is pinned word for word")
  func messages() {
    let accessDenied =
      "Reminders access denied. "
      + "Run `remindctl authorize` to trigger the prompt, then allow Terminal (or remindctl) "
      + "in System Settings > Privacy & Security > Reminders. "
      + "If no prompt appears, run `osascript -e 'tell application \"Reminders\" to get name of reminders'` "
      + "once from the same terminal app. "
      + "If running over SSH, grant access on the Mac that runs the command."
    let writeOnly =
      "Reminders access is write-only. "
      + "Switch to Full Access in System Settings > Privacy & Security > Reminders."

    #expect(RemindCoreError.accessDenied.localizedDescription == accessDenied)
    #expect(RemindCoreError.writeOnlyAccess.localizedDescription == writeOnly)
    #expect(RemindCoreError.listNotFound("Work").localizedDescription == "List not found: \"Work\".")
    #expect(
      RemindCoreError.ambiguousList("Wo", matches: ["Work", "Wonder"]).localizedDescription
        == "List \"Wo\" matches multiple lists: Work, Wonder.")
    #expect(RemindCoreError.reminderNotFound("4A83").localizedDescription == "Reminder not found: \"4A83\".")
    #expect(
      RemindCoreError.ambiguousIdentifier("4A", matches: ["4A83", "4AF0"]).localizedDescription
        == "Identifier \"4A\" matches multiple reminders: 4A83, 4AF0.")
    #expect(RemindCoreError.invalidIdentifier("zz").localizedDescription == "Invalid identifier: \"zz\".")
    #expect(RemindCoreError.invalidDate("someday").localizedDescription == "Invalid date: \"someday\".")
    #expect(RemindCoreError.unsupported("Not supported").localizedDescription == "Not supported")
    #expect(RemindCoreError.operationFailed("It failed").localizedDescription == "It failed")
  }
}
