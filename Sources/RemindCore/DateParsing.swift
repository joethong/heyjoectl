import Foundation

public struct ParsedUserDate: Equatable, Sendable {
  public let date: Date
  public let isDateOnly: Bool

  public init(date: Date, isDateOnly: Bool) {
    self.date = date
    self.isDateOnly = isDateOnly
  }
}

public enum DateParsing {
  public static func parseUserDate(
    _ input: String,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> Date? {
    parseUserDateWithMetadata(input, now: now, calendar: calendar)?.date
  }

  /// Interprets local dates in the supplied calendar's time zone; explicit ISO offsets take precedence.
  public static func parseUserDateWithMetadata(
    _ input: String,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> ParsedUserDate? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = trimmed.lowercased()

    if let relative = parseRelativeDate(lower, now: now, calendar: calendar) {
      return relative
    }

    let absolute = trimmed.uppercased()
    for (pattern, format, isDateOnly) in absoluteFormats {
      // Select field order before parsing: DateFormatter can otherwise reinterpret day-first dates.
      guard absolute.range(of: "\\A\(pattern)\\z", options: .regularExpression) != nil else { continue }
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.calendar = Calendar(identifier: .gregorian)
      formatter.timeZone = calendar.timeZone
      formatter.dateFormat = format
      formatter.isLenient = false
      return formatter.date(from: absolute).map { ParsedUserDate(date: $0, isDateOnly: isDateOnly) }
    }

    return nil
  }

  public static func requireUserDate(
    _ input: String,
    now: Date = Date(),
    calendar: Calendar = .current
  ) throws -> ParsedUserDate {
    if let parsed = parseUserDateWithMetadata(input, now: now, calendar: calendar) { return parsed }
    if let day = clockChangeDay(input, now: now, calendar: calendar) {
      throw RemindCoreError.invalidDateClockChange(input, day: day)
    }
    throw RemindCoreError.invalidDate(input)
  }

  public static func clockChangeDay(
    _ input: String,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> String? {
    let lower = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard case .clockChange(let day) = parseDayReference(lower, now: now, calendar: calendar) else { return nil }
    return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
  }

  public static func formatDisplay(_ date: Date, isDateOnly: Bool = false, calendar: Calendar = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.timeZone = calendar.timeZone
    formatter.dateStyle = .medium
    formatter.timeStyle = isDateOnly ? .none : .short
    return formatter.string(from: date)
  }

  private static func parseRelativeDate(_ input: String, now: Date, calendar: Calendar) -> ParsedUserDate? {
    switch input {
    case "today":
      return ParsedUserDate(date: calendar.startOfDay(for: now), isDateOnly: true)
    case "tomorrow":
      return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
        .map { ParsedUserDate(date: $0, isDateOnly: true) }
    case "yesterday":
      return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now))
        .map { ParsedUserDate(date: $0, isDateOnly: true) }
    case "now":
      return ParsedUserDate(date: now, isDateOnly: false)
    default:
      guard case .parsed(let parsed) = parseDayReference(input, now: now, calendar: calendar) else { return nil }
      return parsed
    }
  }

  private enum DayParse {
    case parsed(ParsedUserDate)
    case clockChange(day: DateComponents)
    case invalid
  }

  private enum WeekdayScope {
    case next
    case this
  }

  private enum DayReference {
    case today
    case tomorrow
    case weekday(Int, WeekdayScope)
  }

  private static let weekdayNumbers: [String: Int] = {
    let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    return Dictionary(
      uniqueKeysWithValues: names.enumerated().flatMap { index, name in
        [(name, index + 1), (String(name.prefix(3)), index + 1)]
      })
  }()

