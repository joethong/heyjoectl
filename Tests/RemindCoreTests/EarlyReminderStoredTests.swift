import Foundation
import RemindCore
import Testing

struct EarlyReminderStoredTests {
  @Test(
    "Each unit is written as ReminderKit's number with a negative count, and reads back as the same Early Reminder",
    arguments: [
      (EarlyReminderUnit.minutes, 0), (.hours, 1), (.days, 2), (.weeks, 3), (.months, 4),
    ])
  func roundTrips(unit: EarlyReminderUnit, number: Int) throws {
    let early = EarlyReminder(count: 15, unit: unit)

    #expect(early.stored.unit == number)
    #expect(early.stored.count == -15)
    let json = #"{"dueDateDeltaAlerts":[{"dueDateDeltaUnit":\#(number),"dueDateDeltaCount":\#(early.stored.count)}]}"#
    #expect(try EarlyReminder.parse(Data(json.utf8)) == early)
  }
}
