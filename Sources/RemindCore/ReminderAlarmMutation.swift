import EventKit
import Foundation

private struct ReminderAlarmReplacement {
  let alarmsToRemove: [EKAlarm]
  let alarmsToAdd: [EKAlarm]
}

enum ReminderAlarmMutation {
  static func replaceDateAlarms(on reminder: EKReminder, with date: Date?) {
    apply(replacingDateAlarms(in: reminder.alarms ?? [], with: date), to: reminder)
  }

  static func moveDueAlarms(on reminder: EKReminder, from oldDue: Date, to newDue: Date?) {
    let dueAlarms = (reminder.alarms ?? []).filter { $0.structuredLocation == nil && $0.absoluteDate == oldDue }
    apply(
      ReminderAlarmReplacement(
        alarmsToRemove: dueAlarms,
        alarmsToAdd: newDue.map { date in dueAlarms.map { _ in EKAlarm(absoluteDate: date) } } ?? []
      ), to: reminder)
  }

  static func replaceRelativeAlarms(on reminder: EKReminder, with change: RelativeAlarmChange) throws {
    let alarmsToAdd: [EKAlarm]
    switch change {
    case .set(let seconds):
      guard reminder.dueDateComponents != nil else {
        throw RemindCoreError.operationFailed(
          "--alarm-before needs a due date: add --due, or set one on the reminder first")
      }
      alarmsToAdd = [EKAlarm(relativeOffset: -TimeInterval(seconds))]
    case .remove:
      alarmsToAdd = []
    }
    apply(
      ReminderAlarmReplacement(
        alarmsToRemove: (reminder.alarms ?? []).filter(isBeforeDue),
        alarmsToAdd: alarmsToAdd
      ), to: reminder)
  }

  private static func isBeforeDue(_ alarm: EKAlarm) -> Bool {
    alarm.structuredLocation == nil && alarm.absoluteDate == nil && alarm.relativeOffset <= 0
  }

  private static func apply(_ replacement: ReminderAlarmReplacement, to reminder: EKReminder) {
    for alarm in replacement.alarmsToRemove {
      reminder.removeAlarm(alarm)
    }
    for alarm in replacement.alarmsToAdd {
      reminder.addAlarm(alarm)
    }
  }

  private static func replacingDateAlarms(in alarms: [EKAlarm], with date: Date?) -> ReminderAlarmReplacement {
    ReminderAlarmReplacement(
      alarmsToRemove: alarms.filter { $0.structuredLocation == nil && $0.absoluteDate != nil },
      alarmsToAdd: date.map { [EKAlarm(absoluteDate: $0)] } ?? []
    )
  }
}
