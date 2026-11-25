import CoreLocation
import EventKit
import Foundation

extension ReminderAlarm {
  private static let maxOffsetSeconds: TimeInterval = 1e12

  init(eventKitAlarm alarm: EKAlarm) {
    if let location = alarm.structuredLocation {
      let coordinate = location.geoLocation?.coordinate
      self = .place(
        PlaceAlarm(
          title: location.title ?? "",
          latitude: coordinate?.latitude,
          longitude: coordinate?.longitude,
          radius: location.radius,
          proximity: Self.proximity(of: alarm)
        ))
    } else if let date = alarm.absoluteDate {
      self = .date(date)
    } else {
      let clamped = min(max(alarm.relativeOffset, -Self.maxOffsetSeconds), Self.maxOffsetSeconds)
      let seconds = Int(clamped.rounded())
      self = seconds > 0 ? .afterDue(seconds: seconds) : .beforeDue(seconds: -seconds)
    }
  }

  static func list(from reminder: EKReminder) -> [ReminderAlarm] {
    (reminder.alarms ?? []).map(ReminderAlarm.init(eventKitAlarm:))
  }

  private static func proximity(of alarm: EKAlarm) -> LocationProximity? {
    switch alarm.proximity {
    case .enter:
      return .arriving
    case .leave:
      return .leaving
    default:
      return nil
    }
  }
}
