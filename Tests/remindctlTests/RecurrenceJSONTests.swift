import Foundation
import RemindCore
import Testing

@testable import remindctl

@MainActor
struct RecurrenceJSONTests {
  private func render(_ rule: RecurrenceRule) throws -> String {
    try OutputRenderer.renderJSON(rule)
  }

  @Test("A simple rule has exactly the 0.3.8 keys")
  func simpleRule() throws {
    let expected = """
      {
        "frequency" : "weekly",
        "interval" : 2
      }
      """
    #expect(try render(RecurrenceRule(frequency: .weekly, interval: 2)) == expected)
  }

  @Test("Weekdays leave out week when it is 0")
  func daysOfWeek() throws {
    let rule = RecurrenceRule(
      frequency: .monthly,
      daysOfWeek: [RecurrenceDay(day: .mon), RecurrenceDay(day: .fri, week: -1)]
    )
    let expected = """
      {
        "daysOfWeek" : [
          {
            "day" : "mon"
          },
          {
            "day" : "fri",
            "week" : -1
          }
        ],
        "frequency" : "monthly",
        "interval" : 1
      }
      """
    #expect(try render(rule) == expected)
  }

  @Test("Days of month, months and positions are int arrays")
  func intArrays() throws {
    let rule = RecurrenceRule(
      frequency: .yearly,
      daysOfMonth: [1, -1],
      monthsOfYear: [3, 9],
      setPositions: [1]
    )
    let expected = """
      {
        "daysOfMonth" : [
          1,
          -1
        ],
        "frequency" : "yearly",
        "interval" : 1,
        "monthsOfYear" : [
          3,
          9
        ],
        "setPositions" : [
          1
        ]
      }
      """
    #expect(try render(rule) == expected)
  }

  @Test("The end is a date or a count")
  func end() throws {
    let date = RecurrenceRule(frequency: .daily, end: .date(Date(timeIntervalSince1970: 1_700_000_000)))
    let dateExpected = """
      {
        "end" : {
          "date" : "2023-11-14T22:13:20Z"
        },
        "frequency" : "daily",
        "interval" : 1
      }
      """
    #expect(try render(date) == dateExpected)

    let count = RecurrenceRule(frequency: .daily, end: .count(5))
    let countExpected = """
      {
        "end" : {
          "count" : 5
        },
        "frequency" : "daily",
        "interval" : 1
      }
      """
    #expect(try render(count) == countExpected)
  }

  @Test("Rules decode back, and 0.3.8 JSON still decodes")
  func decoding() throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let old = Data(#"{"frequency":"weekly","interval":2}"#.utf8)
    #expect(try decoder.decode(RecurrenceRule.self, from: old) == RecurrenceRule(frequency: .weekly, interval: 2))

    let rule = RecurrenceRule(
      frequency: .monthly,
      interval: 3,
      daysOfWeek: [RecurrenceDay(day: .sat, week: 2), RecurrenceDay(day: .sun)],
      daysOfMonth: [5],
      monthsOfYear: [1],
      setPositions: [-1],
      end: .date(Date(timeIntervalSince1970: 1_700_000_000))
    )
    let json = Data(try render(rule).utf8)
    #expect(try decoder.decode(RecurrenceRule.self, from: json) == rule)
  }
}