  private static func parseDayReference(_ input: String, now: Date, calendar: Calendar) -> DayParse {
    var words = input.split(whereSeparator: \.isWhitespace).map(String.init)[...]
    guard let first = words.popFirst() else { return .invalid }

    let reference: DayReference
    switch first {
    case "today":
      reference = .today
    case "tomorrow":
      reference = .tomorrow
    case "next", "this":
      guard let name = words.popFirst(), let weekday = weekdayNumbers[name] else { return .invalid }
      reference = .weekday(weekday, first == "next" ? .next : .this)
    default:
      guard let weekday = weekdayNumbers[first] else { return .invalid }
      reference = .weekday(weekday, .next)
    }

    let clock: (hour: Int, minute: Int)?
    if words.isEmpty {
      clock = nil
    } else {
      guard let parsed = parseClock(words.joined(separator: " ")) else { return .invalid }
      clock = parsed
    }

    guard let resolved = resolve(reference, now: now, calendar: calendar) else { return .invalid }
    let dayFields: Set<Calendar.Component> = [.era, .year, .month, .day]
    var components = calendar.dateComponents(dayFields, from: resolved)
    let day = components
    if let clock {
      components.hour = clock.hour
      components.minute = clock.minute
    }
    guard let date = calendar.date(from: components) else { return .invalid }
    guard clock != nil else { return .parsed(ParsedUserDate(date: date, isDateOnly: true)) }
    guard calendar.dateComponents(dayFields, from: date) == day else { return .clockChange(day: day) }
    return .parsed(ParsedUserDate(date: date, isDateOnly: false))
  }

  private static func resolve(_ reference: DayReference, now: Date, calendar: Calendar) -> Date? {
    let startOfToday = calendar.startOfDay(for: now)
    switch reference {
    case .today:
      return startOfToday
    case .tomorrow:
      return calendar.date(byAdding: .day, value: 1, to: startOfToday)
    case .weekday(let target, .next):
      let ahead = (target - calendar.component(.weekday, from: now) + 7) % 7
      return calendar.date(byAdding: .day, value: ahead == 0 ? 7 : ahead, to: startOfToday)
    case .weekday(let target, .this):
      guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }
      let offset = (target - calendar.firstWeekday + 7) % 7
      guard
        let day = calendar.date(byAdding: .day, value: offset, to: weekStart),
        day >= startOfToday
      else { return nil }
      return day
    }
  }

  private static func parseClock(_ text: String) -> (hour: Int, minute: Int)? {
    var body = Substring(text)
    var isPM: Bool?
    if body.hasSuffix("am") || body.hasSuffix("pm") {
      isPM = body.hasSuffix("pm")
      body = body.dropLast(2)
      if body.last == " " { body = body.dropLast() }
    }

    let parts = body.split(separator: ":", omittingEmptySubsequences: false)
    guard
      (1...2).contains(parts.count),
      parts.allSatisfy({ $0.allSatisfy { ("0"..."9").contains($0) } }),
      (1...2).contains(parts[0].count),
      let hour = Int(parts[0])
    else { return nil }

    var minute = 0
    if parts.count == 2 {
      guard parts[1].count == 2, let value = Int(parts[1]), value < 60 else { return nil }
      minute = value
    } else if isPM == nil {
      return nil
    }

    guard let isPM else { return hour < 24 ? (hour, minute) : nil }
    return (1...12).contains(hour) ? (hour % 12 + (isPM ? 12 : 0), minute) : nil
  }

  private static var absoluteFormats: [(pattern: String, format: String, isDateOnly: Bool)] {
    let date = "[0-9]{4}[-/.][0-9]{1,2}[-/.][0-9]{1,2}"
    let time = "(?:[01]?[0-9]|2[0-3]):[0-5]?[0-9]"
    let seconds = "\(time):[0-5]?[0-9]"
    let zone = "(?:Z|[+-](?:[01][0-9]|2[0-3]):?[0-5][0-9])"
    return [
      ("\(date)T\(seconds)\\.[0-9]+\(zone)", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX", false),
      ("\(date)T\(seconds)\(zone)", "yyyy-MM-dd'T'HH:mm:ssXXXXX", false),
      ("\(date)T\(seconds)\\.[0-9]+", "yyyy-MM-dd'T'HH:mm:ss.SSSSSS", false),
      ("\(date)T\(seconds)", "yyyy-MM-dd'T'HH:mm:ss", false),
      ("\(date)T\(time)", "yyyy-MM-dd'T'HH:mm", false),
      (date, "yyyy-MM-dd", true),
      ("\(date) +\(time)", "yyyy-MM-dd HH:mm", false),
      ("\(date) +\(seconds)", "yyyy-MM-dd HH:mm:ss", false),
      ("[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}", "MM/dd/yyyy", true),
      ("[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} +\(time)", "MM/dd/yyyy HH:mm", false),
      ("[0-9]{1,2}-[0-9]{1,2}-[0-9]{2}", "dd-MM-yy", true),
      ("[0-9]{1,2}-[0-9]{1,2}-[0-9]{4}", "dd-MM-yyyy", true),
    ]
  }
}
