import Foundation
import RemindCore
import RemindPrivate
import Testing

@testable import remindctl

extension RemindPrivateWriteBridgeTests {
  @Test(
    "A missing or changed REMDueDateDeltaInterval refuses setting an Early Reminder but not removing one",
    arguments: [
      (["REMDueDateDeltaInterval": "RPNoSuchClass"], "ReminderKit has no RPNoSuchClass"),
      (
        ["REMDueDateDeltaInterval": "RPStandInDueDateDeltaIntervalTakingInt32"],
        "RPStandInDueDateDeltaIntervalTakingInt32 initWithUnit:count: has an unexpected signature"
      ),
    ]
  )
  func intervalNeededOnlyToSet(overrides: [String: String], reason: String) {
    let setting = UUID().uuidString
    let removing = UUID().uuidString

    let oneDay = EarlyReminderChange.set(EarlyReminder(count: 1, unit: .days))
    #expect(Self.write(setting, flagged: nil, early: oneDay, replacing: overrides) == reason)
    #expect(writeLog.entries(for: setting).isEmpty)
    #expect(Self.write(removing, flagged: nil, early: .remove, replacing: overrides) == nil)
    #expect(writeLog.entries(for: removing).last == "save")
  }

  @Test("No alert context, or no interval from ReminderKit, fails the Early Reminder write without saving")
  func nilContextOrIntervalFails() {
    let oneDay = EarlyReminderChange.set(EarlyReminder(count: 1, unit: .days))
    #expect(
      Self.write(noAlertContextID, flagged: nil, early: oneDay)
        == "REMReminderChangeItem dueDateDeltaAlertContext returned no Early Reminder change"
    )
    #expect(!writeLog.entries(for: noAlertContextID).contains("save"))

