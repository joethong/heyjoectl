import Foundation
import Testing

@testable import RemindCore

struct WeekdayDateParsingTests {
  private static let zone = TimeZone(secondsFromGMT: 8 * 3600) ?? .current

  private static func calendar(firstWeekday: Int) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    calendar.firstWeekday = firstWeekday
    return calendar
  }

  private static func at(_ day: Int, hour: Int = 10, minute: Int = 0, calendar: Calendar) -> Date {
    let components = DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)
    return calendar.date(from: components) ?? .distantPast
  }

  private static let mondayFirst = calendar(firstWeekday: 2)
  private static let sundayFirst = calendar(firstWeekday: 1)

  private static var thursday: Date { at(19, calendar: mondayFirst) }
  private static var sunday: Date { at(22, calendar: mondayFirst) }

  private static func day(_ day: Int, hour: Int? = nil, minute: Int = 0) -> Date {
    let calendar = mondayFirst
    guard let hour else { return calendar.startOfDay(for: at(day, calendar: calendar)) }
    return at(day, hour: hour, minute: minute, calendar: calendar)
  }

  private func parse(
    _ input: String,
    now: Date = WeekdayDateParsingTests.thursday,
    calendar: Calendar = WeekdayDateParsingTests.mondayFirst
  ) -> ParsedUserDate? {
    DateParsing.parseUserDateWithMetadata(input, now: now, calendar: calendar)
  }

  struct Weekday: Sendable, CustomTestStringConvertible {
    let full: String
    let short: String
    let fromThursday: Int
    let fromSunday: Int
    var testDescription: String { full }
  }

  static let weekdays = [
    Weekday(full: "monday", short: "mon", fromThursday: 23, fromSunday: 23),
    Weekday(full: "tuesday", short: "tue", fromThursday: 24, fromSunday: 24),
    Weekday(full: "wednesday", short: "wed", fromThursday: 25, fromSunday: 25),
    Weekday(full: "thursday", short: "thu", fromThursday: 26, fromSunday: 26),
    Weekday(full: "friday", short: "fri", fromThursday: 20, fromSunday: 27),
    Weekday(full: "saturday", short: "sat", fromThursday: 21, fromSunday: 28),
    Weekday(full: "sunday", short: "sun", fromThursday: 22, fromSunday: 29),
  ]

  private static func spellings(_ name: String) -> [String] {
    [name, name.uppercased(), name.capitalized, "  \(name)  "]
  }

  @Test("A bare weekday is the next one after today, all day", arguments: weekdays)
  func bareWeekday(_ weekday: Weekday) throws {
    for name in [weekday.full, weekday.short] {
      for spelling in Self.spellings(name) {
        let fromThursday = try #require(parse(spelling), "\(spelling) from a Thursday")
        #expect(fromThursday.date == Self.day(weekday.fromThursday))
        #expect(fromThursday.isDateOnly)

        let fromSunday = try #require(parse(spelling, now: Self.sunday), "\(spelling) from a Sunday")
        #expect(fromSunday.date == Self.day(weekday.fromSunday))
        #expect(fromSunday.isDateOnly)
      }
    }
  }

  @Test("next <weekday> matches the bare weekday", arguments: weekdays)
  func nextWeekday(_ weekday: Weekday) throws {
    for name in [weekday.full, weekday.short] {
      for spelling in Self.spellings(name) {
        for prefix in ["next ", "NEXT ", "Next   "] {
          let fromThursday = try #require(parse(prefix + spelling))
          #expect(fromThursday.date == Self.day(weekday.fromThursday))
          #expect(fromThursday.isDateOnly)
          let fromSunday = try #require(parse(prefix + spelling, now: Self.sunday))
          #expect(fromSunday.date == Self.day(weekday.fromSunday))
        }
      }
    }
  }

  @Test("Today's own weekday means a week from today")
  func ownWeekday() throws {
    #expect(try #require(parse("thursday")).date == Self.day(26))
    #expect(try #require(parse("next thu")).date == Self.day(26))
    #expect(try #require(parse("sunday", now: Self.sunday)).date == Self.day(29))
    #expect(try #require(parse("next sun", now: Self.sunday)).date == Self.day(29))
  }

  @Test("this <weekday> in a Monday-first week")
  func thisWeekdayMondayFirst() {
    let expected: [(String, Int?)] = [
      ("monday", nil), ("tuesday", nil), ("wednesday", nil), ("thursday", 19),
      ("friday", 20), ("saturday", 21), ("sunday", 22),
    ]
    for (name, day) in expected {
      for input in ["this \(name)", "this \(name.prefix(3))", "THIS \(name.uppercased())"] {
        let parsed = parse(input)
        if let day {
          #expect(parsed?.date == Self.day(day), "\(input)")
          #expect(parsed?.isDateOnly == true)
        } else {
          #expect(parsed == nil, "\(input) has passed")
        }
      }
    }
  }

  @Test("this <weekday> in a Sunday-first week")
  func thisWeekdaySundayFirst() {
    let expected: [(String, Int?)] = [
      ("sunday", nil), ("monday", nil), ("wednesday", nil), ("thursday", 19),
      ("friday", 20), ("saturday", 21),
    ]
    for (name, day) in expected {
      let parsed = parse("this " + name, calendar: Self.sundayFirst)
      if let day {
        #expect(parsed?.date == Self.day(day), "this \(name)")
      } else {
        #expect(parsed == nil, "this \(name) has passed")
      }
    }
  }

  @Test("this <weekday> from a Sunday depends on the week's first day")
  func thisWeekdayFromSunday() throws {
    let sunday = Self.sunday
    #expect(try #require(parse("this sunday", now: sunday)).date == Self.day(22))
    #expect(parse("this monday", now: sunday) == nil)
    #expect(parse("this saturday", now: sunday) == nil)

    let sundayFirst = Self.sundayFirst
    #expect(try #require(parse("this sunday", now: sunday, calendar: sundayFirst)).date == Self.day(22))
    #expect(try #require(parse("this monday", now: sunday, calendar: sundayFirst)).date == Self.day(23))
    #expect(try #require(parse("this sat", now: sunday, calendar: sundayFirst)).date == Self.day(28))
  }

  @Test("A time after a weekday makes a timed result")
  func weekdayWithTime() throws {
    let cases: [(String, Int, Int)] = [
      ("friday 9:00", 9, 0), ("friday 09:00", 9, 0), ("friday 9am", 9, 0), ("friday 9AM", 9, 0),
      ("friday 9 am", 9, 0), ("friday 5:30pm", 17, 30), ("friday 5:30 PM", 17, 30),
      ("friday 17:30", 17, 30), ("Fri 17:30", 17, 30), ("FRIDAY 0:00", 0, 0),
      ("friday 12am", 0, 0), ("friday 12pm", 12, 0), ("friday 12:15am", 0, 15),
      ("friday 12:15pm", 12, 15), ("friday 23:59", 23, 59), ("friday   9:00", 9, 0),
      ("next friday 9:00", 9, 0), ("next fri 5:30pm", 17, 30), ("this friday 17:30", 17, 30),
    ]
    for (input, hour, minute) in cases {
      let parsed = try #require(parse(input), "\(input)")
      #expect(parsed.date == Self.day(20, hour: hour, minute: minute), "\(input)")
      #expect(!parsed.isDateOnly, "\(input)")
    }
  }

  @Test("A time after every weekday keeps the next-day rule", arguments: weekdays)
  func timedWeekdayFromBothDays(_ weekday: Weekday) throws {
    let forms = [
      (weekday.full + " 9am", 9, 0), (weekday.short.uppercased() + " 17:30", 17, 30),
      ("next " + weekday.short + " 5:30pm", 17, 30), ("next " + weekday.full + " 12am", 0, 0),
    ]
    for (input, hour, minute) in forms {
      let fromThursday = try #require(parse(input), "\(input) from a Thursday")
      #expect(fromThursday.date == Self.day(weekday.fromThursday, hour: hour, minute: minute), "\(input)")
      #expect(!fromThursday.isDateOnly)

      let fromSunday = try #require(parse(input, now: Self.sunday), "\(input) from a Sunday")
      #expect(fromSunday.date == Self.day(weekday.fromSunday, hour: hour, minute: minute), "\(input)")
      #expect(!fromSunday.isDateOnly)
    }
  }

  @Test("A time after today or tomorrow")
  func todayAndTomorrowWithTime() throws {
    let cases: [(String, Int, Int, Int)] = [
      ("today 9:00", 19, 9, 0), ("today 9am", 19, 9, 0), ("TODAY 5:30pm", 19, 17, 30),
      ("tomorrow 9am", 20, 9, 0), ("tomorrow 09:00", 20, 9, 0), ("Tomorrow 17:30", 20, 17, 30),
      ("tomorrow 12am", 20, 0, 0),
    ]
    for (input, day, hour, minute) in cases {
      let parsed = try #require(parse(input), "\(input)")
      #expect(parsed.date == Self.day(day, hour: hour, minute: minute), "\(input)")
      #expect(!parsed.isDateOnly, "\(input)")
    }
  }

  @Test("this <weekday> allows today even when its time has passed")
  func thisTodayWithEarlierTime() throws {
    let parsed = try #require(parse("this thursday 8:00"))
    #expect(parsed.date == Self.day(19, hour: 8))
  }

  @Test(
    "Refusals",
    arguments: [
      "this monday", "this monday 9:00", "friday 9pmam", "friday 9ampm",
      "friday 25:00", "friday 24:00", "friday 9:60", "friday 9:5",
      "friday 13pm", "friday 0am", "friday 0pm", "friday 17:30pm", "friday 9", "friday 9:",
      "friday :30", "friday 9:00:00", "friday 9:00 xm", "friday 9am 10am", "fri day", "fri  day",
      "friday junk", "friday,", "fridays", "next", "this", "next week", "this week", "next next friday",
      "this next friday", "next today", "this tomorrow", "next tomorrow", "today 25:00", "today 9",
      "tomorrow 13pm", "tomorrow junk", "yesterday 9:00", "now 9:00", "friday 2026-11-21",
      "in 3 days", "mond", "weekday", "next friday 25:00",
    ]
  )
  func refusals(_ input: String) {
    #expect(parse(input) == nil)
    #expect(DateParsing.parseUserDate(input, now: Self.thursday, calendar: Self.mondayFirst) == nil)
  }

  @Test("A filter takes a weekday too")
  func filterAcceptsWeekday() {
    let filter = ReminderFiltering.parse("Friday", now: Self.thursday, calendar: Self.mondayFirst)
    #expect(filter == .date(Self.day(20)))
  }

  @Test(
    "Earlier forms parse exactly as before",
    arguments: ["today", "tomorrow", "yesterday", "now", "2026-11-21", "2026-11-21 9:00", "2026-11-21T09:00"]
  )
  func earlierFormsUnchanged(_ input: String) throws {
    let parsed = try #require(parse(input))
    switch input {
    case "today": #expect(parsed == ParsedUserDate(date: Self.day(19), isDateOnly: true))
    case "tomorrow": #expect(parsed == ParsedUserDate(date: Self.day(20), isDateOnly: true))
    case "yesterday": #expect(parsed == ParsedUserDate(date: Self.day(18), isDateOnly: true))
    case "now": #expect(parsed == ParsedUserDate(date: Self.thursday, isDateOnly: false))
    case "2026-11-21": #expect(parsed == ParsedUserDate(date: Self.day(21), isDateOnly: true))
    default: #expect(parsed == ParsedUserDate(date: Self.day(21, hour: 9), isDateOnly: false))
    }
  }
}
