import EventKit
import Foundation
import Testing

@testable import RemindCore

@MainActor
struct DueAlarmMoveTests {
  private static func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
  }

  private static let utc = calendar("UTC")
  private static let newYork = calendar("America/New_York")

  private static let timed = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_082_200), isDateOnly: false)
  private static let nextTimed = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_168_600), isDateOnly: false)
  private static let allDay = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_048_000), isDateOnly: true)
  private static let nextAllDay = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_134_400), isDateOnly: true)
  private static let otherTime = Date(timeIntervalSince1970: 1_700_000_000)

  private func reminder(due: ParsedUserDate, calendar: Calendar = utc) throws -> EKReminder {
    let store = EKEventStore()
    let list = EKCalendar(for: .reminder, eventStore: store)
    list.title = "Synthetic list"
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = list
    reminder.title = "Synthetic"
    try RemindersStore.applyDueDate(.some(due), startUpdate: nil, to: reminder, calendar: calendar)
    return reminder
  }

  private func locationAlarm() -> EKAlarm {
    let alarm = EKAlarm()
    alarm.structuredLocation = EKStructuredLocation(title: "Home")
    alarm.proximity = .enter
    return alarm
  }

  private func absoluteDates(_ reminder: EKReminder) -> [Date] {
    (reminder.alarms ?? []).filter { $0.structuredLocation == nil }.compactMap(\.absoluteDate).sorted()
  }

  private func relativeOffsets(_ reminder: EKReminder) -> [TimeInterval] {
    (reminder.alarms ?? []).filter { $0.absoluteDate == nil && $0.structuredLocation == nil }
      .map(\.relativeOffset).sorted()
  }

  private func timedReminderWithOtherAlarms() throws -> EKReminder {
    let reminder = try reminder(due: Self.timed)
    reminder.addAlarm(EKAlarm(absoluteDate: Self.timed.date))
    reminder.addAlarm(EKAlarm(absoluteDate: Self.otherTime))
    reminder.addAlarm(locationAlarm())
    reminder.addAlarm(EKAlarm(relativeOffset: -900))
    reminder.addAlarm(EKAlarm(relativeOffset: 600))
    return reminder
  }

  private func expectOtherAlarmsKept(_ reminder: EKReminder) {
    #expect(relativeOffsets(reminder) == [-900, 600])
    #expect((reminder.alarms ?? []).compactMap(\.structuredLocation?.title) == ["Home"])
  }

  @Test("A new timed due date moves the alarm at the old due time and leaves the others")
  func timedToTimedMovesDueAlarm() throws {
    let reminder = try timedReminderWithOtherAlarms()

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(absoluteDates(reminder) == [Self.otherTime, Self.nextTimed.date])
    expectOtherAlarmsKept(reminder)
  }

  @Test("A due date in the reminder's own time zone moves its alarm when the Mac is in another zone")
  func zonedDueAlarmMoves() throws {
    let reminder = try reminder(due: Self.timed, calendar: Self.newYork)
    reminder.addAlarm(EKAlarm(absoluteDate: Self.timed.date))

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(absoluteDates(reminder) == [Self.nextTimed.date])
  }

  @Test("A floating due date matches its alarm in the Mac's time zone")
  func floatingDueAlarmMoves() throws {
    var macCalendar = Calendar(identifier: .gregorian)
    macCalendar.timeZone = .current
    let reminder = try reminder(due: Self.timed, calendar: macCalendar)
    reminder.timeZone = nil
    #expect(reminder.dueDateComponents?.timeZone == nil)
    reminder.addAlarm(EKAlarm(absoluteDate: Self.timed.date))

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: macCalendar)

    #expect(absoluteDates(reminder) == [Self.nextTimed.date])
  }

  @Test("An alarm made by --due now, with a fraction of a second, still moves")
  func fractionalDueAlarmMoves() throws {
    let reminder = try reminder(due: Self.timed)
    reminder.addAlarm(EKAlarm(absoluteDate: Self.timed.date.addingTimeInterval(0.4)))

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(absoluteDates(reminder) == [Self.nextTimed.date])
  }

  @Test("A new date-only due date removes the alarm at the old due time")
  func timedToDateOnlyRemovesDueAlarm() throws {
    let reminder = try timedReminderWithOtherAlarms()

    try RemindersStore.applyDueDate(.some(Self.nextAllDay), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(absoluteDates(reminder) == [Self.otherTime])
    expectOtherAlarmsKept(reminder)
  }

  @Test("--clear-due removes the alarm at the old due time")
  func clearDueRemovesDueAlarm() throws {
    let reminder = try timedReminderWithOtherAlarms()

    try RemindersStore.applyDueDate(.some(nil), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(absoluteDates(reminder) == [Self.otherTime])
    #expect(relativeOffsets(reminder) == [600])
    #expect((reminder.alarms ?? []).compactMap(\.structuredLocation?.title) == ["Home"])
  }

  @Test("--alarm in the same edit wins over the moved due alarm")
  func alarmInSameEditWins() throws {
    let reminder = try timedReminderWithOtherAlarms()
    let wanted = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_100_000), isDateOnly: false)

    try RemindersStore.applyDateChanges(
      ReminderUpdate(dueDate: .some(Self.nextTimed), alarmDate: .some(wanted)), to: reminder, calendar: Self.utc)

    #expect(absoluteDates(reminder) == [wanted.date])
    expectOtherAlarmsKept(reminder)
  }

  @Test("--alarm at the old due time, with a new --due, keeps the alarm where --alarm put it")
  func alarmAtOldDueTimeStays() throws {
    let reminder = try timedReminderWithOtherAlarms()

    try RemindersStore.applyDateChanges(
      ReminderUpdate(dueDate: .some(Self.nextTimed), alarmDate: .some(Self.timed)), to: reminder, calendar: Self.utc)

    #expect(absoluteDates(reminder) == [Self.timed.date])
    expectOtherAlarmsKept(reminder)
  }

  @Test("--clear-alarm in the same edit wins over the moved due alarm")
  func clearAlarmInSameEditWins() throws {
    let reminder = try timedReminderWithOtherAlarms()

    try RemindersStore.applyDateChanges(
      ReminderUpdate(dueDate: .some(Self.nextTimed), alarmDate: .some(nil)), to: reminder, calendar: Self.utc)

    #expect(absoluteDates(reminder).isEmpty)
    expectOtherAlarmsKept(reminder)
  }

  @Test("Alarms a second before or after the old due time stay")
  func nearbyAlarmsStay() throws {
    let reminder = try reminder(due: Self.timed)
    let nearby = [Self.timed.date.addingTimeInterval(-1), Self.timed.date.addingTimeInterval(1)]
    for date in nearby {
      reminder.addAlarm(EKAlarm(absoluteDate: date))
    }

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(absoluteDates(reminder) == nearby)
  }

  @Test("A date-only old due date moves no alarm")
  func dateOnlyOldDueMovesNothing() throws {
    let reminder = try reminder(due: Self.allDay)
    reminder.addAlarm(EKAlarm(absoluteDate: Self.allDay.date))

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(absoluteDates(reminder) == [Self.allDay.date])
  }

  @Test("Two alarms at the old due time both move")
  func twoDueAlarmsBothMove() throws {
    let reminder = try reminder(due: Self.timed)
    reminder.addAlarm(EKAlarm(absoluteDate: Self.timed.date))
    reminder.addAlarm(EKAlarm(absoluteDate: Self.timed.date))

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(absoluteDates(reminder) == [Self.nextTimed.date, Self.nextTimed.date])
  }
}
