import Foundation
import Testing

@testable import RemindCore

struct DaylightSavingDateParsingTests {
  struct Case: Sendable, CustomTestStringConvertible {
    let zone: String
    let now: String
    let input: String
    let day: String
    let instant: String
    let isDateOnly: Bool
    var testDescription: String { "\(zone) \(input) from \(now)" }
  }

  static func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone) ?? .current
    calendar.firstWeekday = 2
    return calendar
  }

  static func date(_ iso: String) -> Date {
    ISO8601DateFormatter().date(from: iso) ?? .distantPast
  }

  static func localDay(_ date: Date, calendar: Calendar) -> String {
    let parts = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
  }

  static let newYork = "America/New_York"
  static let lordHowe = "Australia/Lord_Howe"
  static let nuuk = "America/Nuuk"
  static let havana = "America/Havana"

  static let cases: [Case] = [
    Case(
      zone: newYork,
      now: "2026-03-06T17:00:00Z",
      input: "sunday 2:30",
      day: "2026-03-08",
      instant: "2026-03-08T07:30:00Z",
      isDateOnly: false
    ),
    Case(
      zone: newYork,
      now: "2026-03-06T17:00:00Z",
      input: "next sun 2:30am",
      day: "2026-03-08",
      instant: "2026-03-08T07:30:00Z",
      isDateOnly: false
    ),
    Case(
      zone: newYork,
      now: "2026-03-06T17:00:00Z",
      input: "this sunday 2:30",
      day: "2026-03-08",
      instant: "2026-03-08T07:30:00Z",
      isDateOnly: false
    ),
    Case(
      zone: newYork,
      now: "2026-03-07T17:00:00Z",
      input: "tomorrow 2:30",
      day: "2026-03-08",
      instant: "2026-03-08T07:30:00Z",
      isDateOnly: false
    ),
    Case(
      zone: newYork,
      now: "2026-03-08T05:30:00Z",
      input: "today 2:30",
      day: "2026-03-08",
      instant: "2026-03-08T07:30:00Z",
      isDateOnly: false
    ),
    Case(
      zone: newYork,
      now: "2026-10-30T16:00:00Z",
      input: "sunday 1:30",
      day: "2026-11-01",
      instant: "2026-11-01T05:30:00Z",
      isDateOnly: false
    ),
    Case(
      zone: newYork,
      now: "2026-10-31T16:00:00Z",
      input: "tomorrow 1:30am",
      day: "2026-11-01",
      instant: "2026-11-01T05:30:00Z",
      isDateOnly: false
    ),
    Case(
      zone: newYork,
      now: "2026-10-30T16:00:00Z",
      input: "sunday 2:30",
      day: "2026-11-01",
      instant: "2026-11-01T07:30:00Z",
      isDateOnly: false
    ),
    Case(
      zone: newYork,
      now: "2026-03-06T17:00:00Z",
      input: "sunday",
      day: "2026-03-08",
      instant: "2026-03-08T05:00:00Z",
      isDateOnly: true
    ),
    Case(
      zone: newYork,
      now: "2026-03-06T17:00:00Z",
      input: "monday 9am",
      day: "2026-03-09",
      instant: "2026-03-09T13:00:00Z",
      isDateOnly: false
    ),
    Case(
      zone: newYork,
      now: "2026-03-07T17:00:00Z",
      input: "tomorrow",
      day: "2026-03-08",
      instant: "2026-03-08T05:00:00Z",
      isDateOnly: true
    ),
    Case(
      zone: newYork,
      now: "2026-10-30T16:00:00Z",
      input: "sunday",
      day: "2026-11-01",
      instant: "2026-11-01T04:00:00Z",
      isDateOnly: true
    ),
    Case(
      zone: newYork,
      now: "2026-10-30T16:00:00Z",
      input: "monday 9am",
      day: "2026-11-02",
      instant: "2026-11-02T14:00:00Z",
      isDateOnly: false
    ),
    Case(
      zone: lordHowe,
      now: "2026-10-03T01:30:00Z",
      input: "sunday 2:15",
      day: "2026-10-04",
      instant: "2026-10-03T15:45:00Z",
      isDateOnly: false
    ),
    Case(
      zone: lordHowe,
      now: "2026-10-03T01:30:00Z",
      input: "this sunday 2:15",
      day: "2026-10-04",
      instant: "2026-10-03T15:45:00Z",
      isDateOnly: false
    ),
    Case(
      zone: lordHowe,
      now: "2026-10-03T01:30:00Z",
      input: "tomorrow 2:15",
      day: "2026-10-04",
      instant: "2026-10-03T15:45:00Z",
      isDateOnly: false
    ),
    Case(
      zone: lordHowe,
      now: "2026-10-03T01:30:00Z",
      input: "sunday 2:30",
      day: "2026-10-04",
      instant: "2026-10-03T15:30:00Z",
      isDateOnly: false
    ),
    Case(
      zone: lordHowe,
      now: "2026-10-03T01:30:00Z",
      input: "sunday",
      day: "2026-10-04",
      instant: "2026-10-03T13:30:00Z",
      isDateOnly: true
    ),
    Case(
      zone: lordHowe,
      now: "2026-10-03T01:30:00Z",
      input: "monday 9am",
      day: "2026-10-05",
      instant: "2026-10-04T22:00:00Z",
      isDateOnly: false
    ),
    Case(
      zone: lordHowe,
      now: "2026-04-03T01:00:00Z",
      input: "sunday 1:45",
      day: "2026-04-05",
      instant: "2026-04-04T14:45:00Z",
      isDateOnly: false
    ),
    Case(
      zone: lordHowe,
      now: "2026-04-04T01:00:00Z",
      input: "tomorrow 1:45",
      day: "2026-04-05",
      instant: "2026-04-04T14:45:00Z",
      isDateOnly: false
    ),
  ]

  @Test("A weekday, today or tomorrow stays on its own day across a clock change", arguments: cases)
  func staysOnRequestedDay(_ testCase: Case) throws {
    let calendar = Self.calendar(testCase.zone)
    let parsed = try #require(
      DateParsing.parseUserDateWithMetadata(
        testCase.input,
        now: Self.date(testCase.now),
        calendar: calendar
      )
    )
    #expect(Self.localDay(parsed.date, calendar: calendar) == testCase.day)
    #expect(parsed.date == Self.date(testCase.instant))
    #expect(parsed.isDateOnly == testCase.isDateOnly)
  }

  @Test("A time in a gap that would land on the next day is refused, not moved to it")
  func gapPastMidnightIsRefused() throws {
    let nuuk = Self.calendar(Self.nuuk)
    let friday = Self.date("2026-03-27T12:00:00Z")
    let saturday = Self.date("2026-03-28T12:00:00Z")

    for input in ["saturday 23:30", "this saturday 11:30pm", "tomorrow 23:30", "sat 23:00"] {
      #expect(DateParsing.parseUserDateWithMetadata(input, now: friday, calendar: nuuk) == nil, "\(input)")
    }
    #expect(DateParsing.parseUserDateWithMetadata("today 23:30", now: saturday, calendar: nuuk) == nil)

    let allDay = try #require(DateParsing.parseUserDateWithMetadata("saturday", now: friday, calendar: nuuk))
    #expect(Self.localDay(allDay.date, calendar: nuuk) == "2026-03-28")
    #expect(allDay.date == Self.date("2026-03-28T02:00:00Z"))
    #expect(allDay.isDateOnly)

    let before = try #require(DateParsing.parseUserDateWithMetadata("saturday 22:30", now: friday, calendar: nuuk))
    #expect(before.date == Self.date("2026-03-29T00:30:00Z"))
    #expect(!before.isDateOnly)
  }
}
