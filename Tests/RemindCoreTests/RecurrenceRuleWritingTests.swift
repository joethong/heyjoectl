import EventKit
import Foundation
import Testing

@testable import RemindCore

private let writingEndDate = Date(timeIntervalSince1970: 1_800_000_000)

private let writingRules: [(name: String, rule: RecurrenceRule)] = [
  ("daily", RecurrenceRule(frequency: .daily)),
  ("every 3 days", RecurrenceRule(frequency: .daily, interval: 3)),
  ("biweekly", RecurrenceRule(frequency: .weekly, interval: 2)),
  ("yearly", RecurrenceRule(frequency: .yearly)),
  (
    "weekly on mon,fri",
    RecurrenceRule(
      frequency: .weekly, daysOfWeek: [RecurrenceDay(day: .mon), RecurrenceDay(day: .fri)])
  ),
  (
    "every 2 weeks on sunday",
    RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: [RecurrenceDay(day: .sun)])
  ),
  ("monthly on 1,15", RecurrenceRule(frequency: .monthly, daysOfMonth: [1, 15])),
  ("monthly on -1", RecurrenceRule(frequency: .monthly, daysOfMonth: [-1])),
  (
    "monthly on last fri",
    RecurrenceRule(frequency: .monthly, daysOfWeek: [RecurrenceDay(day: .fri, week: -1)])
  ),
  (
    "monthly on 2nd tue",
    RecurrenceRule(frequency: .monthly, daysOfWeek: [RecurrenceDay(day: .tue, week: 2)])
  ),
  (
    "yearly on 1st mon",
    RecurrenceRule(frequency: .yearly, daysOfWeek: [RecurrenceDay(day: .mon, week: 1)])
  ),
  (
    "every 3 months on 5th sat",
    RecurrenceRule(
      frequency: .monthly, interval: 3, daysOfWeek: [RecurrenceDay(day: .sat, week: 5)])
  ),
  (
    "months of the year and positions",
    RecurrenceRule(
      frequency: .yearly,
      daysOfWeek: [RecurrenceDay(day: .thu)],
      monthsOfYear: [3, 9],
      setPositions: [-1]
    )
  ),
  ("ends on a date", RecurrenceRule(frequency: .weekly, end: .date(writingEndDate))),
  (
    "ends after a count",
    RecurrenceRule(frequency: .monthly, daysOfMonth: [1], end: .count(10))
  ),
]

@MainActor
struct RecurrenceRuleWritingTests {
  @Test("Each kind of rule survives the trip to EventKit and back", arguments: writingRules)
  func roundTrip(_ entry: (name: String, rule: RecurrenceRule)) throws {
    let eventKitRule = entry.rule.eventKitRule
    let back = try #require(RecurrenceRule(eventKitRule: eventKitRule))
    #expect(back == entry.rule, "\(entry.name)")
  }

  @Test("Empty parts are left unset on the EventKit rule")
  func emptyPartsUnset() {
    let eventKitRule = RecurrenceRule(frequency: .daily).eventKitRule
    #expect(eventKitRule.daysOfTheWeek == nil)
    #expect(eventKitRule.daysOfTheMonth == nil)
    #expect(eventKitRule.monthsOfTheYear == nil)
    #expect(eventKitRule.setPositions == nil)
    #expect(eventKitRule.recurrenceEnd == nil)
  }

  @Test("Weekdays map to the right EventKit days")
  func weekdayMapping() {
    let rule = RecurrenceRule(
      frequency: .weekly,
      daysOfWeek: RecurrenceWeekday.allCases.map { RecurrenceDay(day: $0) }
    )
    let mapped = rule.eventKitRule.daysOfTheWeek?.map(\.dayOfTheWeek)
    #expect(
      mapped == [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday])
  }

  @Test("Applying a rule to a reminder leaves exactly one rule", arguments: writingRules)
  func replacesExistingRule(_ entry: (name: String, rule: RecurrenceRule)) throws {
    let store = EKEventStore()
    let reminder = EKReminder(eventStore: store)
    reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil))
    reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .monthly, interval: 2, end: nil))

    RemindersStore.replaceRecurrence(on: reminder, with: entry.rule)

    let rules = try #require(reminder.recurrenceRules)
    #expect(rules.count == 1, "\(entry.name)")
    #expect(rules.first.flatMap(RecurrenceRule.init(eventKitRule:)) == entry.rule, "\(entry.name)")
  }

  @Test("Applying nil removes every rule")
  func removesRules() {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.addRecurrenceRule(EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil))
    RemindersStore.replaceRecurrence(on: reminder, with: nil)
    #expect((reminder.recurrenceRules ?? []).isEmpty)
  }
}
