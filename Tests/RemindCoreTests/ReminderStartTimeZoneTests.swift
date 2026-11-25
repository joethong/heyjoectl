import EventKit
import Foundation
import Testing

@testable import RemindCore

@MainActor
struct ReminderStartTimeZoneTests {
  private static var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private func makeReminder() -> EKReminder {
    let store = EKEventStore()
    let calendar = EKCalendar(for: .reminder, eventStore: store)
    calendar.title = "Synthetic list"
    let reminder = EKReminder(eventStore: store)
    reminder.calendar = calendar
    reminder.title = "Synthetic"
    return reminder
  }

  private func item(for reminder: EKReminder) throws -> ReminderItem {
    try RemindersStore.reminderItem(from: reminder, calendar: Self.utc)
  }

  @Test("A timed start date comes through with its time")
  func timedStartDate() throws {
    let reminder = makeReminder()
    reminder.startDateComponents = DateComponents(year: 2026, month: 8, day: 30, hour: 9, minute: 30)

    let item = try item(for: reminder)

    #expect(item.startDate == Date(timeIntervalSince1970: 1_788_082_200))
    #expect(item.startDateIsAllDay == false)
  }

  @Test("A date-only start date is marked all-day")
  func dateOnlyStartDate() throws {
    let reminder = makeReminder()
    reminder.startDateComponents = DateComponents(year: 2026, month: 8, day: 30)

    let item = try item(for: reminder)

    #expect(item.startDate == Date(timeIntervalSince1970: 1_788_048_000))
    #expect(item.startDateIsAllDay == true)
  }

  @Test("Without a start date both start fields are nil")
  func noStartDate() throws {
    let item = try item(for: makeReminder())

    #expect(item.startDate == nil)
    #expect(item.startDateIsAllDay == nil)
  }

  @Test("EventKit fills in the start date when only a due date is set")
  func dueDateAlsoFillsStart() throws {
    let reminder = makeReminder()
    reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 30)

    let item = try item(for: reminder)

    #expect(item.startDate == item.dueDate)
    #expect(item.startDateIsAllDay == true)
  }

  private func snapshot(timeZoneID: String? = nil, externalID: String? = nil) -> RemindersStore.ReminderData {
    RemindersStore.ReminderData(
      id: "local",
      title: "Synthetic",
      notes: nil,
      url: nil,
      isCompleted: false,
      completionDate: nil,
      creationDate: nil,
      lastModifiedDate: nil,
      priority: 0,
      dueDateComponents: nil,
      dueDateIsAllDay: false,
      startDateComponents: nil,
      startDateIsAllDay: false,
      timeZoneID: timeZoneID,
      externalID: externalID,
      alarmDate: nil,
      recurrenceRule: nil,
      locationTrigger: nil,
      alarms: [],
      listID: "list",
      listName: "Inbox"
    )
  }

  @Test("The snapshot item carries its time zone name and none when floating")
  func timeZone() {
    #expect(snapshot(timeZoneID: "America/New_York").item(calendar: Self.utc).timeZone == "America/New_York")
    #expect(snapshot(timeZoneID: nil).item(calendar: Self.utc).timeZone == nil)
  }

  @Test("A reminder whose date carries a time zone reports its IANA name")
  func zonedReminder() throws {
    let reminder = makeReminder()
    var due = DateComponents(year: 2026, month: 8, day: 30, hour: 9)
    due.timeZone = TimeZone(identifier: "America/New_York")
    reminder.dueDateComponents = due

    #expect(try item(for: reminder).timeZone == "America/New_York")
  }

  @Test("Setting a start date replaces the one EventKit copied from the due date")
  func applyStartDateSets() throws {
    let reminder = makeReminder()
    reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 30)
    let start = ParsedUserDate(date: Date(timeIntervalSince1970: 1_788_082_200), isDateOnly: false)

    RemindersStore.applyStartDate(.some(start), to: reminder, calendar: Self.utc)

    let item = try item(for: reminder)
    #expect(item.startDate == start.date)
    #expect(item.startDateIsAllDay == false)
    #expect(item.dueDate == Date(timeIntervalSince1970: 1_788_048_000))
  }

  @Test("Clearing the start date beats the copy EventKit makes from the due date")
  func applyStartDateClears() throws {
    let reminder = makeReminder()
    reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 30)
    try #require(reminder.startDateComponents != nil)

    RemindersStore.applyStartDate(.some(nil), to: reminder, calendar: Self.utc)

    let item = try item(for: reminder)
    #expect(item.startDate == nil)
    #expect(item.startDateIsAllDay == nil)
    #expect(item.dueDate == Date(timeIntervalSince1970: 1_788_048_000))
  }

  @Test("Leaving the start date unspecified changes nothing")
  func applyStartDateUnspecified() throws {
    let reminder = makeReminder()
    reminder.dueDateComponents = DateComponents(year: 2026, month: 8, day: 30)
    let before = reminder.startDateComponents

    RemindersStore.applyStartDate(nil, to: reminder, calendar: Self.utc)

    #expect(reminder.startDateComponents == before)
  }

  @Test("A new in-memory reminder is floating")
  func floatingReminder() throws {
    #expect(try item(for: makeReminder()).timeZone == nil)
  }

  @Test("The external id is carried from the snapshot and an empty one is dropped")
  func externalID() {
    #expect(snapshot(externalID: "ABC-123").item(calendar: Self.utc).externalID == "ABC-123")
    #expect(snapshot(externalID: "").item(calendar: Self.utc).externalID == nil)
    #expect(snapshot(externalID: nil).item(calendar: Self.utc).externalID == nil)
  }

  @Test("The snapshot reads the external id from EventKit and leaves the local id alone")
  func externalIDFromEventKit() throws {
    let reminder = makeReminder()
    let expected = try #require(reminder.calendarItemExternalIdentifier)

    let item = try item(for: reminder)

    #expect(item.externalID == expected)
    #expect(item.id == reminder.calendarItemIdentifier)
  }
}

struct ReminderStartTimeZoneCodingTests {
  private func json(_ item: ReminderItem) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return String(bytes: try encoder.encode(item), encoding: .utf8) ?? ""
  }

  private func bare(
    startDate: Date? = nil,
    startDateIsAllDay: Bool? = nil,
    timeZone: String? = nil,
    externalID: String? = nil
  ) -> ReminderItem {
    ReminderItem(
      id: "A1",
      title: "Synthetic",
      notes: nil,
      isCompleted: false,
      completionDate: nil,
      priority: .none,
      dueDate: nil,
      startDate: startDate,
      startDateIsAllDay: startDateIsAllDay,
      timeZone: timeZone,
      externalID: externalID,
      listID: "list",
      listName: "Inbox"
    )
  }

  @Test("The new keys are left out when empty")
  func emptyKeysAreOmitted() throws {
    let text = try json(bare())

    for key in ["startDate", "startDateIsAllDay", "timeZone", "externalID"] {
      #expect(!text.contains("\"\(key)\""))
    }
  }

  @Test("The new keys appear when set")
  func setKeysAppear() throws {
    let text = try json(
      bare(
        startDate: Date(timeIntervalSince1970: 1_788_082_200),
        startDateIsAllDay: false,
        timeZone: "America/New_York",
        externalID: "ABC-123"
      )
    )

    #expect(text.contains(#""startDate":"2026-08-30T09:30:00Z""#))
    #expect(text.contains(#""startDateIsAllDay":false"#))
    #expect(text.contains(#""timeZone":"America\/New_York""#))
    #expect(text.contains(#""externalID":"ABC-123""#))
  }
}
