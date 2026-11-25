import EventKit
import Foundation
import Testing

@testable import RemindCore

private let utc = Calendar.fixed(timeZone: "UTC")
private let tokyo = Calendar.fixed(timeZone: "Asia/Tokyo")
private let losAngeles = Calendar.fixed(timeZone: "America/Los_Angeles")

extension Calendar {
  fileprivate static func fixed(timeZone identifier: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: identifier)!
    return calendar
  }
}

@MainActor
struct RecurrenceEndChangeTests {
  @Test("A date-only end runs through the last second of that local day", arguments: [utc, tokyo, losAngeles])
  func dateOnlyEndsAtLastSecondOfLocalDay(_ calendar: Calendar) throws {
    let start = try #require(calendar.date(from: DateComponents(year: 2027, month: 1, day: 31)))
    let end = RecurrenceEnd.through(ParsedUserDate(date: start, isDateOnly: true), calendar: calendar)

    guard case .date(let date) = end else {
      Issue.record("expected a date end")
      return
    }
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    #expect((parts.year, parts.month, parts.day) == (2027, 1, 31))
    #expect((parts.hour, parts.minute, parts.second) == (23, 59, 59))
  }

  @Test("A date-only end handles a day with a daylight saving change")
  func dateOnlyEndOnDaylightSavingDay() throws {
    let start = try #require(losAngeles.date(from: DateComponents(year: 2027, month: 3, day: 14)))
    let end = RecurrenceEnd.through(ParsedUserDate(date: start, isDateOnly: true), calendar: losAngeles)

    guard case .date(let date) = end else {
      Issue.record("expected a date end")
      return
    }
    let parts = losAngeles.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    #expect((parts.year, parts.month, parts.day) == (2027, 3, 14))
    #expect((parts.hour, parts.minute, parts.second) == (23, 59, 59))
  }

  @Test("An end with a time is kept as given")
  func endWithTimeIsKept() throws {
    let moment = try #require(utc.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 9, minute: 30)))
    let end = RecurrenceEnd.through(ParsedUserDate(date: moment, isDateOnly: false), calendar: utc)
    #expect(end == .date(moment))
  }

  @Test("Ending a rule keeps everything else in it")
  func endingKeepsTheRest() {
    let rule = RecurrenceRule(
      frequency: .weekly,
      interval: 2,
      daysOfWeek: [RecurrenceDay(day: .mon), RecurrenceDay(day: .fri)]
    )
    let ended = rule.ending(.count(5))
    #expect(ended.end == .count(5))
    #expect(ended.frequency == .weekly)
    #expect(ended.interval == 2)
    #expect(ended.daysOfWeek == rule.daysOfWeek)
  }

