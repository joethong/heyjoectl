import Foundation
import Testing

@testable import RemindCore

struct EarlyReminderTests {
  private static func stored(_ alerts: String) -> Data {
    Data(
      """
      {"minimumSupportedVersion": 20230430, "accountIdentifier": "A", "reminderIdentifier": "R", \
      "dueDateDeltaAlerts": [\(alerts)]}
      """.utf8
    )
  }

  private static func alert(unit: Int, count: Int) -> String {
    """
    {"identifier": "X", "dueDateDeltaUnit": \(unit), "dueDateDeltaCount": \(count), \
    "creationDate": 800000000.5, "acknowledgedDate": 800000100.5, "minimumSupportedAppVersion": 0}
    """
  }

  @Test("The stored shape with unit 2 and count -1 is 1 day before")
  func sampleShape() throws {
    let parsed = try EarlyReminder.parse(Self.stored(Self.alert(unit: 2, count: -1)))

    #expect(parsed == EarlyReminder(count: 1, unit: .days))
  }

  @Test(
    "Each stored unit has a name",
    arguments: [
      (0, EarlyReminderUnit.minutes), (1, .hours), (2, .days), (3, .weeks), (4, .months),
    ]
  )
  func units(stored: Int, expected: EarlyReminderUnit) throws {
    let parsed = try EarlyReminder.parse(Self.stored(Self.alert(unit: stored, count: -3)))

    #expect(parsed == EarlyReminder(count: 3, unit: expected))
  }

  @Test("More than one alert cannot be read, so a read-back needs exactly one")
  func twoAlertsUnreadable() throws {
    let alerts = [Self.alert(unit: 1, count: -2), Self.alert(unit: 3, count: -1)].joined(separator: ",")

    #expect(throws: EarlyReminderError.alertCount(2)) { try EarlyReminder.parse(Self.stored(alerts)) }
  }

  @Test("No alerts means no Early Reminder, not an error")
  func noAlerts() throws {
    #expect(try EarlyReminder.parse(Self.stored("")) == nil)
  }

  @Test("Data that is not JSON cannot be read")
  func badJSON() {
    #expect(throws: (any Error).self) { try EarlyReminder.parse(Data("not json".utf8)) }
  }

  @Test("A missing key cannot be read")
  func missingKey() {
    let noCount = Data(#"{"dueDateDeltaAlerts": [{"dueDateDeltaUnit": 2}]}"#.utf8)
    let noAlerts = Data(#"{"minimumSupportedVersion": 20230430}"#.utf8)

    #expect(throws: (any Error).self) { try EarlyReminder.parse(noCount) }
    #expect(throws: (any Error).self) { try EarlyReminder.parse(noAlerts) }
  }

  @Test("A count too large to negate cannot be read, and does not crash")
  func countOutOfRange() {
    #expect(throws: EarlyReminderError.countOutOfRange(Int.min)) {
      try EarlyReminder.parse(Self.stored(Self.alert(unit: 2, count: Int.min)))
    }
  }

  @Test("An unknown unit cannot be read")
  func unknownUnit() {
    #expect(throws: (any Error).self) { try EarlyReminder.parse(Self.stored(Self.alert(unit: 9, count: -1))) }
  }

  @Test("Display says the count and the unit, singular for one")
  func display() {
    #expect(EarlyReminder(count: 1, unit: .days).displayString == "1 day")
    #expect(EarlyReminder(count: 2, unit: .weeks).displayString == "2 weeks")
    #expect(EarlyReminder(count: 30, unit: .minutes).displayString == "30 minutes")
  }

  @Test("JSON is a count and a unit name")
  func json() throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]

    let data = try encoder.encode(EarlyReminder(count: 1, unit: .days))

    #expect(String(bytes: data, encoding: .utf8) == #"{"count":1,"unit":"days"}"#)
  }

  @Test(
    "One year in each unit",
    arguments: [
      (EarlyReminderUnit.minutes, 525_600), (.hours, 8760), (.days, 366), (.weeks, 52), (.months, 12),
    ]
  )
  func countInOneYear(unit: EarlyReminderUnit, count: Int) {
    #expect(unit.countInOneYear == count)
  }
}
