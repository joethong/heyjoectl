import EventKit
import Foundation
import Testing

@testable import RemindCore

@MainActor
struct ReminderAlarmMutationTests {
  @Test("Replacing an absolute alarm preserves relative and geofence alarms")
  func replaceAbsoluteAlarmPreservesIndependentAlarms() {
    let oldDate = Date(timeIntervalSince1970: 1_700_000_000)
    let newDate = Date(timeIntervalSince1970: 1_700_000_600)
    let timedAlarm = EKAlarm(absoluteDate: oldDate)
    let geofenceAlarm = locationAlarm()
    let relativeAlarm = EKAlarm(relativeOffset: -300)
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.addAlarm(timedAlarm)
    reminder.addAlarm(geofenceAlarm)
    reminder.addAlarm(relativeAlarm)

    ReminderAlarmMutation.replaceDateAlarms(on: reminder, with: newDate)

    let alarms = reminder.alarms ?? []
    #expect(alarms.count == 3)
    #expect(alarms.compactMap(\.absoluteDate) == [newDate])
    #expect(alarms.compactMap(\.structuredLocation?.title) == ["Home"])
    #expect(alarms.filter { $0.absoluteDate == nil && $0.structuredLocation == nil }.map(\.relativeOffset) == [-300])
  }

  @Test("Clearing an absolute alarm preserves relative and geofence alarms")
  func clearAbsoluteAlarmPreservesIndependentAlarms() {
    let timedAlarm = EKAlarm(absoluteDate: Date(timeIntervalSince1970: 1_700_000_000))
    let geofenceAlarm = locationAlarm()
    let relativeAlarm = EKAlarm(relativeOffset: -300)
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.addAlarm(timedAlarm)
    reminder.addAlarm(geofenceAlarm)
    reminder.addAlarm(relativeAlarm)

    ReminderAlarmMutation.replaceDateAlarms(on: reminder, with: nil)

    let alarms = reminder.alarms ?? []
    #expect(alarms.count == 2)
    #expect(alarms.compactMap(\.absoluteDate).isEmpty)
    #expect(alarms.compactMap(\.structuredLocation?.title) == ["Home"])
    #expect(alarms.filter { $0.absoluteDate == nil && $0.structuredLocation == nil }.map(\.relativeOffset) == [-300])
  }

  private func reminderWithEachKind(due: Bool = true) -> EKReminder {
    let reminder = EKReminder(eventStore: EKEventStore())
    if due {
      reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 30, hour: 9)
    }
    reminder.addAlarm(EKAlarm(absoluteDate: Date(timeIntervalSince1970: 1_700_000_000)))
    reminder.addAlarm(locationAlarm())
    reminder.addAlarm(EKAlarm(relativeOffset: -300))
    reminder.addAlarm(EKAlarm(relativeOffset: -7200))
    return reminder
  }

  private func relativeOffsets(_ reminder: EKReminder) -> [TimeInterval] {
    (reminder.alarms ?? []).filter { $0.absoluteDate == nil && $0.structuredLocation == nil }.map(\.relativeOffset)
  }

  @Test("Setting a before-due alarm replaces only the relative alarms")
  func setReplacesOnlyRelativeAlarms() throws {
    let reminder = reminderWithEachKind()

    try ReminderAlarmMutation.replaceRelativeAlarms(on: reminder, with: .set(beforeDueSeconds: 900))

    let alarms = reminder.alarms ?? []
    #expect(alarms.count == 3)
    #expect(relativeOffsets(reminder) == [-900])
    #expect(alarms.compactMap(\.absoluteDate) == [Date(timeIntervalSince1970: 1_700_000_000)])
    #expect(alarms.compactMap(\.structuredLocation?.title) == ["Home"])
  }

  @Test("Setting a before-due alarm on a reminder with no alarms adds one")
  func setAddsToEmpty() throws {
    let reminder = EKReminder(eventStore: EKEventStore())
    reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 30, hour: 9)

    try ReminderAlarmMutation.replaceRelativeAlarms(on: reminder, with: .set(beforeDueSeconds: 3600))

    #expect(relativeOffsets(reminder) == [-3600])
  }

  @Test("Removing relative alarms leaves fixed-time and place alarms")
  func removeKeepsOthers() throws {
    let reminder = reminderWithEachKind()

    try ReminderAlarmMutation.replaceRelativeAlarms(on: reminder, with: .remove)

    let alarms = reminder.alarms ?? []
    #expect(alarms.count == 2)
    #expect(relativeOffsets(reminder).isEmpty)
    #expect(alarms.compactMap(\.absoluteDate) == [Date(timeIntervalSince1970: 1_700_000_000)])
    #expect(alarms.compactMap(\.structuredLocation?.title) == ["Home"])
  }

  @Test("Removing relative alarms needs no due date")
  func removeWithoutDueDate() throws {
    let reminder = reminderWithEachKind(due: false)

    try ReminderAlarmMutation.replaceRelativeAlarms(on: reminder, with: .remove)

    #expect(relativeOffsets(reminder).isEmpty)
    #expect((reminder.alarms ?? []).count == 2)
  }

  @Test("Setting a before-due alarm without a due date throws and changes nothing")
  func setWithoutDueDateThrows() {
    let reminder = reminderWithEachKind(due: false)
    let before = reminder.alarms ?? []

    #expect(
      throws: RemindCoreError.operationFailed(
        "--alarm-before needs a due date: add --due, or set one on the reminder first")
    ) {
      try ReminderAlarmMutation.replaceRelativeAlarms(on: reminder, with: .set(beforeDueSeconds: 900))
    }

    #expect(reminder.alarms == before)
    #expect(relativeOffsets(reminder).sorted() == [-7200, -300])
  }

  private func locationAlarm() -> EKAlarm {
    let alarm = EKAlarm()
    alarm.structuredLocation = EKStructuredLocation(title: "Home")
    alarm.proximity = .enter
    return alarm
  }
}
