import Foundation
import RemindCore
import RemindPrivate
import Testing

@testable import remindctl

struct RemindPrivateWriteBridgeTests {
  static let standIns = [
    "REMObjectID": "RPStandInObjectID",
    "REMStore": "RPStandInStore",
    "REMReminder": "RPStandInReminder",
    "REMReminderStorage": "RPStandInReminderStorage",
    "REMSaveRequest": "RPStandInSaveRequest",
    "REMReminderChangeItem": "RPStandInChangeItem",
    "REMReminderFlaggedContextChangeItem": "RPStandInFlaggedContext",
    "REMReminderUrgentAlarmContextChangeItem": "RPStandInUrgentContext",
    "REMReminderDueDateDeltaAlertContextChangeItem": "RPStandInDueDateDeltaAlertContext",
    "REMDueDateDeltaInterval": "RPStandInDueDateDeltaInterval",
  ]

  static func result(
    _ id: String,
    flagged: Bool?,
    urgent: Bool? = nil,
    early: EarlyReminderChange? = nil,
    replacing overrides: [String: String] = [:],
    timeout: TimeInterval = 10
  ) -> RPWriteResult {
    let classes = standIns.merging(overrides) { $1 }
    let change = ReminderKitFieldsWriter.bridged(
      PrivateFieldsChange(flagged: flagged, urgent: urgent, earlyReminder: early)
    )
    return RPWriteWithClassesForTesting(classes, id, change, timeout)
  }

  static func write(
    _ id: String,
    flagged: Bool?,
    urgent: Bool? = nil,
    early: EarlyReminderChange? = nil,
    replacing overrides: [String: String] = [:]
  ) -> String? {
    let result = result(id, flagged: flagged, urgent: urgent, early: early, replacing: overrides)
    #expect(!result.outcomeUnknown)
    return result.failureReason
  }

