import Commander
import Foundation
import RemindCore

enum CommandHelpers {
  static func parsePriority(_ value: String) throws -> ReminderPriority {
    switch value.lowercased() {
    case "none":
      return .none
    case "low":
      return .low
    case "medium", "med":
      return .medium
    case "high":
      return .high
    default:
      throw RemindCoreError.operationFailed("Invalid priority: \"\(value)\" (use none|low|medium|high)")
    }
  }

  static func parseDueDate(_ value: String) throws -> ParsedUserDate {
    try parseDueDate(value, now: Date(), calendar: .current)
  }

  static func parseDueDate(_ value: String, now: Date, calendar: Calendar) throws -> ParsedUserDate {
    try DateParsing.requireUserDate(value, now: now, calendar: calendar)
  }

  static func parseRecurrenceEnd(
    until: String?,
    count: String?,
    calendar: Calendar = .current,
    now: Date = Date()
  ) throws -> RecurrenceEnd? {
    if until != nil && count != nil {
      throw RemindCoreError.operationFailed("Use either --repeat-until or --repeat-count, not both")
    }
    if let until {
      let parsed = try DateParsing.requireUserDate(until, now: now, calendar: calendar)
      return .through(parsed, calendar: calendar)
    }
    if let count {
      guard let number = Int(count), number >= 1 else {
        throw RemindCoreError.operationFailed(
          "Invalid repeat count: \"\(count)\" (use a whole number of 1 or more)"
        )
      }
      return .count(number)
    }
    return nil
  }

  static func parseAlarmBefore(_ value: String) throws -> RelativeAlarmChange {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized == "none" {
      return .remove
    }
    let secondsPerUnit = ["m": 60, "h": 3600, "d": 86_400, "w": 604_800]
    let maxSeconds = 366 * 86_400
    let amountText = normalized.dropLast()
    guard
      let unit = normalized.last,
      let perUnit = secondsPerUnit[String(unit)],
      amountText.allSatisfy({ $0.isASCII && $0.isNumber }),
      let amount = Int(amountText), amount > 0,
      case (let seconds, false) = amount.multipliedReportingOverflow(by: perUnit),
      seconds <= maxSeconds
    else {
      throw RemindCoreError.operationFailed(
        "Invalid --alarm-before: \"\(value)\" "
          + "(use a whole number above 0 with m, h, d or w, up to 366 days, "
          + "such as 15m, 1h, 1d or 1w, or none)"
      )
    }
    return .set(beforeDueSeconds: seconds)
  }

  static func parseURL(_ value: String) throws -> URL {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      !trimmed.isEmpty,
      let url = URL(string: trimmed),
      let scheme = url.scheme,
      !scheme.isEmpty
    else {
      throw RemindCoreError.operationFailed("Invalid URL: \"\(value)\" (include a scheme like https://)")
    }
    return url
  }

  static func resolveShowIdentifiers(
    _ inputs: [String],
    in store: any ReminderCommandStore
  ) async throws -> [ReminderItem] {
    try await resolveShowIdentifiers(
      inputs,
      lookUp: { await store.reminderItem(withID: $0) },
      fetchAll: { try await store.reminders(in: nil) }
    )
  }

  static func resolveShowIdentifiers(
    _ inputs: [String],
    lookUp: @Sendable (String) async throws -> ReminderItem?,
    fetchAll: @Sendable () async throws -> [ReminderItem]
  ) async throws -> [ReminderItem] {
    if let direct = try await lookUpFullIDs(inputs, lookUp: lookUp) {
      return direct
    }
    let reminders = try await fetchAll()
    let defaultShowReminders = ReminderFiltering.apply(reminders, filter: .today)
    return try IDResolver.resolve(inputs, from: reminders, numericFrom: defaultShowReminders)
  }

  private static func lookUpFullIDs(
    _ inputs: [String],
    lookUp: (String) async throws -> ReminderItem?
  ) async throws -> [ReminderItem]? {
    let ids = inputs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
    guard !ids.isEmpty, ids.allSatisfy({ UUID(uuidString: $0) != nil }) else {
      return nil
    }
    var resolved: [ReminderItem] = []
    for id in ids {
      guard let item = try await lookUp(id), item.id.uppercased() == id else {
        return nil
      }
      if !resolved.contains(where: { $0.id == item.id }) {
        resolved.append(item)
      }
    }
    return resolved
  }

  static func listTarget(name: String?, id: String?) throws -> ReminderListTarget? {
    if let name, let id, !name.isEmpty, !id.isEmpty {
      throw RemindCoreError.operationFailed("Use either --list or --list-id, not both")
    }
    if let id, !id.isEmpty {
      return .id(id)
    }
    if let name, !name.isEmpty {
      return .name(name)
    }
    return nil
  }

  static func reminder(_ reminder: ReminderItem, matchesSearch query: String) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let haystack = [
      reminder.title,
      reminder.notes ?? "",
      reminder.url?.absoluteString ?? "",
    ].joined(separator: "\n")
    return haystack.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil
  }
}
