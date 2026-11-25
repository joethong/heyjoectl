import Foundation
import RemindCore

extension OutputRenderer {
  static func printReminderDetailStandard(_ reminder: ReminderItem) {
    printDetailIdentity(reminder)
    printDetailPrivateFields(reminder)
    printDetailSchedule(reminder)
    printDetailRepeatAndPlace(reminder)
    printDetailHistoryAndNotes(reminder)
  }

  private static func printDetailIdentity(_ reminder: ReminderItem) {
    Swift.print("ID: \(reminder.id)")
    Swift.print("Title: \(reminder.title)")
    Swift.print("List: \(reminder.listName)")
    Swift.print("Status: \(reminder.isCompleted ? "completed" : "open")")
    Swift.print("Priority: \(reminder.priority.rawValue)")
  }

  private static func printDetailPrivateFields(_ reminder: ReminderItem) {
    if reminder.flagged == true {
      Swift.print("Flagged: yes")
    }
    if reminder.urgent == true {
      Swift.print("Urgent: yes")
    }
    if let earlyReminder = reminder.earlyReminder {
      Swift.print("Early reminder: \(earlyReminder.displayString) before")
    }
    if let tags = reminder.tags, !tags.isEmpty {
      Swift.print("Tags: \(tags.map { "#\($0)" }.joined(separator: " "))")
    }
    if let parentID = reminder.parentID {
      Swift.print("Sub-task of: \(shortID(parentID))")
    }
    if let assignee = reminder.assignee {
      Swift.print("Assigned to: \(assignee.name ?? shortID(assignee.id))")
    }
    for link in reminder.links ?? [] {
      Swift.print("Link: \(link)")
    }
  }

  private static func printDetailSchedule(_ reminder: ReminderItem) {
    for line in startAndZoneLines(for: reminder) {
      Swift.print(line)
    }
    if let dueDate = reminder.dueDate {
      Swift.print("Due: \(DateParsing.formatDisplay(dueDate, isDateOnly: reminder.dueDateIsAllDay))")
    }
    if let alarmDate = reminder.alarmDate {
      Swift.print("Alarm: \(DateParsing.formatDisplay(alarmDate))")
    }
    for alarm in reminder.alarms ?? [] {
      if let text = relativeAlarmText(alarm) {
        Swift.print("Alarm: \(text)")
      }
    }
  }

  private static func printDetailRepeatAndPlace(_ reminder: ReminderItem) {
    if let recurrenceRule = reminder.recurrenceRule {
      Swift.print("Repeat: \(recurrenceRule.displayString)")
    }
    if let locationTrigger = reminder.locationTrigger {
      Swift.print(
        "Location: \(locationTrigger.address) (\(locationTrigger.proximity.rawValue), \(locationTrigger.radius)m)"
      )
    }
    if let url = reminder.url {
      Swift.print("URL: \(url.absoluteString)")
    }
  }

  private static func printDetailHistoryAndNotes(_ reminder: ReminderItem) {
    if let creationDate = reminder.creationDate {
      Swift.print("Created: \(DateParsing.formatDisplay(creationDate))")
    }
    if let lastModifiedDate = reminder.lastModifiedDate {
      Swift.print("Modified: \(DateParsing.formatDisplay(lastModifiedDate))")
    }
    if let completionDate = reminder.completionDate {
      Swift.print("Completed: \(DateParsing.formatDisplay(completionDate))")
    }
    if let notes = reminder.notes, !notes.isEmpty {
      Swift.print("Notes:")
      Swift.print(notes)
    }
  }

  static func startAndZoneLines(for reminder: ReminderItem) -> [String] {
    var lines: [String] = []
    if let startDate = reminder.startDate {
      lines.append("Start: \(DateParsing.formatDisplay(startDate, isDateOnly: reminder.startDateIsAllDay ?? false))")
    }
    if let timeZone = reminder.timeZone {
      lines.append("Time zone: \(timeZone)")
    }
    return lines
  }

  private static func relativeAlarmText(_ alarm: ReminderAlarm) -> String? {
    switch alarm {
    case .beforeDue(let seconds):
      return "\(durationText(seconds: seconds)) before due"
    case .afterDue(let seconds):
      return "\(durationText(seconds: seconds)) after due"
    case .date, .place:
      return nil
    }
  }

  private static func durationText(seconds: Int) -> String {
    let units = [("week", 604_800), ("day", 86_400), ("hour", 3600), ("minute", 60)]
    for (name, size) in units where seconds != 0 && seconds % size == 0 {
      let count = seconds / size
      return "\(count) \(name)\(count == 1 ? "" : "s")"
    }
    return "\(seconds) second\(seconds == 1 ? "" : "s")"
  }
}
