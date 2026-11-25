import EventKit
import Foundation
import Testing

@testable import RemindCore

@MainActor
struct ReminderStaleEditTests {
  static func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
  }

  static let utc = calendar("UTC")
  static let newYork = calendar("America/New_York")

  static let allDay = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_048_000), isDateOnly: true)
  static let nextAllDay = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_134_400), isDateOnly: true)
  static let timed = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_082_200), isDateOnly: false)
  static let nextTimed = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_168_600), isDateOnly: false)

  func makeReminder() -> EKReminder {
    let store = EKEventStore()
    let calendar = EKCalendar(for: .reminder, eventStore: store)
    calendar.title = "Synthetic list"
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = calendar
    reminder.title = "Synthetic"
    return reminder
  }

  func reminder(due: ParsedUserDate, calendar: Calendar = utc) throws -> EKReminder {
    let reminder = makeReminder()
    try RemindersStore.applyDueDate(.some(due), startUpdate: nil, to: reminder, calendar: calendar)
    return reminder
  }

  func item(_ reminder: EKReminder, calendar: Calendar = utc) throws -> ReminderItem {
    try RemindersStore.reminderItem(from: reminder, calendar: calendar)
  }

  func locationAlarm() -> EKAlarm {
    let alarm = EKAlarm()
    alarm.structuredLocation = EKStructuredLocation(title: "Home")
    alarm.proximity = .enter
    return alarm
  }

  func relativeOffsets(_ reminder: EKReminder) -> [TimeInterval] {
    (reminder.alarms ?? []).filter { $0.absoluteDate == nil && $0.structuredLocation == nil }
      .map(\.relativeOffset).sorted()
  }

  func reminderWithEveryAlarmKind() throws -> EKReminder {
    let reminder = try reminder(due: Self.timed)
    reminder.addAlarm(EKAlarm(absoluteDate: Date(timeIntervalSince1970: 1_700_000_000)))
    reminder.addAlarm(locationAlarm())
    reminder.addAlarm(EKAlarm(relativeOffset: -900))
    reminder.addAlarm(EKAlarm(relativeOffset: 0))
    reminder.addAlarm(EKAlarm(relativeOffset: 600))
    return reminder
  }

  @Test("--alarm-before replaces the before-due and at-due alarms and keeps the after-due one")
  func alarmBeforeKeepsAfterDue() throws {
    let reminder = try reminderWithEveryAlarmKind()

    try ReminderAlarmMutation.replaceRelativeAlarms(on: reminder, with: .set(beforeDueSeconds: 300))

    #expect(relativeOffsets(reminder) == [-300, 600])
    #expect((reminder.alarms ?? []).compactMap(\.absoluteDate) == [Date(timeIntervalSince1970: 1_700_000_000)])
    #expect((reminder.alarms ?? []).compactMap(\.structuredLocation?.title) == ["Home"])
  }

  @Test("--alarm-before none removes only the before-due and at-due alarms")
  func alarmBeforeNoneKeepsAfterDue() throws {
    let reminder = try reminderWithEveryAlarmKind()

    try ReminderAlarmMutation.replaceRelativeAlarms(on: reminder, with: .remove)

    #expect(relativeOffsets(reminder) == [600])
    #expect((reminder.alarms ?? []).count == 3)
  }

  @Test("Clearing the due date removes the before-due alarms and keeps date and place alarms")
  func clearDueRemovesBeforeDueAlarms() throws {
    let reminder = try reminderWithEveryAlarmKind()

    try RemindersStore.applyDueDate(.some(nil), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(reminder.dueDateComponents == nil)
    #expect(relativeOffsets(reminder) == [600])
    #expect((reminder.alarms ?? []).compactMap(\.absoluteDate) == [Date(timeIntervalSince1970: 1_700_000_000)])
    #expect((reminder.alarms ?? []).compactMap(\.structuredLocation?.title) == ["Home"])
  }

  @Test("Changing the due date moves only the alarm at the old due time")
  func changeDueMovesOnlyDueAlarm() throws {
    let reminder = try reminderWithEveryAlarmKind()
    reminder.addAlarm(EKAlarm(absoluteDate: Self.timed.date))

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(relativeOffsets(reminder) == [-900, 0, 600])
    #expect(
      (reminder.alarms ?? []).compactMap(\.absoluteDate).sorted()
        == [Date(timeIntervalSince1970: 1_700_000_000), Self.nextTimed.date]
    )
    #expect((reminder.alarms ?? []).count == 6)
  }

  @Test("A new all-day due date takes the copied start date with it")
  func allDayDueMovesCopiedStart() throws {
    let reminder = try reminder(due: Self.allDay)

    try RemindersStore.applyDueDate(.some(Self.nextAllDay), startUpdate: nil, to: reminder, calendar: Self.utc)

    let item = try item(reminder)
    #expect(item.dueDate == Self.nextAllDay.date)
    #expect(item.startDate == Self.nextAllDay.date)
    #expect(item.startDateIsAllDay == true)
  }

  @Test("A new timed due date takes the copied start date with it")
  func timedDueMovesCopiedStart() throws {
    let reminder = try reminder(due: Self.timed)

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: Self.utc)

    let item = try item(reminder)
    #expect(item.dueDate == Self.nextTimed.date)
    #expect(item.startDate == Self.nextTimed.date)
    #expect(item.startDateIsAllDay == false)
  }

  @Test("A timed due date in a named time zone takes the copied start date with it")
  func zonedDueMovesCopiedStart() throws {
    let reminder = try reminder(due: Self.timed, calendar: Self.newYork)

    try RemindersStore.applyDueDate(
      .some(Self.nextTimed),
      startUpdate: nil,
      to: reminder,
      calendar: Self.newYork
    )

    let item = try item(reminder, calendar: Self.newYork)
    #expect(item.dueDate == Self.nextTimed.date)
    #expect(item.startDate == Self.nextTimed.date)
    #expect(item.timeZone == "America/New_York")
  }

  @Test("Changing an all-day due date to a timed one moves the copied start date too")
  func allDayToTimedMovesCopiedStart() throws {
    let reminder = try reminder(due: Self.allDay)

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: Self.utc)

    let item = try item(reminder)
    #expect(item.startDate == Self.nextTimed.date)
    #expect(item.startDateIsAllDay == false)
  }

  @Test("A start date set on purpose stays when the due date changes")
  func deliberateStartStays() throws {
    let reminder = try reminder(due: Self.timed)
    RemindersStore.applyStartDate(
      .some(ParsedUserDate(date: Self.timed.date.addingTimeInterval(-86_400), isDateOnly: false)),
      to: reminder,
      calendar: Self.utc
    )
    let start = reminder.startDateComponents

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(reminder.startDateComponents == start)
    #expect(try item(reminder).startDate == Self.timed.date.addingTimeInterval(-86_400))
  }

  @Test(
    "A start date set on purpose that would end up after a new, earlier due date is refused before any change",
    arguments: [false, true]
  )
  func deliberateStartAfterNewDueRefused(allDay: Bool) throws {
    let due = allDay ? Self.allDay : Self.timed
    let newDue = due.date.addingTimeInterval(allDay ? -172_800 : -7200)
    let reminder = try reminder(due: due)
    RemindersStore.applyStartDate(
      .some(ParsedUserDate(date: due.date.addingTimeInterval(-3600), isDateOnly: false)),
      to: reminder,
      calendar: Self.utc
    )
    let (oldDue, oldStart) = (reminder.dueDateComponents, reminder.startDateComponents)

    #expect(
      throws: RemindCoreError.operationFailed(
        "The start date would be after the new due date; give an earlier --start, or --clear-start"
      )
    ) {
      try RemindersStore.applyDueDate(
        .some(ParsedUserDate(date: newDue, isDateOnly: due.isDateOnly)),
        startUpdate: nil,
        to: reminder,
        calendar: Self.utc
      )
    }
    #expect(reminder.dueDateComponents == oldDue)
    #expect(reminder.startDateComponents == oldStart)
  }

  @Test("A start date set on purpose on the new due day, or before it, stays")
  func deliberateStartOnNewDueDayStays() throws {
    let reminder = try reminder(due: Self.nextAllDay)
    RemindersStore.applyStartDate(
      .some(ParsedUserDate(date: Self.allDay.date.addingTimeInterval(3600), isDateOnly: false)),
      to: reminder,
      calendar: Self.utc
    )
    let start = reminder.startDateComponents

    try RemindersStore.applyDueDate(.some(Self.allDay), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(reminder.startDateComponents == start)
  }

  @Test("A start date on the same day as an all-day due date, but timed, stays")
  func sameDayDifferentTimeStays() throws {
    let reminder = try reminder(due: Self.allDay)
    RemindersStore.applyStartDate(
      .some(ParsedUserDate(date: Self.allDay.date.addingTimeInterval(3600), isDateOnly: false)),
      to: reminder,
      calendar: Self.utc
    )
    let start = reminder.startDateComponents

    try RemindersStore.applyDueDate(.some(Self.nextAllDay), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(reminder.startDateComponents == start)
  }

  @Test("A start date with the due date's clock time in another time zone stays")
  func otherZoneStartStays() throws {
    let reminder = try reminder(due: Self.timed)
    var start = reminder.startDateComponents
    start?.timeZone = TimeZone(identifier: "America/New_York")
    reminder.startDateComponents = start

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: nil, to: reminder, calendar: Self.utc)

    #expect(reminder.startDateComponents?.timeZone == TimeZone(identifier: "America/New_York"))
    #expect(reminder.startDateComponents?.day == 30)
  }

  @Test("A start date given with the new due date is left for the start update")
  func givenStartIsNotTouched() throws {
    let reminder = try reminder(due: Self.timed)
    let start = reminder.startDateComponents

    try RemindersStore.applyDueDate(
      .some(Self.nextTimed),
      startUpdate: .some(Self.allDay),
      to: reminder,
      calendar: Self.utc
    )

    #expect(reminder.startDateComponents == start)
  }

  @Test("A start date given with the new due date ends up as the one asked for")
  func givenStartWins() throws {
    let reminder = try reminder(due: Self.timed)
    let earlier = ParsedUserDate(date: Self.nextTimed.date.addingTimeInterval(-7200), isDateOnly: false)

    try RemindersStore.applyDueDate(
      .some(Self.nextTimed),
      startUpdate: .some(earlier),
      to: reminder,
      calendar: Self.utc
    )
    RemindersStore.applyStartDate(.some(earlier), to: reminder, calendar: Self.utc)

    let item = try item(reminder)
    #expect(item.dueDate == Self.nextTimed.date)
    #expect(item.startDate == earlier.date)
  }

  @Test("Clearing the start date with a new due date leaves the new due date and no start date")
  func clearedStartWithNewDue() throws {
    let reminder = try reminder(due: Self.timed)

    try RemindersStore.applyDueDate(.some(Self.nextTimed), startUpdate: .some(nil), to: reminder, calendar: Self.utc)
    RemindersStore.applyStartDate(.some(nil), to: reminder, calendar: Self.utc)

    let item = try item(reminder)
    #expect(item.dueDate == Self.nextTimed.date)
    #expect(item.startDate == nil)
    #expect(item.startDateIsAllDay == nil)
  }
}