  @Test("Changing only the end keeps the weekdays and interval")
  func changeEndKeepsWeekdaysAndInterval() throws {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.addRecurrenceRule(
      EKRecurrenceRule(
        recurrenceWith: .weekly,
        interval: 2,
        daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.friday)],
        daysOfTheMonth: nil,
        monthsOfTheYear: nil,
        weeksOfTheYear: nil,
        daysOfTheYear: nil,
        setPositions: nil,
        end: nil
      )
    )

    try RemindersStore.replaceRecurrenceEnd(on: reminder, with: .count(6))

    let rules = try #require(reminder.recurrenceRules)
    #expect(rules.count == 1)
    let rule = try #require(rules.first.flatMap(RecurrenceRule.init(eventKitRule:)))
    #expect(
      rule
        == RecurrenceRule(
          frequency: .weekly,
          interval: 2,
          daysOfWeek: [RecurrenceDay(day: .mon), RecurrenceDay(day: .fri)],
          end: .count(6)
        )
    )
  }

  @Test("Changing only the end keeps the first day of the week")
  func changeEndKeepsFirstDayOfWeek() throws {
    let reminder = EKReminder(eventStore: EKEventStore())
    let original = EKRecurrenceRule(
      recurrenceWith: .weekly,
      interval: 2,
      daysOfTheWeek: [EKRecurrenceDayOfWeek(.sunday), EKRecurrenceDayOfWeek(.monday)],
      daysOfTheMonth: nil,
      monthsOfTheYear: nil,
      weeksOfTheYear: nil,
      daysOfTheYear: nil,
      setPositions: nil,
      end: nil
    )
    original.setValue(1, forKey: "firstDayOfTheWeek")
    reminder.addRecurrenceRule(original)
    #expect(original.firstDayOfTheWeek == 1)

    try RemindersStore.replaceRecurrenceEnd(on: reminder, with: .count(6))

    let rules = try #require(reminder.recurrenceRules)
    #expect(rules.count == 1)
    #expect(rules.first?.firstDayOfTheWeek == 1)
    #expect(rules.first?.interval == 2)
    #expect(rules.first?.recurrenceEnd?.occurrenceCount == 6)
  }

  @Test("Changing only the end puts a new rule object on the reminder")
  func changingEndUsesANewRule() throws {
    let reminder = EKReminder(eventStore: EKEventStore())
    let original = EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)
    reminder.addRecurrenceRule(original)

    try RemindersStore.replaceRecurrenceEnd(on: reminder, with: .count(7))

    let rules = reminder.recurrenceRules ?? []
    #expect(rules.count == 1)
    #expect(rules.first.map { $0 !== original } == true)
    #expect(rules.first?.recurrenceEnd?.occurrenceCount == 7)
  }

  @Test("Changing the end replaces an earlier end")
  func changeEndReplacesEarlierEnd() throws {
    let reminder = EKReminder(eventStore: EKEventStore())
    RemindersStore.replaceRecurrence(on: reminder, with: RecurrenceRule(frequency: .daily, end: .count(3)))
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    try RemindersStore.replaceRecurrenceEnd(on: reminder, with: .date(date))

    let rule = try #require(reminder.recurrenceRules?.first.flatMap(RecurrenceRule.init(eventKitRule:)))
    #expect(rule == RecurrenceRule(frequency: .daily, end: .date(date)))
  }

  @Test("Changing only the end keeps monthly days of the month, including the last day")
  func changeEndKeepsMonthlyDaysOfTheMonth() throws {
    try expectEndChangeKeepsRule(
      RuleShape(frequency: .monthly, interval: 2, daysOfTheMonth: [1, 15, -1], firstDayOfTheWeek: 1)
    )
  }

  @Test(
    "Changing only the end keeps a monthly ordinal weekday",
    arguments: [
      RuleShape(frequency: .monthly, daysOfTheWeek: [.init(day: .friday, weekNumber: -1)], firstDayOfTheWeek: 1),
      RuleShape(frequency: .monthly, daysOfTheWeek: [.init(day: .tuesday, weekNumber: 2)], firstDayOfTheWeek: 1),
    ]
  )
  func changeEndKeepsMonthlyOrdinalWeekday(_ shape: RuleShape) throws {
    try expectEndChangeKeepsRule(shape)
  }

  @Test("Changing only the end keeps yearly months of the year with an ordinal weekday")
  func changeEndKeepsYearlyMonthsWithOrdinalWeekday() throws {
    try expectEndChangeKeepsRule(
      RuleShape(
        frequency: .yearly,
        daysOfTheWeek: [.init(day: .thursday, weekNumber: 4)],
        monthsOfTheYear: [11],
        firstDayOfTheWeek: 1
      )
    )
  }

  @Test("Changing only the end keeps yearly weeks of the year")
  func changeEndKeepsYearlyWeeksOfTheYear() throws {
    try expectEndChangeKeepsRule(
      RuleShape(
        frequency: .yearly,
        daysOfTheWeek: [.init(day: .monday)],
        weeksOfTheYear: [1, 26, -1],
        firstDayOfTheWeek: 1
      )
    )
  }

  @Test("Changing only the end keeps yearly days of the year")
  func changeEndKeepsYearlyDaysOfTheYear() throws {
    try expectEndChangeKeepsRule(RuleShape(frequency: .yearly, daysOfTheYear: [1, 100, -1], firstDayOfTheWeek: 1))
  }

  @Test("Changing only the end keeps set positions")
  func changeEndKeepsSetPositions() throws {
    let weekdays: [RuleShape.Day] = [.monday, .tuesday, .wednesday, .thursday, .friday].map { .init(day: $0) }
    try expectEndChangeKeepsRule(
      RuleShape(frequency: .monthly, daysOfTheWeek: weekdays, setPositions: [-1], firstDayOfTheWeek: 1)
    )
  }

  @Test("Changing the end of a reminder with no repeat throws and changes nothing")
  func changeEndWithoutRuleThrows() {
    let reminder = EKReminder(eventStore: EKEventStore())

    #expect(throws: RemindCoreError.self) {
      try RemindersStore.replaceRecurrenceEnd(on: reminder, with: .count(2))
    }
    #expect((reminder.recurrenceRules ?? []).isEmpty)
  }
}

