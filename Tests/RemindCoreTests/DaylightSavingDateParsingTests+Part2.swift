import Foundation
import Testing

@testable import RemindCore

extension DaylightSavingDateParsingTests {
  @Test("An all-day weekday is the same instant with or without this, even after a midnight clock change")
  func allDayThisMatchesBareWeekday() throws {
    var havana = Self.calendar(Self.havana)
    havana.firstWeekday = 1
    let now = Self.date("2026-03-10T17:00:00Z")

    let bare = try #require(DateParsing.parseUserDateWithMetadata("friday", now: now, calendar: havana))
    let this = try #require(DateParsing.parseUserDateWithMetadata("this friday", now: now, calendar: havana))
    #expect(this == bare)
    #expect(this.date == Self.date("2026-03-13T04:00:00Z"))
    #expect(this.isDateOnly)

    let timed = try #require(DateParsing.parseUserDateWithMetadata("this friday 9am", now: now, calendar: havana))
    #expect(timed.date == Self.date("2026-03-13T13:00:00Z"))
  }

  @Test("An absolute date still refuses a time in the gap and takes the second of a repeated hour")
  func absoluteDatesKeepTheirOwnRules() throws {
    let newYork = Self.calendar(Self.newYork)
    let now = Self.date("2026-03-06T17:00:00Z")

    #expect(DateParsing.parseUserDateWithMetadata("2026-03-08 02:30", now: now, calendar: newYork) == nil)
    #expect(DateParsing.parseUserDateWithMetadata("2026-03-08T02:30", now: now, calendar: newYork) == nil)
    #expect(
      DateParsing.parseUserDateWithMetadata("2026-10-04 02:15", now: now, calendar: Self.calendar(Self.lordHowe))
        == nil
    )

    let repeated = try #require(
      DateParsing.parseUserDateWithMetadata("2026-11-01 01:30", now: now, calendar: newYork)
    )
    #expect(repeated.date == Self.date("2026-11-01T06:30:00Z"))
    #expect(!repeated.isDateOnly)
  }

  @Test("A refused clock-change time throws an error that names the requested day")
  func clockChangeRefusalNamesTheDay() {
    let nuuk = Self.calendar(Self.nuuk)
    let friday = Self.date("2026-03-27T12:00:00Z")
    let saturday = Self.date("2026-03-28T12:00:00Z")
    let why = "(that time doesn't exist on 2026-03-28 because the clocks change; pick another time)."

    for input in ["saturday 23:30", "this saturday 11:30pm", "tomorrow 23:30", "sat 23:00", " SATURDAY 23:30 "] {
      do {
        _ = try DateParsing.requireUserDate(input, now: friday, calendar: nuuk)
        Issue.record("\(input) was accepted")
      } catch let error as RemindCoreError {
        #expect(error == .invalidDateClockChange(input, day: "2026-03-28"), "\(input)")
        #expect(error.localizedDescription == "Invalid date: \"\(input)\" \(why)", "\(input)")
      } catch {
        Issue.record("\(input) threw \(error)")
      }
    }
    #expect(throws: RemindCoreError.invalidDateClockChange("today 23:30", day: "2026-03-28")) {
      try DateParsing.requireUserDate("today 23:30", now: saturday, calendar: nuuk)
    }
  }

  @Test("Every other refusal is still the plain invalid-date error")
  func otherRefusalsStayPlain() {
    let nuuk = Self.calendar(Self.nuuk)
    let friday = Self.date("2026-03-27T12:00:00Z")

    for input in [
      "someday", "next week", "yesterday 9:00", "saturday 25:00", "saturday 9:60", "saturday 9",
      "2026-03-28 23:30", "next 23:30", "",
    ] {
      #expect(throws: RemindCoreError.invalidDate(input), "\(input)") {
        try DateParsing.requireUserDate(input, now: friday, calendar: nuuk)
      }
    }
    #expect(throws: RemindCoreError.invalidDate("2026-03-08 02:30")) {
      try DateParsing.requireUserDate(
        "2026-03-08 02:30",
        now: Self.date("2026-03-06T17:00:00Z"),
        calendar: Self.calendar(Self.newYork)
      )
    }
  }

  @Test("A gap time that stays on its day, and a time before the gap, parse without an error")
  func acceptedTimesDoNotThrow() throws {
    let nuuk = Self.calendar(Self.nuuk)
    let friday = Self.date("2026-03-27T12:00:00Z")
    #expect(
      try DateParsing.requireUserDate("saturday 22:30", now: friday, calendar: nuuk).date
        == Self.date("2026-03-29T00:30:00Z")
    )
    #expect(try DateParsing.requireUserDate("saturday", now: friday, calendar: nuuk).isDateOnly)
    let newYork = Self.calendar(Self.newYork)
    let beforeSpring = Self.date("2026-03-06T17:00:00Z")
    #expect(
      try DateParsing.requireUserDate("sunday 2:30", now: beforeSpring, calendar: newYork).date
        == Self.date("2026-03-08T07:30:00Z")
    )
  }
}
