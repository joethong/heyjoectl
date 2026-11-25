import EventKit
import Foundation
import Testing

@testable import RemindCore

extension ReminderStaleEditTests {
  @Test("Leaving the due date unspecified changes neither date")
  func dueUnspecifiedChangesNothing() throws {
    let reminder = try reminder(due: Self.timed)
    let (due, start) = (reminder.dueDateComponents, reminder.startDateComponents)

    try RemindersStore.applyDueDate(nil, startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(reminder.dueDateComponents == due)
    #expect(reminder.startDateComponents == start)
  }

  static let liveAllDay = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_235_200), isDateOnly: true)
  static let liveNextAllDay = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_580_800), isDateOnly: true)
  static let liveTimed = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_267_600), isDateOnly: false)
  static let liveNextTimed = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_440_400), isDateOnly: false)

  func reminderWithEventKitDateOnlyCopy() throws -> EKReminder {
    let reminder = try reminder(due: Self.liveAllDay, calendar: Self.newYork)
    reminder.startDateComponents = DateComponents(year: 2026, month: 9, day: 1, hour: 0, minute: 0)
    return reminder
  }

  @Test("EventKit's timed midnight copy of a date-only due date moves to a new date-only due date")
  func eventKitCopyMovesToNewAllDay() throws {
    let reminder = try reminderWithEventKitDateOnlyCopy()

    try RemindersStore.applyDueDate(
      .some(Self.liveNextAllDay),
      startUpdate: nil,
      to: reminder,
      calendar: Self.newYork
    )

    let item = try item(reminder, calendar: Self.newYork)
    #expect(item.dueDate == Date(timeIntervalSince1970: 1_788_580_800))
    #expect(item.startDate == Date(timeIntervalSince1970: 1_788_580_800))
  }

  @Test("EventKit's timed midnight copy of a date-only due date moves to a new timed due date")
  func eventKitCopyMovesToNewTimed() throws {
    let reminder = try reminderWithEventKitDateOnlyCopy()

    try RemindersStore.applyDueDate(
      .some(Self.liveNextTimed),
      startUpdate: nil,
      to: reminder,
      calendar: Self.newYork
    )

    let item = try item(reminder, calendar: Self.newYork)
    #expect(item.dueDate == Date(timeIntervalSince1970: 1_788_440_400))
    #expect(item.startDate == Date(timeIntervalSince1970: 1_788_440_400))
    #expect(item.startDateIsAllDay == false)
  }

  @Test("A start date on the date-only due day at another time of day stays")
  func eventKitCopyLookalikeStays() throws {
    let reminder = try reminderWithEventKitDateOnlyCopy()
    reminder.startDateComponents = DateComponents(year: 2026, month: 9, day: 1, hour: 8, minute: 0)
    let start = reminder.startDateComponents

    try RemindersStore.applyDueDate(
      .some(Self.liveNextAllDay),
      startUpdate: nil,
      to: reminder,
      calendar: Self.newYork
    )

    #expect(reminder.startDateComponents == start)
  }

  @Test("Clearing a timed due date also clears the start date EventKit copied from it")
  func clearDueClearsTimedCopy() throws {
    let reminder = try reminder(due: Self.liveTimed, calendar: Self.newYork)
    #expect(try item(reminder, calendar: Self.newYork).startDate == Self.liveTimed.date)

    try RemindersStore.applyDueDate(.some(nil), startUpdate: nil, to: reminder, calendar: Self.newYork)

    let item = try item(reminder, calendar: Self.newYork)
    #expect(item.dueDate == nil)
    #expect(item.startDate == nil)
  }

  @Test("Clearing a date-only due date also clears the start date EventKit copied from it")
  func clearDueClearsDateOnlyCopy() throws {
    let reminder = try reminderWithEventKitDateOnlyCopy()

    try RemindersStore.applyDueDate(.some(nil), startUpdate: nil, to: reminder, calendar: Self.newYork)

    let item = try item(reminder, calendar: Self.newYork)
    #expect(item.dueDate == nil)
    #expect(item.startDate == nil)
  }

  @Test("Clearing the due date keeps a start date set on purpose, at the same instant")
  func clearDueKeepsDeliberateStart() throws {
    let reminder = try reminder(due: Self.liveTimed, calendar: Self.newYork)
    let earlier = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_267_600 - 90_000), isDateOnly: false)
    RemindersStore.applyStartDate(.some(earlier), to: reminder, calendar: Self.newYork)
    let start = reminder.startDateComponents

    try RemindersStore.applyDueDate(.some(nil), startUpdate: nil, to: reminder, calendar: Self.newYork)

    let item = try item(reminder, calendar: Self.newYork)
    #expect(reminder.startDateComponents == start)
    #expect(item.startDate == earlier.date)
    #expect(item.startDateIsAllDay == false)
  }

  @Test("Clearing a date-only due date keeps a date-only start set on purpose")
  func clearDueKeepsDeliberateDateOnlyStart() throws {
    let reminder = try reminderWithEventKitDateOnlyCopy()
    let earlier = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_235_200 - 86_400), isDateOnly: true)
    RemindersStore.applyStartDate(.some(earlier), to: reminder, calendar: Self.newYork)
    let start = reminder.startDateComponents

    try RemindersStore.applyDueDate(.some(nil), startUpdate: nil, to: reminder, calendar: Self.newYork)

    let item = try item(reminder, calendar: Self.newYork)
    #expect(reminder.startDateComponents == start)
    #expect(item.startDate == earlier.date)
    #expect(item.startDateIsAllDay == true)
  }

  @Test("Clearing the due date with a start date given in the same edit leaves the start update alone")
  func clearDueWithGivenStartLeavesStart() throws {
    let reminder = try reminder(due: Self.liveTimed, calendar: Self.newYork)
    let start = reminder.startDateComponents

    try RemindersStore.applyDueDate(
      .some(nil),
      startUpdate: .some(Self.liveAllDay),
      to: reminder,
      calendar: Self.newYork
    )

    #expect(reminder.startDateComponents == start)
  }

  func reminderWithZonedDateOnlyCopy() throws -> EKReminder {
    let reminder = try reminder(due: Self.liveAllDay, calendar: Self.newYork)
    reminder.startDateComponents = DateComponents(
      timeZone: TimeZone(identifier: "UTC"),
      year: 2026,
      month: 9,
      day: 1,
      hour: 0,
      minute: 0
    )
    return reminder
  }

  @Test("A midnight copy of a date-only due date in any time zone moves with a new due date")
  func zonedDateOnlyCopyMoves() throws {
    let reminder = try reminderWithZonedDateOnlyCopy()

    try RemindersStore.applyDueDate(
      .some(Self.liveNextAllDay),
      startUpdate: nil,
      to: reminder,
      calendar: Self.newYork
    )

    let item = try item(reminder, calendar: Self.newYork)
    #expect(item.startDate == Date(timeIntervalSince1970: 1_788_580_800))
  }

  @Test("Clearing a date-only due date clears a midnight copy in any time zone")
  func zonedDateOnlyCopyClears() throws {
    let reminder = try reminderWithZonedDateOnlyCopy()

    try RemindersStore.applyDueDate(.some(nil), startUpdate: nil, to: reminder, calendar: Self.newYork)

    #expect(reminder.startDateComponents == nil)
  }
}
