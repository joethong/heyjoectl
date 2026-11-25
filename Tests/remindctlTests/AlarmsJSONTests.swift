import Foundation
import RemindCore
import Testing

@testable import remindctl

@MainActor
struct AlarmsJSONTests {
  private func render(_ alarms: [ReminderAlarm]) throws -> String {
    try OutputRenderer.renderJSON(alarms)
  }

  @Test("A fixed-time alarm has kind and an ISO 8601 date")
  func dateAlarm() throws {
    let expected = """
      [
        {
          "date" : "2023-11-14T22:13:20Z",
          "kind" : "date"
        }
      ]
      """
    #expect(try render([.date(Date(timeIntervalSince1970: 1_700_000_000))]) == expected)
  }

  @Test("Relative alarms have kind and positive seconds")
  func relativeAlarms() throws {
    let expected = """
      [
        {
          "kind" : "beforeDue",
          "seconds" : 900
        },
        {
          "kind" : "afterDue",
          "seconds" : 60
        }
      ]
      """
    #expect(try render([.beforeDue(seconds: 900), .afterDue(seconds: 60)]) == expected)
  }

  @Test("A place alarm has title, coordinates, radius and proximity")
  func placeAlarm() throws {
    let trigger = LocationTrigger(
      address: "Home",
      latitude: 37.5,
      longitude: -122.25,
      radius: 150,
      proximity: .arriving
    )
    let expected = """
      [
        {
          "kind" : "place",
          "latitude" : 37.5,
          "longitude" : -122.25,
          "proximity" : "arriving",
          "radius" : 150,
          "title" : "Home"
        }
      ]
      """
    #expect(try render([.place(PlaceAlarm(trigger))]) == expected)
  }

  @Test("A place alarm without coordinates leaves them out")
  func placeAlarmWithoutCoordinates() throws {
    let expected = """
      [
        {
          "kind" : "place",
          "proximity" : "arriving",
          "radius" : 100,
          "title" : "Home"
        }
      ]
      """
    #expect(try render([.place(PlaceAlarm(LocationTrigger(address: "Home")))]) == expected)
  }

  @Test("A place alarm with an unknown proximity leaves proximity out")
  func placeAlarmWithoutProximity() throws {
    let expected = """
      [
        {
          "kind" : "place",
          "radius" : 75,
          "title" : "Work"
        }
      ]
      """
    #expect(try render([.place(PlaceAlarm(title: "Work", radius: 75, proximity: nil))]) == expected)
  }

  @Test("A reminder with alarms carries the new alarms key; one without has none")
  func itemKey() throws {
    let base = ReminderItem(
      id: "A1",
      title: "T",
      notes: nil,
      isCompleted: false,
      completionDate: nil,
      priority: .none,
      dueDate: nil,
      listID: "L1",
      listName: "Inbox"
    )
    let withAlarms = ReminderItem(
      id: "A1",
      title: "T",
      notes: nil,
      isCompleted: false,
      completionDate: nil,
      priority: .none,
      dueDate: nil,
      alarms: [.beforeDue(seconds: 900)],
      listID: "L1",
      listName: "Inbox"
    )
    #expect(!(try OutputRenderer.renderJSON(base)).contains("\"alarms\""))
    #expect(try OutputRenderer.renderJSON(withAlarms).contains("\"alarms\""))
  }

  @Test("Alarms decode back from their JSON")
  func roundTrip() throws {
    let alarms: [ReminderAlarm] = [
      .date(Date(timeIntervalSince1970: 1_700_000_000)),
      .beforeDue(seconds: 3600),
      .afterDue(seconds: 5),
      .place(PlaceAlarm(LocationTrigger(address: "Home", latitude: 1, longitude: 2, radius: 50, proximity: .leaving))),
      .place(PlaceAlarm(title: "Work", radius: 75, proximity: nil)),
    ]
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let json = try render(alarms)
    #expect(try decoder.decode([ReminderAlarm].self, from: Data(json.utf8)) == alarms)
  }
}
