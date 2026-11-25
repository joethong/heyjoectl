import EventKit
import Foundation
import Testing

@testable import RemindCore

@MainActor
struct RecurrenceRuleDetailsTests {
  private static let endDate: Date = {
    var components = DateComponents()
    components.year = 2027
    components.month = 1
    components.day = 31
    components.hour = 12
    return Calendar.current.date(from: components)!
  }()

  private func snapshotRule(_ eventKitRule: EKRecurrenceRule?) throws -> RecurrenceRule? {
    let store = EKEventStore()
    let calendar = EKCalendar(for: .reminder, eventStore: store)
    calendar.title = "Synthetic list"
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = calendar
    reminder.title = "Repeats"
    if let eventKitRule {
      reminder.addRecurrenceRule(eventKitRule)
    }
    return try #require(RemindersStore.reminderData(from: reminder)).recurrenceRule
  }

  private func eventKitRule(
    _ frequency: EKRecurrenceFrequency,
    interval: Int = 1,
    daysOfTheWeek: [EKRecurrenceDayOfWeek]? = nil,
    daysOfTheMonth: [NSNumber]? = nil,
    monthsOfTheYear: [NSNumber]? = nil,
    setPositions: [NSNumber]? = nil,
    end: EKRecurrenceEnd? = nil
  ) -> EKRecurrenceRule {
    EKRecurrenceRule(
      recurrenceWith: frequency,
      interval: interval,
      daysOfTheWeek: daysOfTheWeek,
      daysOfTheMonth: daysOfTheMonth,
      monthsOfTheYear: monthsOfTheYear,
      weeksOfTheYear: nil,
      daysOfTheYear: nil,
      setPositions: setPositions,
      end: end
    )
  }

  @Test("A simple rule has no extra parts")
  func simpleRule() throws {
    let rule = try snapshotRule(eventKitRule(.weekly, interval: 2))
    #expect(rule == RecurrenceRule(frequency: .weekly, interval: 2))
  }

  @Test("A reminder without a rule has none")
  func noRule() throws {
    #expect(try snapshotRule(nil) == nil)
  }

