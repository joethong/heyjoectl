import Foundation
import RemindCore
import Testing

@testable import remindctl

@MainActor
// swiftlint:disable:next type_body_length
struct JSONCompatibilityTests {
  private func expectJSON<T: Encodable>(
    _ payload: T,
    _ expected: String,
    sourceLocation: SourceLocation = #_sourceLocation
  ) throws {
    let actual = try OutputRenderer.renderJSON(payload)
    #expect(actual == expected, sourceLocation: sourceLocation)
  }

  private static func date(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSince1970: seconds)
  }

  private static let timed = ReminderItem(
    id: "A1",
    title: "Timed",
    notes: "Bring ID",
    url: URL(string: "https://example.com/a"),
    isCompleted: false,
    completionDate: nil,
    creationDate: date(1_700_000_000),
    lastModifiedDate: date(1_700_000_100),
    priority: .high,
    dueDate: date(1_700_003_600),
    listID: "L1",
    listName: "Inbox"
  )

  private static let dateOnly = ReminderItem(
    id: "A2",
    title: "Date only",
    notes: nil,
    isCompleted: false,
    completionDate: nil,
    priority: .none,
    dueDate: date(1_700_006_400),
    dueDateIsAllDay: true,
    listID: "L1",
    listName: "Inbox"
  )

  private static let noDueDate = ReminderItem(
    id: "A3",
    title: "No due",
    notes: nil,
    isCompleted: false,
    completionDate: nil,
    priority: .low,
    dueDate: nil,
    listID: "L1",
    listName: "Inbox"
  )

  private static let repeating = ReminderItem(
    id: "A4",
    title: "Repeats",
    notes: nil,
    isCompleted: false,
    completionDate: nil,
    priority: .medium,
    dueDate: date(1_700_003_600),
    recurrenceRule: RecurrenceRule(frequency: .weekly, interval: 2),
    listID: "L2",
    listName: "Home"
  )

  private static let alarm = ReminderItem(
    id: "A5",
    title: "Alarm",
    notes: nil,
    isCompleted: false,
    completionDate: nil,
    priority: .none,
    dueDate: date(1_700_003_600),
    alarmDate: date(1_700_003_000),
    listID: "L2",
    listName: "Home"
  )

  private static let place = ReminderItem(
    id: "A6",
    title: "Place",
    notes: nil,
    isCompleted: false,
    completionDate: nil,
    priority: .none,
    dueDate: nil,
    locationTrigger: LocationTrigger(
      address: "1 Apple Park Way",
      latitude: 37.3349,
      longitude: -122.009,
      radius: 150,
      proximity: .leaving
    ),
    listID: "L2",
    listName: "Home"
  )

  private static let placeWithoutCoordinates = ReminderItem(
    id: "A7",
    title: "Place",
    notes: nil,
    isCompleted: false,
    completionDate: nil,
    priority: .none,
    dueDate: nil,
    locationTrigger: LocationTrigger(address: "Home"),
    listID: "L2",
    listName: "Home"
  )

  private static let done = ReminderItem(
    id: "A8",
    title: "Done",
    notes: nil,
    isCompleted: true,
    completionDate: date(1_700_004_000),
    priority: .none,
    dueDate: date(1_700_003_600),
    listID: "L1",
    listName: "Inbox"
  )

  @Test("Timed reminder with notes, URL, and metadata")
  func timedReminder() throws {
    let expected = #"""
      {
        "creationDate" : "2023-11-14T22:13:20Z",
        "dueDate" : "2023-11-14T23:13:20Z",
        "dueDateIsAllDay" : false,
        "id" : "A1",
        "isCompleted" : false,
        "lastModifiedDate" : "2023-11-14T22:15:00Z",
        "listID" : "L1",
        "listName" : "Inbox",
        "notes" : "Bring ID",
        "priority" : "high",
        "title" : "Timed",
        "url" : "https:\/\/example.com\/a"
      }
      """#
    try expectJSON(Self.timed, expected)
  }

  @Test("Date-only due date")
  func dateOnlyReminder() throws {
    let expected = """
      {
        "dueDate" : "2023-11-15T00:00:00Z",
        "dueDateIsAllDay" : true,
        "id" : "A2",
        "isCompleted" : false,
        "listID" : "L1",
        "listName" : "Inbox",
        "priority" : "none",
        "title" : "Date only"
      }
      """
    try expectJSON(Self.dateOnly, expected)
  }

  @Test("No due date leaves every optional key out")
  func noDueDateReminder() throws {
    let expected = """
      {
        "dueDateIsAllDay" : false,
        "id" : "A3",
        "isCompleted" : false,
        "listID" : "L1",
        "listName" : "Inbox",
        "priority" : "low",
        "title" : "No due"
      }
      """
    try expectJSON(Self.noDueDate, expected)
  }

  @Test("Repeating reminder")
  func repeatingReminder() throws {
    let expected = """
      {
        "dueDate" : "2023-11-14T23:13:20Z",
        "dueDateIsAllDay" : false,
        "id" : "A4",
        "isCompleted" : false,
        "listID" : "L2",
        "listName" : "Home",
        "priority" : "medium",
        "recurrenceRule" : {
          "frequency" : "weekly",
          "interval" : 2
        },
        "title" : "Repeats"
      }
      """
    try expectJSON(Self.repeating, expected)
  }

  @Test("Reminder with an alarm")
  func alarmReminder() throws {
    let expected = """
      {
        "alarmDate" : "2023-11-14T23:03:20Z",
        "dueDate" : "2023-11-14T23:13:20Z",
        "dueDateIsAllDay" : false,
        "id" : "A5",
        "isCompleted" : false,
        "listID" : "L2",
        "listName" : "Home",
        "priority" : "none",
        "title" : "Alarm"
      }
      """
    try expectJSON(Self.alarm, expected)
  }

  @Test("Reminder with a place")
  func placeReminder() throws {
    let expected = """
      {
        "dueDateIsAllDay" : false,
        "id" : "A6",
        "isCompleted" : false,
        "listID" : "L2",
        "listName" : "Home",
        "locationTrigger" : {
          "address" : "1 Apple Park Way",
          "latitude" : 37.3349,
          "longitude" : -122.009,
          "proximity" : "leaving",
          "radius" : 150
        },
        "priority" : "none",
        "title" : "Place"
      }
      """
    try expectJSON(Self.place, expected)
  }

  @Test("A place without coordinates leaves latitude and longitude out")
  func placeWithoutCoordinates() throws {
    let expected = """
      {
        "dueDateIsAllDay" : false,
        "id" : "A7",
        "isCompleted" : false,
        "listID" : "L2",
        "listName" : "Home",
        "locationTrigger" : {
          "address" : "Home",
          "proximity" : "arriving",
          "radius" : 100
        },
        "priority" : "none",
        "title" : "Place"
      }
      """
    try expectJSON(Self.placeWithoutCoordinates, expected)
  }

  @Test("Completed reminder")
  func completedReminder() throws {
    let expected = """
      {
        "completionDate" : "2023-11-14T23:20:00Z",
        "dueDate" : "2023-11-14T23:13:20Z",
        "dueDateIsAllDay" : false,
        "id" : "A8",
        "isCompleted" : true,
        "listID" : "L1",
        "listName" : "Inbox",
        "priority" : "none",
        "title" : "Done"
      }
      """
    try expectJSON(Self.done, expected)
  }

  @Test("A list of reminders is a plain array in the given order")
  func reminderArray() throws {
    let expected = """
      [
        {
          "dueDate" : "2023-11-15T00:00:00Z",
          "dueDateIsAllDay" : true,
          "id" : "A2",
          "isCompleted" : false,
          "listID" : "L1",
          "listName" : "Inbox",
          "priority" : "none",
          "title" : "Date only"
        },
        {
          "dueDateIsAllDay" : false,
          "id" : "A3",
          "isCompleted" : false,
          "listID" : "L1",
          "listName" : "Inbox",
          "priority" : "low",
          "title" : "No due"
        }
      ]
      """
    try expectJSON([Self.dateOnly, Self.noDueDate], expected)
  }

  @Test("An empty list of reminders is an empty array")
  func emptyReminderArray() throws {
    try expectJSON([ReminderItem](), "[\n\n]")
  }

  @Test("Lists output")
  func listsOutput() throws {
    let summaries = [
      ListSummary(id: "L1", title: "Inbox", reminderCount: 3, overdueCount: 1),
      ListSummary(id: "L2", title: "Home", reminderCount: 0, overdueCount: 0),
    ]
    let expected = """
      [
        {
          "id" : "L1",
          "overdueCount" : 1,
          "reminderCount" : 3,
          "title" : "Inbox"
        },
        {
          "id" : "L2",
          "overdueCount" : 0,
          "reminderCount" : 0,
          "title" : "Home"
        }
      ]
      """
    try expectJSON(summaries, expected)
  }

  @Test("Delete result")
  func deleteResult() throws {
    let expected = """
      {
        "deleted" : 2
      }
      """
    try expectJSON(OutputRenderer.deletePayload(2), expected)
  }

  @Test(
    "Status output",
    arguments: [
      (RemindersAuthorizationStatus.notDetermined, "false", "not-determined"),
      (.restricted, "false", "restricted"),
      (.denied, "false", "denied"),
      (.writeOnly, "false", "write-only"),
      (.fullAccess, "true", "full-access"),
    ]
  )
  func statusOutput(status: RemindersAuthorizationStatus, authorized: String, name: String) throws {
    let expected = """
      {
        "authorized" : \(authorized),
        "status" : "\(name)"
      }
      """
    try expectJSON(OutputRenderer.authorizationPayload(status), expected)
  }
}
