import EventKit
import Foundation

extension RemindersStore {
  struct ReminderData: Sendable {
    let id: String
    let title: String
    let notes: String?
    let url: URL?
    let isCompleted: Bool
    let completionDate: Date?
    let creationDate: Date?
    let lastModifiedDate: Date?
    let priority: Int
    let dueDateComponents: DateComponents?
    let dueDateIsAllDay: Bool
    let startDateComponents: DateComponents?
    let startDateIsAllDay: Bool
    let timeZoneID: String?
    let externalID: String?
    let alarmDate: Date?
    let recurrenceRule: RecurrenceRule?
    let locationTrigger: LocationTrigger?
    let alarms: [ReminderAlarm]
    let listID: String
    let listName: String

    func item(calendar: Calendar) -> ReminderItem {
      let startDate = startDateComponents.flatMap { calendar.date(from: $0) }
      return ReminderItem(
        id: id,
        title: title,
        notes: notes,
        url: url,
        isCompleted: isCompleted,
        completionDate: completionDate,
        creationDate: creationDate,
        lastModifiedDate: lastModifiedDate,
        priority: ReminderPriority(eventKitValue: priority),
        dueDate: dueDateComponents.flatMap { calendar.date(from: $0) },
        dueDateIsAllDay: dueDateIsAllDay,
        startDate: startDate,
        startDateIsAllDay: startDate == nil ? nil : startDateIsAllDay,
        timeZone: timeZoneID,
        externalID: externalID.flatMap { $0.isEmpty ? nil : $0 },
        alarmDate: alarmDate,
        recurrenceRule: recurrenceRule,
        locationTrigger: locationTrigger,
        alarms: alarms.isEmpty ? nil : alarms,
        listID: listID,
        listName: listName
      )
    }
  }

  static func reminderItem(from reminder: EKReminder, calendar: Calendar = .current) throws -> ReminderItem {
    guard let data = reminderData(from: reminder) else {
      throw RemindCoreError.operationFailed("Reminder is missing a calendar")
    }
    return data.item(calendar: calendar)
  }

  static func reminderData(from reminder: EKReminder) -> ReminderData? {
    // Skip orphaned reminders before dereferencing EventKit's calendar IUO.
    guard let calendar = reminder.calendar else { return nil }
    let components = reminder.dueDateComponents
    let startComponents = reminder.startDateComponents
    return ReminderData(
      id: reminder.calendarItemIdentifier,
      title: reminder.title ?? "",
      notes: reminder.notes,
      url: reminder.url,
      isCompleted: reminder.isCompleted,
      completionDate: reminder.completionDate,
      creationDate: reminder.creationDate,
      lastModifiedDate: reminder.lastModifiedDate,
      priority: Int(reminder.priority),
      dueDateComponents: components,
      dueDateIsAllDay: isAllDay(components),
      startDateComponents: startComponents,
      startDateIsAllDay: isAllDay(startComponents),
      timeZoneID: reminder.timeZone?.identifier,
      externalID: reminder.calendarItemExternalIdentifier,
      alarmDate: alarmDate(from: reminder),
      recurrenceRule: recurrenceRule(from: reminder),
      locationTrigger: locationTrigger(from: reminder),
      alarms: ReminderAlarm.list(from: reminder),
      listID: calendar.calendarIdentifier,
      listName: calendar.title
    )
  }

  private static func alarmDate(from reminder: EKReminder) -> Date? {
    reminder.alarms?
      .compactMap(\.absoluteDate)
      .min()
  }

  private static func recurrenceRule(from reminder: EKReminder) -> RecurrenceRule? {
    guard let rule = reminder.recurrenceRules?.first else { return nil }
    return RecurrenceRule(eventKitRule: rule)
  }
}
