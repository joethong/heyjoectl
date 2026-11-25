import Foundation
import RemindCore
import Testing

@testable import remindctl

@MainActor
struct AlarmBeforeParsingTests {
  @Test(
    "Whole numbers of minutes, hours, days and weeks parse to seconds",
    arguments: [
      ("5m", 300), ("15m", 900), ("1h", 3600), ("2h", 7200), ("1d", 86_400), ("1w", 604_800), ("90m", 5400),
    ])
  func validDurations(input: String, seconds: Int) throws {
    #expect(try CommandHelpers.parseAlarmBefore(input) == .set(beforeDueSeconds: seconds))
  }

  @Test("The longest accepted duration is 366 days")
  func longestDuration() throws {
    #expect(try CommandHelpers.parseAlarmBefore("366d") == .set(beforeDueSeconds: 31_622_400))
    #expect(try CommandHelpers.parseAlarmBefore("527040m") == .set(beforeDueSeconds: 31_622_400))
    #expect(try CommandHelpers.parseAlarmBefore("52w") == .set(beforeDueSeconds: 31_449_600))
  }

  @Test("Case and surrounding spaces are tolerated")
  func tolerantInput() throws {
    #expect(try CommandHelpers.parseAlarmBefore(" 15M ") == .set(beforeDueSeconds: 900))
  }

  @Test("none removes the relative alarms")
  func none() throws {
    #expect(try CommandHelpers.parseAlarmBefore("none") == .remove)
    #expect(try CommandHelpers.parseAlarmBefore("NONE") == .remove)
  }

  @Test(
    "Bad input is an error that names the value and the accepted forms",
    arguments: [
      "0m", "0h", "1x", "", "  ", "-5m", "+5m", "m", "15", "1.5h", "5 m", "1m30s", "none5", "99999999999999999999m",
      "9223372036854775807w", "153722867280912930m", "367d", "527041m", "53w",
    ])
  func badDurations(input: String) {
    do {
      _ = try CommandHelpers.parseAlarmBefore(input)
      Issue.record("Expected an error for \"\(input)\"")
    } catch let error as RemindCoreError {
      #expect(
        error.errorDescription
          == "Invalid --alarm-before: \"\(input)\" "
          + "(use a whole number above 0 with m, h, d or w, up to 366 days, such as 15m, 1h, 1d or 1w, or none)"
      )
    } catch {
      Issue.record("Unexpected error \(error)")
    }
  }
}

@MainActor
struct AddAlarmBeforeTests {
  @Test("No --alarm-before gives no alarm")
  func absent() throws {
    #expect(try AddCommand.alarmBeforeSeconds(value: nil, hasDue: false) == nil)
  }

  @Test("--alarm-before with a due date gives the seconds")
  func withDue() throws {
    #expect(try AddCommand.alarmBeforeSeconds(value: "15m", hasDue: true) == 900)
  }

  @Test("--alarm-before without --due is an error")
  func withoutDue() {
    #expect(throws: RemindCoreError.operationFailed("--alarm-before needs a due date: add --due")) {
      _ = try AddCommand.alarmBeforeSeconds(value: "15m", hasDue: false)
    }
  }

  @Test("--alarm-before none on add adds no alarm, with or without --due")
  func noneOnAdd() throws {
    #expect(try AddCommand.alarmBeforeSeconds(value: "none", hasDue: true) == nil)
    #expect(try AddCommand.alarmBeforeSeconds(value: "none", hasDue: false) == nil)
  }
}
