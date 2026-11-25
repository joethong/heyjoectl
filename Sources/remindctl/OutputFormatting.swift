import Foundation
import RemindCore

enum OutputFormat: Equatable {
  case standard
  case table
  case plain
  case json
  case quiet
}

struct ListSummary: Codable, Sendable, Equatable {
  let id: String
  let title: String
  let reminderCount: Int
  let overdueCount: Int
}

struct AuthorizationSummary: Codable, Sendable, Equatable {
  let status: String
  let authorized: Bool
}

enum OutputRenderer {
  static func printReminders(_ reminders: [ReminderItem], format: OutputFormat) {
    switch format {
    case .standard:
      printRemindersStandard(reminders)
    case .table:
      printRemindersTable(reminders)
    case .plain:
      printRemindersPlain(reminders)
    case .json:
      printJSON(reminders)
    case .quiet:
      Swift.print(reminders.count)
    }
  }

  static func printSearchResults(_ reminders: [ReminderItem], format: OutputFormat) {
    if format == .standard {
      printSearchResultsStandard(reminders)
    } else {
      printReminders(reminders, format: format)
    }
  }

  static func printReminder(_ reminder: ReminderItem, format: OutputFormat) {
    switch format {
    case .standard:
      Swift.print(confirmationLine(for: reminder))
    case .table:
      printRemindersTable([reminder])
    case .plain:
      Swift.print(plainLine(for: reminder))
    case .json:
      printJSON(reminder)
    case .quiet:
      break
    }
  }

  static func printReminderDetail(_ reminder: ReminderItem, format: OutputFormat) {
    switch format {
    case .standard, .table:
      printReminderDetailStandard(reminder)
    case .plain:
      Swift.print(plainLine(for: reminder))
    case .json:
      printJSON(reminder)
    case .quiet:
      Swift.print(reminder.id)
    }
  }

  static func printDeleteResult(_ count: Int, format: OutputFormat) {
    switch format {
    case .standard, .table:
      Swift.print("Deleted \(count) reminder(s)")
    case .plain:
      Swift.print("\(count)")
    case .json:
      printJSON(deletePayload(count))
    case .quiet:
      break
    }
  }

  static func printAuthorizationStatus(_ status: RemindersAuthorizationStatus, format: OutputFormat) {
    switch format {
    case .standard, .table:
      Swift.print("Reminders access: \(status.displayName)")
    case .plain:
      Swift.print(status.rawValue)
    case .json:
      printJSON(authorizationPayload(status))
    case .quiet:
      Swift.print(status.isAuthorized ? "1" : "0")
    }
  }

  static func deletePayload(_ count: Int) -> [String: Int] {
    ["deleted": count]
  }

  static func authorizationPayload(_ status: RemindersAuthorizationStatus) -> AuthorizationSummary {
    AuthorizationSummary(status: status.rawValue, authorized: status.isAuthorized)
  }

  private static func printRemindersStandard(_ reminders: [ReminderItem]) {
    let sorted = ReminderFiltering.sort(reminders)
    guard !sorted.isEmpty else {
      Swift.print("No reminders found")
      return
    }
    for (index, reminder) in sorted.enumerated() {
      Swift.print("[\(index + 1)] \(standardLine(for: reminder))")
    }
  }

  private static func printRemindersPlain(_ reminders: [ReminderItem]) {
    let sorted = ReminderFiltering.sort(reminders)
    for reminder in sorted {
      Swift.print(plainLine(for: reminder))
    }
  }

  private static func printRemindersTable(_ reminders: [ReminderItem]) {
    let sorted = ReminderFiltering.sort(reminders)
    guard !sorted.isEmpty else {
      Swift.print("No reminders found")
      return
    }
    Swift.print(["ID", "Status", "Due", "Priority", "List", "Title"].joined(separator: "\t"))
    for reminder in sorted {
      let due =
        reminder.dueDate.map {
          DateParsing.formatDisplay($0, isDateOnly: reminder.dueDateIsAllDay)
        } ?? ""
      Swift.print(
        [
          shortID(reminder.id),
          reminder.isCompleted ? "done" : "open",
          due,
          reminder.priority == .none ? "" : reminder.priority.rawValue,
          reminder.listName,
          reminder.title,
        ].joined(separator: "\t")
      )
    }
  }

  private static func printSearchResultsStandard(_ reminders: [ReminderItem]) {
    let sorted = ReminderFiltering.sort(reminders)
    guard !sorted.isEmpty else {
      Swift.print("No reminders found")
      return
    }
    for reminder in sorted {
      Swift.print("\(standardLine(for: reminder)) id=\(reminder.id)")
    }
  }

  static func confirmationLine(for reminder: ReminderItem) -> String {
    let due =
      reminder.dueDate.map {
        DateParsing.formatDisplay($0, isDateOnly: reminder.dueDateIsAllDay)
      } ?? "no due date"
    let recurrence = recurrenceSuffix(for: reminder)
    return "✓ \(reminder.title) [\(reminder.listName)] — \(due)\(recurrence)\(privateMarks(for: reminder))"
  }

  static func standardLine(for reminder: ReminderItem) -> String {
    let status = reminder.isCompleted ? "x" : " "
    let due =
      reminder.dueDate.map {
        DateParsing.formatDisplay($0, isDateOnly: reminder.dueDateIsAllDay)
      } ?? "no due date"
    let priority = reminder.priority == .none ? "" : " priority=\(reminder.priority.rawValue)"
    let recurrence = recurrenceSuffix(for: reminder)
    let marks = privateMarks(for: reminder)
    return "[\(status)] \(reminder.title) [\(reminder.listName)] — \(due)\(priority)\(recurrence)\(marks)"
  }

  static func plainLine(for reminder: ReminderItem) -> String {
    let due: String
    if let dueDate = reminder.dueDate {
      due =
        reminder.dueDateIsAllDay
        ? dateOnlyFormatter().string(from: dueDate)
        : isoFormatter().string(from: dueDate)
    } else {
      due = ""
    }
    return [
      reminder.id,
      reminder.listName,
      reminder.isCompleted ? "1" : "0",
      reminder.priority.rawValue,
      due,
      reminder.title,
    ].joined(separator: "\t")
  }

  static func renderJSON<T: Encodable>(_ payload: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    encoder.dateEncodingStrategy = .iso8601
    return String(bytes: try encoder.encode(payload), encoding: .utf8) ?? ""
  }

  static func printJSON<T: Encodable>(_ payload: T) {
    do {
      Swift.print(try renderJSON(payload))
    } catch {
      Swift.print("Failed to encode JSON: \(error)")
    }
  }

  private static func isoFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  private static func dateOnlyFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }

  private static func privateMarks(for reminder: ReminderItem) -> String {
    (reminder.flagged == true ? " [flagged]" : "") + (reminder.urgent == true ? " [urgent]" : "")
      + (reminder.earlyReminder.map { " [early: \($0.displayString)]" } ?? "")
      + (reminder.parentID.map { " [sub-task of \(shortID($0))]" } ?? "")
      + (reminder.assignee.map { " [assigned to \($0.name ?? shortID($0.id))]" } ?? "")
      + (reminder.tags ?? []).map { " #\($0)" }.joined()
      + (reminder.links == nil ? "" : " [link]")
  }

  private static func recurrenceSuffix(for reminder: ReminderItem) -> String {
    reminder.recurrenceRule.map { " repeat=\($0.displayString)" } ?? ""
  }

  static func shortID(_ id: String) -> String {
    String(id.prefix(8))
  }
}
