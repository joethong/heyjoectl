import Foundation
import Testing

@testable import RemindCore
@testable import remindctl

private let nuuk: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "America/Nuuk")!
  calendar.firstWeekday = 2
  return calendar
}()

private let friday = ISO8601DateFormatter().date(from: "2026-03-27T12:00:00Z")!
private let saturday = ISO8601DateFormatter().date(from: "2026-03-28T12:00:00Z")!

private func message(_ body: () throws -> Void) -> String? {
  do {
    try body()
    return nil
  } catch {
    return (error as? RemindCoreError)?.errorDescription
  }
}

private func clockChange(_ input: String, day: String) -> String {
  "Invalid date: \"\(input)\" (that time doesn't exist on \(day) because the clocks change; pick another time)."
}

@MainActor
struct ClockChangeMessageTests {
  @Test(
    "A weekday or tomorrow time inside the clock-change gap says why",
    arguments: ["saturday 23:30", "tomorrow 23:30"])
  func dueDateSaysWhy(_ input: String) {
    #expect(
      message { _ = try CommandHelpers.parseDueDate(input, now: friday, calendar: nuuk) }
        == clockChange(input, day: "2026-03-28"))
  }

  @Test("Today with a time inside the gap says why")
  func todaySaysWhy() {
    #expect(
      message { _ = try CommandHelpers.parseDueDate("today 23:30", now: saturday, calendar: nuuk) }
        == clockChange("today 23:30", day: "2026-03-28"))
  }

  @Test("A repeat-until time inside the gap says why")
  func repeatUntilSaysWhy() {
    #expect(
      message {
        _ = try CommandHelpers.parseRecurrenceEnd(until: "saturday 23:30", count: nil, calendar: nuuk, now: friday)
      }
        == clockChange("saturday 23:30", day: "2026-03-28"))
  }

  @Test("Other refusals keep the plain message", arguments: ["someday", "saturday 25:00", "2026-03-28 23:30", ""])
  func otherRefusalsStayPlain(_ input: String) {
    #expect(
      message { _ = try CommandHelpers.parseDueDate(input, now: friday, calendar: nuuk) }
        == "Invalid date: \"\(input)\".")
    #expect(
      message { _ = try CommandHelpers.parseRecurrenceEnd(until: input, count: nil, calendar: nuuk, now: friday) }
        == "Invalid date: \"\(input)\".")
  }

  @Test("A gap time that stays on its day is still accepted")
  func acceptedTimeStillParses() throws {
    let parsed = try CommandHelpers.parseDueDate("saturday 22:30", now: friday, calendar: nuuk)
    #expect(parsed.date == ISO8601DateFormatter().date(from: "2026-03-29T00:30:00Z"))
  }
}