    let id = UUID().uuidString
    #expect(
      Self.write(
        id,
        flagged: nil,
        early: oneDay,
        replacing: ["REMDueDateDeltaInterval": "RPStandInDueDateDeltaIntervalReturningNil"]
      )
        == "REMDueDateDeltaInterval initWithUnit:count: returned nothing"
    )
    #expect(!writeLog.entries(for: id).contains("save"))
  }

  @Test(
    "A flag-only or Urgent-only write does not check the Early Reminder's classes or methods",
    arguments: [
      ["REMDueDateDeltaInterval": "RPNoSuchClass"],
      ["REMReminderDueDateDeltaAlertContextChangeItem": "RPNoSuchClass"],
      ["REMDueDateDeltaInterval": "RPStandInDueDateDeltaIntervalTakingInt32"],
      ["REMReminderDueDateDeltaAlertContextChangeItem": "RPStandInDeltaContextNoAdd"],
      ["REMReminder": "RPStandInReminderWithoutStorage"],
      ["REMReminderStorage": "RPStandInReminderStorageWithoutAlerts"],
    ]
  )
  func otherWritesIgnoreEarlyRequirements(overrides: [String: String]) {
    let flagOnly = UUID().uuidString
    let urgentOnly = UUID().uuidString

    #expect(Self.write(flagOnly, flagged: true, replacing: overrides) == nil)
    #expect(Self.write(urgentOnly, flagged: nil, urgent: false, replacing: overrides) == nil)
    #expect(writeLog.entries(for: flagOnly).last == "save")
    #expect(writeLog.entries(for: urgentOnly).last == "save")
  }

  static let firstAlertID = "1FA0D26C-0395-4D60-A75D-42693F041C0F"
  static let secondAlertID = "2C6E9B41-8D0A-4F3E-B5A7-0E1D2C3B4A59"

  static func storeAlerts(_ id: String, _ json: String) {
    storedAlerts.set(id, Data(json.utf8) as NSData)
  }

  static func alertsJSON(_ ids: [String]) -> String {
    let alerts = ids.map { #"{"identifier":"\#($0)","dueDateDeltaUnit":2,"dueDateDeltaCount":-1}"# }
    return #"{"accountIdentifier":"A","dueDateDeltaAlerts":[\#(alerts.joined(separator: ","))]}"#
  }

  @Test("Setting an Early Reminder removes the alerts already on the reminder by id before adding the new one")
  func setReplacesExistingAlerts() {
    let id = UUID().uuidString
    Self.storeAlerts(id, Self.alertsJSON([Self.firstAlertID, Self.secondAlertID]))

    #expect(Self.write(id, flagged: nil, early: .set(EarlyReminder(count: 15, unit: .minutes))) == nil)
    #expect(
      writeLog.entries(for: id) == [
        "fetch x-apple-reminderkit://REMCDReminder/\(id)",
        "removeAlerts \(Self.firstAlertID) \(Self.secondAlertID)",
        "removeAllFetchedDueDateDeltaAlerts", "addAlert 0 -15", "save",
      ]
    )
  }

  @Test("--early none removes the alerts already on the reminder by id and adds nothing")
  func removalRemovesExistingAlerts() {
    let id = UUID().uuidString
    Self.storeAlerts(id, Self.alertsJSON([Self.firstAlertID]))

    #expect(Self.write(id, flagged: nil, early: .remove) == nil)
    #expect(
      writeLog.entries(for: id) == [
        "fetch x-apple-reminderkit://REMCDReminder/\(id)", "removeAlerts \(Self.firstAlertID)",
        "removeAllFetchedDueDateDeltaAlerts", "save",
      ]
    )
  }

  @Test("A reminder whose stored alert list is empty gets the new Early Reminder with nothing removed by id")
  func emptyAlertListAddsOnly() {
    let id = UUID().uuidString
    Self.storeAlerts(id, Self.alertsJSON([]))

    #expect(Self.write(id, flagged: nil, early: .set(EarlyReminder(count: 1, unit: .hours))) == nil)
    #expect(
      writeLog.entries(for: id) == [
        "fetch x-apple-reminderkit://REMCDReminder/\(id)", "removeAllFetchedDueDateDeltaAlerts", "addAlert 1 -1",
        "save",
      ]
    )
  }

  @Test(
    "Early Reminder ids that cannot be read fail the write before anything is changed or saved",
    arguments: [
      #"not json"#,
      #"{"dueDateDeltaAlerts":{}}"#,
      #"{"accountIdentifier":"A"}"#,
      #"{"dueDateDeltaAlerts":[{"dueDateDeltaUnit":2,"dueDateDeltaCount":-1}]}"#,
      #"{"dueDateDeltaAlerts":[{"identifier":"not-a-uuid","dueDateDeltaUnit":2,"dueDateDeltaCount":-1}]}"#,
      #"{"dueDateDeltaAlerts":[{"identifier":7}]}"#,
      #"["1FA0D26C-0395-4D60-A75D-42693F041C0F"]"#,
    ]
  )
  func unreadableIDsFail(json: String) {
    let setting = UUID().uuidString
    let removing = UUID().uuidString
    Self.storeAlerts(setting, json)
    Self.storeAlerts(removing, json)

    let reason = "the Early Reminders already on the reminder could not be read"
    #expect(Self.write(setting, flagged: true, early: .set(EarlyReminder(count: 1, unit: .days))) == reason)
    #expect(Self.write(removing, flagged: nil, early: .remove) == reason)
    #expect(writeLog.entries(for: setting) == ["fetch x-apple-reminderkit://REMCDReminder/\(setting)"])
    #expect(writeLog.entries(for: removing) == ["fetch x-apple-reminderkit://REMCDReminder/\(removing)"])
  }

  @Test("Early Reminder data that is not data, or a reminder with no storage, fails the write before any change")
  func missingAlertDataFails() {
    let id = UUID().uuidString
    storedAlerts.set(id, "{}" as NSString)
    let reason = "the Early Reminders already on the reminder could not be read"

    #expect(Self.write(id, flagged: nil, early: .remove) == reason)
    #expect(Self.write(writeNoStorageID, flagged: nil, early: .remove) == reason)
    #expect(writeLog.entries(for: id) == ["fetch x-apple-reminderkit://REMCDReminder/\(id)"])
    #expect(writeLog.entries(for: writeNoStorageID).count == 1)
  }

  @Test("The flag, Urgent and a new Early Reminder replace the alerts already on the reminder in one save")
  func combinedWriteReplacesExistingAlerts() {
    let id = UUID().uuidString
    Self.storeAlerts(id, Self.alertsJSON([Self.firstAlertID]))

    #expect(Self.write(id, flagged: true, urgent: true, early: .set(EarlyReminder(count: 2, unit: .days))) == nil)
    #expect(
      writeLog.entries(for: id) == [
        "fetch x-apple-reminderkit://REMCDReminder/\(id)", "setFlagged 1", "setUrgent true",
        "removeAlerts \(Self.firstAlertID)", "removeAllFetchedDueDateDeltaAlerts", "addAlert 2 -2", "save",
      ]
    )
  }

  @Test("A flag-only write does not read the Early Reminders already on the reminder")
  func flagOnlyIgnoresAlertData() {
    let id = UUID().uuidString
    Self.storeAlerts(id, "not json")

    #expect(Self.write(id, flagged: true) == nil)
    #expect(writeLog.entries(for: id).last == "save")
  }

  @Test(
    "A missing or changed removeDueDateDeltaAlertsWithIdentifiers: refuses an Early Reminder write before any call",
    arguments: [
      (
        "RPStandInDeltaContextNoRemoveByID",
        "RPStandInDeltaContextNoRemoveByID has no removeDueDateDeltaAlertsWithIdentifiers:"
      ),
      (
        "RPStandInDeltaContextRemovingByString",
        "RPStandInDeltaContextRemovingByString removeDueDateDeltaAlertsWithIdentifiers: "
          + "has an unexpected signature"
      ),
    ]
  )
  func refusesWithoutRemoveByID(standIn: String, reason: String) {
    let setting = UUID().uuidString
    let removing = UUID().uuidString
    let flagOnly = UUID().uuidString
    let overrides = ["REMReminderDueDateDeltaAlertContextChangeItem": standIn]

    let oneDay = EarlyReminderChange.set(EarlyReminder(count: 1, unit: .days))
    #expect(Self.write(setting, flagged: nil, early: oneDay, replacing: overrides) == reason)
    #expect(Self.write(removing, flagged: nil, early: .remove, replacing: overrides) == reason)
    #expect(writeLog.entries(for: setting).isEmpty)
    #expect(writeLog.entries(for: removing).isEmpty)
    #expect(Self.write(flagOnly, flagged: true, replacing: overrides) == nil)
  }
}
