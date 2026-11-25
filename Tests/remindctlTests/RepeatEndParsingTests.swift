import Foundation
import Testing

@testable import RemindCore
@testable import remindctl

private let tokyo: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
  return calendar
}()

private func message(_ body: () throws -> Void) -> String? {
  do {
    try body()
    return nil
  } catch {
    return (error as? RemindCoreError)?.errorDescription
  }
}

@MainActor
struct RepeatEndParsingTests {
  @Test("No end flags gives no end")
  func noFlags() throws {
    #expect(try CommandHelpers.parseRecurrenceEnd(until: nil, count: nil) == nil)
  }

  @Test("A count gives a count end")
  func countOnly() throws {
    #expect(try CommandHelpers.parseRecurrenceEnd(until: nil, count: "5") == .count(5))
    #expect(try CommandHelpers.parseRecurrenceEnd(until: nil, count: "1") == .count(1))
  }

  @Test("A date-only until ends at the last second of that day in the local time zone")
  func untilDateOnly() throws {
    let end = try CommandHelpers.parseRecurrenceEnd(until: "2027-01-31", count: nil, calendar: tokyo)
    let expected = try #require(
      tokyo.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 23, minute: 59, second: 59)))
    #expect(end == .date(expected))
  }

  @Test("An until with a time is kept as given")
  func untilWithTime() throws {
    let end = try CommandHelpers.parseRecurrenceEnd(until: "2027-01-31 09:30", count: nil, calendar: tokyo)
    let expected = try #require(tokyo.date(from: DateComponents(year: 2027, month: 1, day: 31, hour: 9, minute: 30)))
    #expect(end == .date(expected))
  }

  @Test("Until and count together are an error")
  func untilAndCount() {
    #expect(
      message { _ = try CommandHelpers.parseRecurrenceEnd(until: "2027-01-31", count: "3") }
        == "Use either --repeat-until or --repeat-count, not both")
  }

  @Test("A count of 0, a negative count, a fraction or a word is an error", arguments: ["0", "-2", "1.5", "five", ""])
  func badCount(_ value: String) {
    #expect(
      message { _ = try CommandHelpers.parseRecurrenceEnd(until: nil, count: value) }
        == "Invalid repeat count: \"\(value)\" (use a whole number of 1 or more)")
  }

  @Test("A bad date is the same error as a bad due date")
  func badDate() {
    #expect(
      message { _ = try CommandHelpers.parseRecurrenceEnd(until: "someday", count: nil) }
        == RemindCoreError.invalidDate("someday").errorDescription)
  }

  @Test("Add: either flag alone is an error")
  func addNeedsRepeat() {
    let expected = "Use --repeat-until or --repeat-count together with --repeat"
    #expect(
      message { _ = try AddCommand.recurrenceRule(repeatValue: nil, until: "2027-01-31", count: nil) } == expected)
    #expect(message { _ = try AddCommand.recurrenceRule(repeatValue: nil, until: nil, count: "3") } == expected)
  }

  @Test("Add: no repeat and no end gives no rule")
  func addNothing() throws {
    #expect(try AddCommand.recurrenceRule(repeatValue: nil, until: nil, count: nil) == nil)
  }

  @Test("Add: a repeat without an end is unchanged")
  func addRepeatOnly() throws {
    #expect(
      try AddCommand.recurrenceRule(repeatValue: "weekly on mon,fri", until: nil, count: nil)
        == RecurrenceRule(
          frequency: .weekly, daysOfWeek: [RecurrenceDay(day: .mon), RecurrenceDay(day: .fri)]))
  }

  @Test("Add: repeat with a count sets the end")
  func addRepeatWithCount() throws {
    #expect(
      try AddCommand.recurrenceRule(repeatValue: "every 2 weeks", until: nil, count: "4")
        == RecurrenceRule(frequency: .weekly, interval: 2, end: .count(4)))
  }

  @Test("Add: repeat with an until date sets the end")
  func addRepeatWithUntil() throws {
    let rule = try #require(try AddCommand.recurrenceRule(repeatValue: "daily", until: "2027-01-31", count: nil))
    guard case .date = rule.end else {
      Issue.record("expected a date end")
      return
    }
    #expect(rule.frequency == .daily)
  }

  @Test("Add: until and count together are an error even with a repeat")
  func addClash() {
    #expect(
      message { _ = try AddCommand.recurrenceRule(repeatValue: "daily", until: "2027-01-31", count: "3") }
        == "Use either --repeat-until or --repeat-count, not both")
  }

  @Test("Add: a bad count is an error")
  func addBadCount() {
    #expect(message { _ = try AddCommand.recurrenceRule(repeatValue: "daily", until: nil, count: "0") } != nil)
  }

  @Test("Edit: no repeat flags changes nothing")
  func editNothing() throws {
    let update = try EditCommand.parsedRecurrenceUpdate(repeatValue: nil, noRepeat: false, until: nil, count: nil)
    #expect(update.rule == nil)
    #expect(update.end == nil)
  }

  @Test("Edit: repeat alone sets a new rule with no end")
  func editRepeatOnly() throws {
    let update = try EditCommand.parsedRecurrenceUpdate(repeatValue: "weekly", noRepeat: false, until: nil, count: nil)
    #expect(update.rule == .some(RecurrenceRule(frequency: .weekly)))
    #expect(update.end == nil)
  }

  @Test("Edit: repeat with a count gives the new rule the end")
  func editRepeatWithCount() throws {
    let update = try EditCommand.parsedRecurrenceUpdate(repeatValue: "weekly", noRepeat: false, until: nil, count: "3")
    #expect(update.rule == .some(RecurrenceRule(frequency: .weekly, end: .count(3))))
    #expect(update.end == nil)
  }

  @Test("Edit: a count alone changes only the end of the existing rule")
  func editCountAlone() throws {
    let update = try EditCommand.parsedRecurrenceUpdate(repeatValue: nil, noRepeat: false, until: nil, count: "7")
    #expect(update.rule == nil)
    #expect(update.end == .count(7))
  }

  @Test("Edit: an until date alone changes only the end of the existing rule")
  func editUntilAlone() throws {
    let update = try EditCommand.parsedRecurrenceUpdate(
      repeatValue: nil, noRepeat: false, until: "2027-01-31", count: nil)
    #expect(update.rule == nil)
    guard case .date? = update.end else {
      Issue.record("expected a date end")
      return
    }
  }

  @Test("Edit: until and count together are an error")
  func editClash() {
    #expect(
      message {
        _ = try EditCommand.parsedRecurrenceUpdate(
          repeatValue: nil, noRepeat: false, until: "2027-01-31", count: "3")
      } == "Use either --repeat-until or --repeat-count, not both")
  }

  @Test("Edit: --no-repeat with either flag is an error")
  func editNoRepeatClash() {
    let expected = "Use either --no-repeat or --repeat-until/--repeat-count, not both"
    #expect(
      message {
        _ = try EditCommand.parsedRecurrenceUpdate(repeatValue: nil, noRepeat: true, until: "2027-01-31", count: nil)
      } == expected)
    #expect(
      message {
        _ = try EditCommand.parsedRecurrenceUpdate(repeatValue: nil, noRepeat: true, until: nil, count: "3")
      } == expected)
  }

  @Test("Edit: --no-repeat alone still removes the repeat")
  func editNoRepeatAlone() throws {
    let update = try EditCommand.parsedRecurrenceUpdate(repeatValue: nil, noRepeat: true, until: nil, count: nil)
    #expect(update.rule == .some(nil))
    #expect(update.end == nil)
  }

  @Test("Edit: --repeat with --no-repeat is still the old error")
  func editRepeatNoRepeat() {
    #expect(
      message {
        _ = try EditCommand.parsedRecurrenceUpdate(repeatValue: "daily", noRepeat: true, until: nil, count: nil)
      } == "Use either --repeat or --no-repeat, not both")
  }

  @Test("Edit: a bad count is an error")
  func editBadCount() {
    #expect(
      message { _ = try EditCommand.parsedRecurrenceUpdate(repeatValue: nil, noRepeat: false, until: nil, count: "x") }
        != nil)
  }

  @Test("The router accepts both new options on add and edit", arguments: ["add", "edit"])
  func routerAcceptsOptions(_ command: String) throws {
    let invocation = try CommandRouter().program.resolve(arguments: [
      "remindjoectl", command, "Item", "--repeat", "weekly", "--repeat-until", "2027-01-31", "--repeat-count", "3",
    ])
    #expect(invocation.parsedValues.options["repeatUntil"] == ["2027-01-31"])
    #expect(invocation.parsedValues.options["repeatCount"] == ["3"])
  }
}
