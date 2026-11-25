import CoreLocation
import EventKit
import Foundation
import Testing

@testable import RemindCore

@MainActor
struct ReminderAlarmSnapshotTests {
  private func item(alarms: [EKAlarm]) throws -> ReminderItem {
    let store = EKEventStore()
    let calendar = EKCalendar(for: .reminder, eventStore: store)
    calendar.title = "Synthetic list"
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = calendar
    reminder.title = "Alarms"
    reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 30, hour: 9)
    for alarm in alarms {
      reminder.addAlarm(alarm)
    }
    return try RemindersStore.reminderItem(from: reminder)
  }

  private func makePlaceAlarm() -> EKAlarm {
    let location = EKStructuredLocation(title: "Home")
    location.geoLocation = CLLocation(latitude: 37.5, longitude: -122.25)
    location.radius = 150
    let alarm = EKAlarm()
    alarm.structuredLocation = location
    alarm.proximity = .leave
    return alarm
  }

  private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

  private var homeTrigger: LocationTrigger {
    LocationTrigger(address: "Home", latitude: 37.5, longitude: -122.25, radius: 150, proximity: .leaving)
  }

  @Test("A reminder with no alarms has no alarms list")
  func noAlarms() throws {
    #expect(try item(alarms: []).alarms == nil)
  }

  @Test("A fixed-time alarm is listed as a date")
  func fixedTimeAlarm() throws {
    #expect(try item(alarms: [EKAlarm(absoluteDate: fixedDate)]).alarms == [.date(fixedDate)])
  }

  @Test("A relative alarm before the due date is listed as beforeDue in positive seconds")
  func relativeAlarmBeforeDue() throws {
    #expect(try item(alarms: [EKAlarm(relativeOffset: -900)]).alarms == [.beforeDue(seconds: 900)])
  }

  @Test("A relative alarm after the due date is listed as afterDue")
  func relativeAlarmAfterDue() throws {
    #expect(try item(alarms: [EKAlarm(relativeOffset: 600)]).alarms == [.afterDue(seconds: 600)])
  }

  @Test("A place alarm is listed with the same values as locationTrigger")
  func placeAlarm() throws {
    let result = try item(alarms: [makePlaceAlarm()])
    #expect(result.alarms == [.place(PlaceAlarm(homeTrigger))])
    #expect(result.locationTrigger == homeTrigger)
  }

  @Test("All three kinds are listed, and the older fields stay as they were")
  func allThreeTogether() throws {
    let result = try item(alarms: [EKAlarm(relativeOffset: -3600), makePlaceAlarm(), EKAlarm(absoluteDate: fixedDate)])
    let alarms = try #require(result.alarms)
    #expect(alarms.count == 3)
    #expect(alarms.contains(.beforeDue(seconds: 3600)))
    #expect(alarms.contains(.place(PlaceAlarm(homeTrigger))))
    #expect(alarms.contains(.date(fixedDate)))
    #expect(result.alarmDate == fixedDate)
    #expect(result.locationTrigger == homeTrigger)
  }

  @Test("Alarms keep the order EventKit returns them in")
  func keepsEventKitOrder() throws {
    let store = EKEventStore()
    let calendar = EKCalendar(for: .reminder, eventStore: store)
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = calendar
    for alarm in [EKAlarm(relativeOffset: -3600), makePlaceAlarm(), EKAlarm(absoluteDate: fixedDate)] {
      reminder.addAlarm(alarm)
    }
    let eventKitOrder = (reminder.alarms ?? []).compactMap(ReminderAlarm.init(eventKitAlarm:))

    #expect(try RemindersStore.reminderItem(from: reminder).alarms == eventKitOrder)
  }

  @Test("A place alarm with no arriving or leaving setting is still listed, without a proximity")
  func placeAlarmWithoutProximity() throws {
    let alarm = EKAlarm()
    alarm.structuredLocation = EKStructuredLocation(title: "Home")
    let result = try item(alarms: [alarm])
    #expect(
      result.alarms == [.place(PlaceAlarm(title: "Home", latitude: nil, longitude: nil, radius: 0, proximity: nil))])
    #expect(result.locationTrigger == nil)
  }

  @Test("Extreme relative offsets are listed without crashing")
  func extremeOffsets() throws {
    let result = try item(alarms: [EKAlarm(relativeOffset: -1e19), EKAlarm(relativeOffset: 1e19)])
    let alarms = try #require(result.alarms)
    #expect(alarms.count == 2)
    #expect(alarms.contains(.beforeDue(seconds: 1_000_000_000_000)))
    #expect(alarms.contains(.afterDue(seconds: 1_000_000_000_000)))
  }

  @Test("Two fixed-time alarms are both listed while alarmDate keeps only the earliest")
  func twoFixedTimeAlarms() throws {
    let later = fixedDate.addingTimeInterval(600)
    let result = try item(alarms: [EKAlarm(absoluteDate: later), EKAlarm(absoluteDate: fixedDate)])
    let alarms = try #require(result.alarms)
    #expect(alarms.count == 2)
    #expect(alarms.contains(.date(later)))
    #expect(alarms.contains(.date(fixedDate)))
    #expect(result.alarmDate == fixedDate)
  }
}