  @Test("Weekdays are read in order")
  func weekdays() throws {
    let rule = try snapshotRule(
      eventKitRule(
        .weekly,
        daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.friday), EKRecurrenceDayOfWeek(.sunday)]
      ))
    #expect(
      rule?.daysOfWeek == [
        RecurrenceDay(day: .mon), RecurrenceDay(day: .fri), RecurrenceDay(day: .sun),
      ])
  }

  @Test("A weekday keeps its position in the month")
  func weekdayWithPosition() throws {
    let rule = try snapshotRule(
      eventKitRule(.monthly, daysOfTheWeek: [EKRecurrenceDayOfWeek(.tuesday, weekNumber: 2)]))
    #expect(rule?.daysOfWeek == [RecurrenceDay(day: .tue, week: 2)])
  }

  @Test("The last weekday of the month reads as week -1")
  func lastWeekday() throws {
    let rule = try snapshotRule(
      eventKitRule(.monthly, daysOfTheWeek: [EKRecurrenceDayOfWeek(.friday, weekNumber: -1)]))
    #expect(rule?.daysOfWeek == [RecurrenceDay(day: .fri, week: -1)])
  }

  @Test("Days of the month keep negative values")
  func daysOfMonth() throws {
    let rule = try snapshotRule(eventKitRule(.monthly, daysOfTheMonth: [1, 15, -1]))
    #expect(rule?.daysOfMonth == [1, 15, -1])
  }

  @Test("Months of the year")
  func monthsOfYear() throws {
    let rule = try snapshotRule(eventKitRule(.yearly, monthsOfTheYear: [3, 9]))
    #expect(rule?.monthsOfYear == [3, 9])
  }

  @Test("Set positions")
  func setPositions() throws {
    let rule = try snapshotRule(
      eventKitRule(
        .monthly,
        daysOfTheWeek: [EKRecurrenceDayOfWeek(.monday), EKRecurrenceDayOfWeek(.friday)],
        setPositions: [-1]
      ))
    #expect(rule?.setPositions == [-1])
    #expect(rule?.daysOfWeek == [RecurrenceDay(day: .mon), RecurrenceDay(day: .fri)])
  }

  @Test("An end date")
  func endDate() throws {
    let rule = try snapshotRule(eventKitRule(.daily, end: EKRecurrenceEnd(end: Self.endDate)))
    #expect(rule?.end == .date(Self.endDate))
  }

  @Test("An occurrence count")
  func endCount() throws {
    let rule = try snapshotRule(eventKitRule(.daily, end: EKRecurrenceEnd(occurrenceCount: 5)))
    #expect(rule?.end == .count(5))
  }

  @Test("A mix of parts")
  func mixedParts() throws {
    let rule = try snapshotRule(
      eventKitRule(
        .yearly,
        interval: 2,
        daysOfTheWeek: [EKRecurrenceDayOfWeek(.thursday, weekNumber: 4)],
        monthsOfTheYear: [11],
        end: EKRecurrenceEnd(occurrenceCount: 3)
      ))
    #expect(
      rule
        == RecurrenceRule(
          frequency: .yearly,
          interval: 2,
          daysOfWeek: [RecurrenceDay(day: .thu, week: 4)],
          monthsOfYear: [11],
          end: .count(3)
        ))
  }

  @Test("Rule parts reach the reminder item")
  func itemCarriesRule() throws {
    let store = EKEventStore()
    let calendar = EKCalendar(for: .reminder, eventStore: store)
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = calendar
    reminder.addRecurrenceRule(
      eventKitRule(.monthly, daysOfTheWeek: [EKRecurrenceDayOfWeek(.friday, weekNumber: -1)]))
    let item = try RemindersStore.reminderItem(from: reminder)
    #expect(item.recurrenceRule?.displayString == "monthly on the last Fri")
  }

  @Test("Whole rules in words")
  func words() {
    #expect(
      RecurrenceRule(
        frequency: .weekly,
        interval: 2,
        daysOfWeek: [RecurrenceDay(day: .mon), RecurrenceDay(day: .fri)],
        end: .date(Self.endDate)
      ).displayString == "every 2 weeks on Mon, Fri until 31 Jan 2027")
    #expect(
      RecurrenceRule(
        frequency: .monthly, daysOfWeek: [RecurrenceDay(day: .fri, week: -1)]
      ).displayString == "monthly on the last Fri")
    #expect(
      RecurrenceRule(frequency: .monthly, daysOfMonth: [1, 15]).displayString == "monthly on days 1, 15")
    #expect(RecurrenceRule(frequency: .daily, end: .count(5)).displayString == "daily, 5 times")
  }

  @Test("A simple rule reads as before")
  func simpleWords() {
    #expect(RecurrenceRule(frequency: .weekly).displayString == "weekly")
    #expect(RecurrenceRule(frequency: .weekly, interval: 2).displayString == "every 2 weeks")
  }

  @Test("Other parts in words")
  func otherWords() {
    #expect(RecurrenceRule(frequency: .monthly, daysOfMonth: [1]).displayString == "monthly on day 1")
    #expect(RecurrenceRule(frequency: .monthly, daysOfMonth: [-1]).displayString == "monthly on the last day")
    #expect(
      RecurrenceRule(frequency: .monthly, daysOfMonth: [1, -1]).displayString == "monthly on days 1, last")
    #expect(
      RecurrenceRule(frequency: .yearly, monthsOfYear: [3, 9]).displayString == "yearly in Mar, Sep")
    #expect(
      RecurrenceRule(
        frequency: .monthly,
        daysOfWeek: [RecurrenceDay(day: .mon), RecurrenceDay(day: .fri)],
        setPositions: [-1]
      ).displayString == "monthly on Mon, Fri at position -1")
    #expect(
      RecurrenceRule(
        frequency: .monthly,
        daysOfWeek: [RecurrenceDay(day: .tue, week: 2), RecurrenceDay(day: .wed, week: -2)]
      ).displayString == "monthly on the 2nd Tue, the 2nd last Wed")
    #expect(
      RecurrenceRule(
        frequency: .yearly,
        daysOfWeek: [RecurrenceDay(day: .sun, week: 11), RecurrenceDay(day: .sat, week: 3)]
      ).displayString == "yearly on the 11th Sun, the 3rd Sat")
    #expect(RecurrenceRule(frequency: .daily, end: .count(1)).displayString == "daily, 1 time")
  }
}
