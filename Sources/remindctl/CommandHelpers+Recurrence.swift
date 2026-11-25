import Foundation
import RemindCore

extension CommandHelpers {
  static func parseRecurrence(_ value: String) throws -> RecurrenceRule {
    let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let words = normalized.split(separator: " ").map(String.init)
    guard let onIndex = words.firstIndex(of: "on") else {
      return try parseBaseRecurrence(normalized, original: value)
    }
    let base = try parseBaseRecurrence(words[..<onIndex].joined(separator: " "), original: value)
    return try applyingOn(words[(onIndex + 1)...], to: base, original: value)
  }

  private static func parseBaseRecurrence(_ normalized: String, original: String) throws -> RecurrenceRule {
    switch normalized {
    case "daily":
      return RecurrenceRule(frequency: .daily)
    case "weekly":
      return RecurrenceRule(frequency: .weekly)
    case "biweekly":
      return RecurrenceRule(frequency: .weekly, interval: 2)
    case "monthly":
      return RecurrenceRule(frequency: .monthly)
    case "yearly", "annually":
      return RecurrenceRule(frequency: .yearly)
    default:
      return try parseCustomRecurrence(normalized, original: original)
    }
  }

  private static let weekdayNames: [String: RecurrenceWeekday] = {
    let fullNames = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    var names: [String: RecurrenceWeekday] = [:]
    for (weekday, fullName) in zip(RecurrenceWeekday.allCases, fullNames) {
      names[weekday.rawValue] = weekday
      names[fullName] = weekday
    }
    return names
  }()

  private static let positionNames: [String: Int] = [
    "1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5, "last": -1,
  ]

  private static func applyingOn(
    _ words: ArraySlice<String>,
    to base: RecurrenceRule,
    original: String
  ) throws -> RecurrenceRule {
    let text = words.joined(separator: " ")
    let monthlyKinds: [RecurrenceFrequency] = [.monthly, .yearly]

    func rule(daysOfWeek: [RecurrenceDay] = [], daysOfMonth: [Int] = []) -> RecurrenceRule {
      RecurrenceRule(
        frequency: base.frequency,
        interval: base.interval,
        daysOfWeek: daysOfWeek,
        daysOfMonth: daysOfMonth
      )
    }

    if !text.contains(","), words.count == 2 {
      guard
        monthlyKinds.contains(base.frequency),
        let week = positionNames[words[words.startIndex]],
        let day = weekdayNames[words[words.startIndex + 1]]
      else { throw invalidRecurrence(original) }
      return rule(daysOfWeek: [RecurrenceDay(day: day, week: week)])
    }

    let items = text.split(separator: ",", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
    guard !items.contains(where: \.isEmpty) else { throw invalidRecurrence(original) }

    let weekdays = items.compactMap { weekdayNames[$0] }
    if weekdays.count == items.count {
      guard base.frequency == .weekly else { throw invalidRecurrence(original) }
      return rule(daysOfWeek: weekdays.map { RecurrenceDay(day: $0) })
    }

    let monthDays = items.compactMap(Int.init)
    guard
      monthDays.count == items.count,
      monthlyKinds.contains(base.frequency),
      monthDays.allSatisfy({ (1...31).contains($0) || (-31 ... -1).contains($0) })
    else { throw invalidRecurrence(original) }
    return rule(daysOfMonth: monthDays)
  }

  private static func parseCustomRecurrence(_ normalized: String, original: String) throws -> RecurrenceRule {
    let parts = normalized.split(separator: " ")
    guard parts.count == 3, parts[0] == "every", let interval = Int(parts[1]), interval > 0 else {
      throw invalidRecurrence(original)
    }

    let frequency: RecurrenceFrequency
    switch parts[2] {
    case "day", "days":
      frequency = .daily
    case "week", "weeks":
      frequency = .weekly
    case "month", "months":
      frequency = .monthly
    case "year", "years":
      frequency = .yearly
    default:
      throw invalidRecurrence(original)
    }
    return RecurrenceRule(frequency: frequency, interval: interval)
  }

  private static func invalidRecurrence(_ value: String) -> RemindCoreError {
    RemindCoreError.operationFailed(
      """
      Invalid repeat value: "\(value)" \
      (use daily|weekly|biweekly|monthly|yearly or "every N days/weeks/months/years"; \
      add "on mon,fri" to weekly, as in "weekly on mon,fri"; \
      add "on 1,15" (days 1 to 31 or -1 to -31) to monthly or yearly, as in "monthly on 1,15" or "monthly on -1"; \
      add "on last fri" (1st to 5th or last) to monthly or yearly, as in "monthly on last fri" or "monthly on 2nd tue")
      """
    )
  }
}
