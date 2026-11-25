import Foundation
import RemindCore

extension AddCommand {
  static func parsedStartDate(startValue: String?, clearStart: Bool) throws -> ParsedUserDate?? {
    if startValue != nil && clearStart {
      throw RemindCoreError.operationFailed("Use either --start or --clear-start, not both")
    }
    if let startValue {
      return try CommandHelpers.parseDueDate(startValue)
    }
    return clearStart ? .some(nil) : nil
  }

  static func alarmBeforeSeconds(value: String?, hasDue: Bool) throws -> Int? {
    guard let value else { return nil }
    guard case .set(let seconds) = try CommandHelpers.parseAlarmBefore(value) else { return nil }
    guard hasDue else {
      throw RemindCoreError.operationFailed("--alarm-before needs a due date: add --due")
    }
    return seconds
  }

  static func recurrenceRule(repeatValue: String?, until: String?, count: String?) throws -> RecurrenceRule? {
    let end = try CommandHelpers.parseRecurrenceEnd(until: until, count: count)
    guard let repeatValue else {
      if end != nil {
        throw RemindCoreError.operationFailed("Use --repeat-until or --repeat-count together with --repeat")
      }
      return nil
    }
    let rule = try CommandHelpers.parseRecurrence(repeatValue)
    return end.map(rule.ending) ?? rule
  }

  static func makeLocationTrigger(
    location: String?,
    radius: String?,
    leaving: Bool
  ) throws -> LocationTrigger? {
    guard let location else {
      if radius != nil || leaving {
        throw RemindCoreError.operationFailed("Use --location with --radius or --leaving")
      }
      return nil
    }
    let radius = try radius.map(parseRadius) ?? 100
    return LocationTrigger(
      address: location,
      radius: radius,
      proximity: leaving ? .leaving : .arriving
    )
  }

  private static func parseRadius(_ value: String) throws -> Double {
    guard let radius = Double(value), radius.isFinite, radius > 0 else {
      throw RemindCoreError.operationFailed("Invalid radius: \"\(value)\"")
    }
    return radius
  }
}