  @Test("Flag and unflag fetch by the ReminderKit URL, set the flag and save once", arguments: [true, false])
  func writesFlag(flagged: Bool) {
    let id = UUID().uuidString

    #expect(Self.write(id, flagged: flagged) == nil)
    #expect(
      writeLog.entries(for: id) == [
        "fetch x-apple-reminderkit://REMCDReminder/\(id)", "setFlagged \(flagged ? 1 : 0)", "save",
      ]
    )
  }

  @Test("Urgent on and off is set on the urgent alarm context and saved once", arguments: [true, false])
  func writesUrgent(urgent: Bool) {
    let id = UUID().uuidString

    #expect(Self.write(id, flagged: nil, urgent: urgent) == nil)
    #expect(
      writeLog.entries(for: id) == [
        "fetch x-apple-reminderkit://REMCDReminder/\(id)", "setUrgent \(urgent)", "save",
      ]
    )
  }

  @Test("The flag and Urgent are set on the same change and saved once")
  func writesFlagAndUrgentInOneSave() {
    let id = UUID().uuidString

    #expect(Self.write(id, flagged: true, urgent: false) == nil)
    #expect(
      writeLog.entries(for: id) == [
        "fetch x-apple-reminderkit://REMCDReminder/\(id)", "setFlagged 1", "setUrgent false", "save",
      ]
    )
  }

  @Test(
    "An Urgent write with a missing Urgent class, method or type is refused before anything is fetched or saved",
    arguments: [
      (["REMReminderUrgentAlarmContextChangeItem": "RPNoSuchClass"], "ReminderKit has no RPNoSuchClass"),
      (
        ["REMReminderChangeItem": "RPStandInChangeItemWithoutUrgent"],
        "RPStandInChangeItemWithoutUrgent has no urgentAlarmContext"
      ),
      (
        ["REMReminderUrgentAlarmContextChangeItem": "RPStandInUrgentContextTakingInteger"],
        "RPStandInUrgentContextTakingInteger setIsUrgentStateEnabledForCurrentUser: has an unexpected signature"
      ),
    ]
  )
  func refusesUrgentBeforeAnyCall(overrides: [String: String], reason: String) {
    let flagAndUrgent = UUID().uuidString
    let urgentOnly = UUID().uuidString

    #expect(Self.write(flagAndUrgent, flagged: true, urgent: true, replacing: overrides) == reason)
    #expect(Self.write(urgentOnly, flagged: nil, urgent: false, replacing: overrides) == reason)
    #expect(writeLog.entries(for: flagAndUrgent).isEmpty)
    #expect(writeLog.entries(for: urgentOnly).isEmpty)
  }

  @Test(
    "A flag-only write does not check Urgent's classes or methods",
    arguments: [
      ["REMReminderUrgentAlarmContextChangeItem": "RPNoSuchClass"],
      ["REMReminderUrgentAlarmContextChangeItem": "RPStandInUrgentContextTakingInteger"],
      ["REMReminderChangeItem": "RPStandInChangeItemFlagOnly"],
    ]
  )
  func flagOnlyIgnoresUrgentRequirements(overrides: [String: String]) {
    let id = UUID().uuidString

    #expect(Self.write(id, flagged: true, replacing: overrides) == nil)
    #expect(writeLog.entries(for: id).last == "save")
  }

  @Test(
    "An Urgent-only write does not check the flag's classes or methods",
    arguments: [
      ["REMReminderFlaggedContextChangeItem": "RPNoSuchClass"],
      ["REMReminderFlaggedContextChangeItem": "RPStandInFlaggedContextTakingBool"],
      ["REMReminderChangeItem": "RPStandInUrgentOnlyChangeItem"],
    ]
  )
  func urgentOnlyIgnoresFlagRequirements(overrides: [String: String]) {
    let id = UUID().uuidString

    #expect(Self.write(id, flagged: nil, urgent: true, replacing: overrides) == nil)
    #expect(writeLog.entries(for: id).last == "save")
  }

  @Test(
    "A missing class, method or type is refused before anything is fetched or saved",
    arguments: [
      (["REMStore": "RPNoSuchClass"], "ReminderKit has no RPNoSuchClass"),
      (
        ["REMSaveRequest": "RPStandInSaveRequestWithoutSave"],
        "RPStandInSaveRequestWithoutSave has no saveSynchronouslyWithError:"
      ),
      (
        ["REMReminderFlaggedContextChangeItem": "RPStandInFlaggedContextTakingBool"],
        "RPStandInFlaggedContextTakingBool setFlagged: has an unexpected signature"
      ),
    ]
  )
  func refusesBeforeAnyCall(overrides: [String: String], reason: String) {
    let id = UUID().uuidString

    #expect(Self.write(id, flagged: true, replacing: overrides) == reason)
    #expect(writeLog.entries(for: id).isEmpty)
  }

  @Test("An error set by the fetch fails the write even though the fetch returned a reminder")
  func fetchErrorFails() {
    #expect(Self.write(fetchFailsID, flagged: true) == "no such reminder")
    #expect(!writeLog.entries(for: fetchFailsID).contains("save"))
  }

  @Test("An error set by the save fails the write even though the save returned YES")
  func saveErrorFails() {
    #expect(Self.write(saveFailsID, flagged: true) == "the store is locked")
  }

  @Test("An id that is not a UUID is refused before any fetch")
  func nonUUIDRefused() {
    #expect(Self.write("not-a-uuid", flagged: true) == "not-a-uuid is not a ReminderKit id")
    #expect(writeLog.entries(for: "not-a-uuid").isEmpty)
  }

  @Test("A fetch with no reminder and no error, or a save that says NO, fails the write")
  func emptyAnswersFail() {
    #expect(
      Self.write(fetchFindsNothingID, flagged: true) == "ReminderKit found no reminder with id \(fetchFindsNothingID)"
    )
    #expect(Self.write(saveSaysNoID, flagged: true) == "REMSaveRequest did not save")
  }

  @Test("A save that times out or raises leaves the outcome unknown")
  func slowOrRaisingSaveIsUnknown() {
    let slow = Self.result(saveIsSlowID, flagged: true, timeout: 0.2)
    #expect(slow.outcomeUnknown)
    #expect(slow.failureReason == "ReminderKit did not answer within 0.2 seconds")

    let raised = Self.result(saveRaisesID, flagged: true)
    #expect(raised.outcomeUnknown)
    #expect(raised.failureReason == "ReminderKit raised NSInternalInconsistencyException: store went away")
  }

  @Test(
    "Every unit goes to ReminderKit as an interval that reads back as the Early Reminder asked for",
    arguments: [EarlyReminderUnit.minutes, .hours, .days, .weeks, .months]
  )
  func earlyRoundTrips(unit: EarlyReminderUnit) throws {
    let id = UUID().uuidString
    let early = EarlyReminder(count: 3, unit: unit)

    #expect(Self.write(id, flagged: nil, early: .set(early)) == nil)
    let entries = writeLog.entries(for: id)
    #expect(entries.count == 4)
    #expect(entries.dropFirst().first == "removeAllFetchedDueDateDeltaAlerts")
    #expect(entries.last == "save")
    let added = try #require(entries.first { $0.hasPrefix("addAlert ") })
    let numbers = added.split(separator: " ").compactMap { Int($0) }
    let json = #"{"dueDateDeltaAlerts":[{"dueDateDeltaUnit":\#(numbers[0]),"dueDateDeltaCount":\#(numbers[1])}]}"#
    #expect(numbers[1] == -3)
    #expect(try EarlyReminder.parse(Data(json.utf8)) == early)
  }

  @Test("Removing the Early Reminder only removes the fetched alerts, then saves")
  func earlyRemoval() {
    let id = UUID().uuidString

    #expect(Self.write(id, flagged: nil, early: .remove) == nil)
    #expect(
      writeLog.entries(for: id) == [
        "fetch x-apple-reminderkit://REMCDReminder/\(id)", "removeAllFetchedDueDateDeltaAlerts", "save",
      ]
    )
  }

  @Test("The flag, Urgent and the Early Reminder are set on the same change and saved once")
  func writesAllThreeInOneSave() {
    let id = UUID().uuidString

    #expect(Self.write(id, flagged: true, urgent: true, early: .set(EarlyReminder(count: 1, unit: .days))) == nil)
    #expect(
      writeLog.entries(for: id) == [
        "fetch x-apple-reminderkit://REMCDReminder/\(id)", "setFlagged 1", "setUrgent true",
        "removeAllFetchedDueDateDeltaAlerts", "addAlert 2 -1", "save",
      ]
    )
  }

  @Test("A nil alert from ReminderKit fails the Early Reminder write without saving")
  func nilAlertFails() {
    #expect(
      Self.write(addAlertFailsID, flagged: true, early: .set(EarlyReminder(count: 1, unit: .days)))
        == "REMReminderDueDateDeltaAlertContextChangeItem addDueDateDeltaAlertWithDueDateDelta: returned no alert"
    )
    #expect(!writeLog.entries(for: addAlertFailsID).contains("save"))
  }

  @Test(
    "An Early Reminder write with a missing class, method or type is refused before anything is fetched or saved",
    arguments: [
      (
        ["REMReminderChangeItem": "RPStandInChangeItemFlagOnly"],
        "RPStandInChangeItemFlagOnly has no dueDateDeltaAlertContext"
      ),
      (
        ["REMReminderDueDateDeltaAlertContextChangeItem": "RPStandInDeltaContextNoAdd"],
        "RPStandInDeltaContextNoAdd has no addDueDateDeltaAlertWithDueDateDelta:"
      ),
      (["REMReminder": "RPStandInReminderWithoutStorage"], "RPStandInReminderWithoutStorage has no storage"),
      (
        ["REMReminderStorage": "RPStandInReminderStorageWithoutAlerts"],
        "RPStandInReminderStorageWithoutAlerts has no dueDateDeltaAlertsData"
      ),
    ]
  )
  func refusesEarlyBeforeAnyCall(overrides: [String: String], reason: String) {
    let setting = UUID().uuidString
    let removing = UUID().uuidString

    let oneDay = EarlyReminderChange.set(EarlyReminder(count: 1, unit: .days))
    #expect(Self.write(setting, flagged: nil, early: oneDay, replacing: overrides) == reason)
    #expect(Self.write(removing, flagged: true, early: .remove, replacing: overrides) == reason)
    #expect(writeLog.entries(for: setting).isEmpty)
    #expect(writeLog.entries(for: removing).isEmpty)
  }
}
