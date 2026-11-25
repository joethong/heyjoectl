import Foundation

public enum EarlyReminderUnit: String, Codable, Sendable, Equatable, CaseIterable {
  case minutes
  case hours
  case days
  case weeks
  case months

  init?(stored: Int) {
    switch stored {
    case 0: self = .minutes
    case 1: self = .hours
    case 2: self = .days
    case 3: self = .weeks
    case 4: self = .months
    default: return nil
    }
  }

  var stored: Int {
    switch self {
    case .minutes: 0
    case .hours: 1
    case .days: 2
    case .weeks: 3
    case .months: 4
    }
  }

  public var countInOneYear: Int {
    switch self {
    case .minutes: 525_600
    case .hours: 8760
    case .days: 366
    case .weeks: 52
    case .months: 12
    }
  }

  var singular: String { String(rawValue.dropLast()) }

  public var suffix: String {
    switch self {
    case .minutes: "m"
    case .hours: "h"
    case .days: "d"
    case .weeks: "w"
    case .months: "mo"
    }
  }

  public static var yearLimits: String {
    let limits = allCases.map { "\($0.countInOneYear)\($0.suffix)" }
    return limits.dropLast().joined(separator: ", ") + " or " + (limits.last ?? "")
  }
}

public struct EarlyReminder: Codable, Sendable, Equatable {
  public let count: Int
  public let unit: EarlyReminderUnit

  public init(count: Int, unit: EarlyReminderUnit) {
    self.count = count
    self.unit = unit
  }

  public var displayString: String {
    "\(count) \(count == 1 ? unit.singular : unit.rawValue)"
  }

  /// ReminderKit's unit number and count, which is negative for "before the due date".
  public var stored: (unit: Int, count: Int) {
    (unit.stored, -count)
  }

  /// ReminderKit stores "before the due date" as a negative count, so the count is negated.
  public static func parse(_ data: Data) throws -> EarlyReminder? {
    let stored = try JSONDecoder().decode(Stored.self, from: data)
    let alerts = stored.dueDateDeltaAlerts
    guard alerts.count <= 1 else { throw EarlyReminderError.alertCount(alerts.count) }
    guard let first = alerts.first else { return nil }
    guard let unit = EarlyReminderUnit(stored: first.dueDateDeltaUnit) else {
      throw EarlyReminderError.unknownUnit(first.dueDateDeltaUnit)
    }
    let (count, overflow) = 0.subtractingReportingOverflow(first.dueDateDeltaCount)
    guard !overflow else { throw EarlyReminderError.countOutOfRange(first.dueDateDeltaCount) }
    return EarlyReminder(count: count, unit: unit)
  }

  private struct Stored: Decodable {
    struct Alert: Decodable {
      let dueDateDeltaUnit: Int
      let dueDateDeltaCount: Int
    }

    let dueDateDeltaAlerts: [Alert]
  }
}

public enum EarlyReminderChange: Sendable, Equatable {
  case set(EarlyReminder)
  case remove
}

public enum EarlyReminderError: Error, Equatable {
  case unknownUnit(Int)
  case countOutOfRange(Int)
  case alertCount(Int)
}