struct RuleShape: Equatable, Sendable {
  struct Day: Equatable, Sendable {
    var day: EKWeekday
    var weekNumber = 0
  }

  var frequency: EKRecurrenceFrequency
  var interval = 1
  var daysOfTheWeek: [Day] = []
  var daysOfTheMonth: [Int] = []
  var monthsOfTheYear: [Int] = []
  var weeksOfTheYear: [Int] = []
  var daysOfTheYear: [Int] = []
  var setPositions: [Int] = []
  var firstDayOfTheWeek = 0

  func eventKitRule(end: EKRecurrenceEnd?) -> EKRecurrenceRule {
    func numbers(_ values: [Int]) -> [NSNumber]? { values.isEmpty ? nil : values.map { NSNumber(value: $0) } }
    let rule = EKRecurrenceRule(
      recurrenceWith: frequency,
      interval: interval,
      daysOfTheWeek: daysOfTheWeek.isEmpty
        ? nil : daysOfTheWeek.map { EKRecurrenceDayOfWeek($0.day, weekNumber: $0.weekNumber) },
      daysOfTheMonth: numbers(daysOfTheMonth),
      monthsOfTheYear: numbers(monthsOfTheYear),
      weeksOfTheYear: numbers(weeksOfTheYear),
      daysOfTheYear: numbers(daysOfTheYear),
      setPositions: numbers(setPositions),
      end: end
    )
    if firstDayOfTheWeek != 0 {
      rule.setValue(firstDayOfTheWeek, forKey: "firstDayOfTheWeek")
    }
    return rule
  }
}

extension RuleShape {
  init(_ rule: EKRecurrenceRule) {
    self.init(
      frequency: rule.frequency,
      interval: rule.interval,
      daysOfTheWeek: (rule.daysOfTheWeek ?? []).map { Day(day: $0.dayOfTheWeek, weekNumber: $0.weekNumber) },
      daysOfTheMonth: (rule.daysOfTheMonth ?? []).map(\.intValue),
      monthsOfTheYear: (rule.monthsOfTheYear ?? []).map(\.intValue),
      weeksOfTheYear: (rule.weeksOfTheYear ?? []).map(\.intValue),
      daysOfTheYear: (rule.daysOfTheYear ?? []).map(\.intValue),
      setPositions: (rule.setPositions ?? []).map(\.intValue),
      firstDayOfTheWeek: rule.firstDayOfTheWeek
    )
  }
}

@MainActor
private func expectEndChangeKeepsRule(_ shape: RuleShape, sourceLocation: SourceLocation = #_sourceLocation) throws {
  let original = shape.eventKitRule(end: EKRecurrenceEnd(occurrenceCount: 3))
  #expect(RuleShape(original) == shape, "EventKit kept every part of the original rule", sourceLocation: sourceLocation)
  #expect(original.recurrenceEnd?.occurrenceCount == 3, sourceLocation: sourceLocation)
  let reminder = EKReminder(eventStore: EKEventStore())
  reminder.addRecurrenceRule(original)

  try RemindersStore.replaceRecurrenceEnd(on: reminder, with: .count(6))

  let rules = try #require(reminder.recurrenceRules, sourceLocation: sourceLocation)
  #expect(rules.count == 1, sourceLocation: sourceLocation)
  let rebuilt = try #require(rules.first, sourceLocation: sourceLocation)
  #expect(RuleShape(rebuilt) == shape, sourceLocation: sourceLocation)
  #expect(rebuilt.recurrenceEnd?.occurrenceCount == 6, sourceLocation: sourceLocation)
}
