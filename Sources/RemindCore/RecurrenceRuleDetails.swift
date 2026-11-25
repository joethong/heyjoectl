import EventKit
import Foundation

public enum RecurrenceWeekday: String, Codable, CaseIterable, Sendable {
  case mon, tue, wed, thu, fri, sat, sun

  var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

public struct RecurrenceDay: Codable, Sendable, Equatable {
  public let day: RecurrenceWeekday
  public let week: Int

  public init(day: RecurrenceWeekday, week: Int = 0) {
    self.day = day
    self.week = week
  }

  private enum CodingKeys: String, CodingKey {
    case day, week
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    day = try container.decode(RecurrenceWeekday.self, forKey: .day)
    week = try container.decodeIfPresent(Int.self, forKey: .week) ?? 0
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(day, forKey: .day)
    if week != 0 {
      try container.encode(week, forKey: .week)
    }
  }

  var words: String {
    week == 0 ? day.label : "the \(RecurrenceWords.ordinal(week)) \(day.label)"
  }
}

public enum RecurrenceEnd: Codable, Sendable, Equatable {
  case date(Date)
  case count(Int)

  private enum CodingKeys: String, CodingKey {
    case date, count
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if let date = try container.decodeIfPresent(Date.self, forKey: .date) {
      self = .date(date)
    } else {
      self = .count(try container.decode(Int.self, forKey: .count))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .date(let date):
      try container.encode(date, forKey: .date)
    case .count(let count):
      try container.encode(count, forKey: .count)
    }
  }

  /// A date-only end means "through that day", so it lands on the last second of that local day.
  public static func through(_ parsed: ParsedUserDate, calendar: Calendar = .current) -> RecurrenceEnd {
    guard parsed.isDateOnly else { return .date(parsed.date) }
    let start = calendar.startOfDay(for: parsed.date)
    let nextDay = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    return .date(calendar.startOfDay(for: nextDay).addingTimeInterval(-1))
  }

  var eventKitEnd: EKRecurrenceEnd {
    switch self {
    case .date(let date): EKRecurrenceEnd(end: date)
    case .count(let count): EKRecurrenceEnd(occurrenceCount: count)
    }
  }
}

enum RecurrenceWords {
  private static let monthNames = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
  ]

  static func ordinal(_ number: Int) -> String {
    if number == -1 { return "last" }
    let magnitude = abs(number)
    let suffix =
      switch (magnitude % 100, magnitude % 10) {
      case (11...13, _): "th"
      case (_, 1): "st"
      case (_, 2): "nd"
      case (_, 3): "rd"
      default: "th"
      }
    return "\(magnitude)\(suffix)" + (number < 0 ? " last" : "")
  }

  static func interval(frequency: RecurrenceFrequency, interval: Int) -> String {
    if interval == 1 {
      return frequency.rawValue
    }
    let unit =
      switch frequency {
      case .daily: "days"
      case .weekly: "weeks"
      case .monthly: "months"
      case .yearly: "years"
      }
    return "every \(interval) \(unit)"
  }

  static func daysOfWeek(_ days: [RecurrenceDay]) -> String? {
    days.isEmpty ? nil : "on " + days.map(\.words).joined(separator: ", ")
  }

  static func daysOfMonth(_ days: [Int]) -> String? {
    guard !days.isEmpty else { return nil }
    if days.count == 1, let only = days.first {
      return only < 0 ? "on the \(ordinal(only)) day" : "on day \(only)"
    }
    return "on days " + days.map { $0 < 0 ? ordinal($0) : String($0) }.joined(separator: ", ")
  }

  static func monthsOfYear(_ months: [Int]) -> String? {
    guard !months.isEmpty else { return nil }
    let names = months.map { (1...12).contains($0) ? monthNames[$0 - 1] : String($0) }
    return "in " + names.joined(separator: ", ")
  }

  static func setPositions(_ positions: [Int]) -> String? {
    guard !positions.isEmpty else { return nil }
    let label = positions.count == 1 ? "position" : "positions"
    return "at \(label) " + positions.map(String.init).joined(separator: ", ")
  }

  static func end(_ end: RecurrenceEnd?) -> String {
    switch end {
    case nil:
      return ""
    case .date(let date)?:
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.timeZone = TimeZone.current
      formatter.dateFormat = "d MMM yyyy"
      return " until \(formatter.string(from: date))"
    case .count(let count)?:
      return count == 1 ? ", 1 time" : ", \(count) times"
    }
  }
}

extension RecurrenceWeekday {
  init?(eventKitWeekday: EKWeekday) {
    switch eventKitWeekday {
    case .monday: self = .mon
    case .tuesday: self = .tue
    case .wednesday: self = .wed
    case .thursday: self = .thu
    case .friday: self = .fri
    case .saturday: self = .sat
    case .sunday: self = .sun
    @unknown default: return nil
    }
  }

  var eventKitWeekday: EKWeekday {
    switch self {
    case .mon: .monday
    case .tue: .tuesday
    case .wed: .wednesday
    case .thu: .thursday
    case .fri: .friday
    case .sat: .saturday
    case .sun: .sunday
    }
  }
}

extension RecurrenceRule {
  var eventKitRule: EKRecurrenceRule {
    EKRecurrenceRule(
      recurrenceWith: frequency.eventKitFrequency,
      interval: interval,
      daysOfTheWeek: daysOfWeek.isEmpty
        ? nil
        : daysOfWeek.map { EKRecurrenceDayOfWeek($0.day.eventKitWeekday, weekNumber: $0.week) },
      daysOfTheMonth: daysOfMonth.isEmpty ? nil : daysOfMonth.map(NSNumber.init(value:)),
      monthsOfTheYear: monthsOfYear.isEmpty ? nil : monthsOfYear.map(NSNumber.init(value:)),
      weeksOfTheYear: nil,
      daysOfTheYear: nil,
      setPositions: setPositions.isEmpty ? nil : setPositions.map(NSNumber.init(value:)),
      end: end?.eventKitEnd
    )
  }

  public func ending(_ end: RecurrenceEnd) -> RecurrenceRule {
    RecurrenceRule(
      frequency: frequency,
      interval: interval,
      daysOfWeek: daysOfWeek,
      daysOfMonth: daysOfMonth,
      monthsOfYear: monthsOfYear,
      setPositions: setPositions,
      end: end
    )
  }

  init?(eventKitRule rule: EKRecurrenceRule) {
    guard let frequency = RecurrenceFrequency(eventKitFrequency: rule.frequency) else { return nil }
    self.init(
      frequency: frequency,
      interval: rule.interval,
      daysOfWeek: (rule.daysOfTheWeek ?? []).compactMap { day in
        RecurrenceWeekday(eventKitWeekday: day.dayOfTheWeek).map {
          RecurrenceDay(day: $0, week: day.weekNumber)
        }
      },
      daysOfMonth: (rule.daysOfTheMonth ?? []).map(\.intValue),
      monthsOfYear: (rule.monthsOfTheYear ?? []).map(\.intValue),
      setPositions: (rule.setPositions ?? []).map(\.intValue),
      end: rule.recurrenceEnd.flatMap { end in
        if let date = end.endDate { return .date(date) }
        return end.occurrenceCount > 0 ? .count(end.occurrenceCount) : nil
      }
    )
  }
}
