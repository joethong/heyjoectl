import Testing

@testable import RemindCore
@testable import remindctl

@MainActor
struct RecurrenceOnParsingTests {
  private func parse(_ value: String) throws -> RecurrenceRule {
    try CommandHelpers.parseRecurrence(value)
  }

  private func days(_ names: RecurrenceWeekday...) -> [RecurrenceDay] {
    names.map { RecurrenceDay(day: $0) }
  }

  @Test("Weekdays after weekly")
  func weekdays() throws {
    #expect(try parse("weekly on mon,fri") == RecurrenceRule(frequency: .weekly, daysOfWeek: days(.mon, .fri)))
    #expect(
      try parse("every 2 weeks on tue")
        == RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: days(.tue)))
    #expect(
      try parse("biweekly on wed")
        == RecurrenceRule(frequency: .weekly, interval: 2, daysOfWeek: days(.wed)))
  }

  @Test("Full day names, spaces after commas and any case")
  func namesSpacesCase() throws {
    #expect(
      try parse("Weekly ON Monday, FRIDAY")
        == RecurrenceRule(frequency: .weekly, daysOfWeek: days(.mon, .fri)))
    #expect(
      try parse("  weekly on thursday , saturday  ")
        == RecurrenceRule(frequency: .weekly, daysOfWeek: days(.thu, .sat)))
    #expect(try parse("weekly on sunday") == RecurrenceRule(frequency: .weekly, daysOfWeek: days(.sun)))
  }

  @Test("Days of the month after monthly and yearly")
  func daysOfMonth() throws {
    #expect(try parse("monthly on 1,15") == RecurrenceRule(frequency: .monthly, daysOfMonth: [1, 15]))
    #expect(try parse("monthly on 1, 15") == RecurrenceRule(frequency: .monthly, daysOfMonth: [1, 15]))
    #expect(try parse("monthly on -1") == RecurrenceRule(frequency: .monthly, daysOfMonth: [-1]))
    #expect(
      try parse("every 3 months on 31, -31")
        == RecurrenceRule(frequency: .monthly, interval: 3, daysOfMonth: [31, -31]))
    #expect(try parse("yearly on 10") == RecurrenceRule(frequency: .yearly, daysOfMonth: [10]))
  }

  @Test("Nth and last weekday after monthly and yearly")
  func positions() throws {
    #expect(
      try parse("monthly on last fri")
        == RecurrenceRule(frequency: .monthly, daysOfWeek: [RecurrenceDay(day: .fri, week: -1)]))
    #expect(
      try parse("monthly on 2nd tue")
        == RecurrenceRule(frequency: .monthly, daysOfWeek: [RecurrenceDay(day: .tue, week: 2)]))
    #expect(
      try parse("yearly on 1st mon")
        == RecurrenceRule(frequency: .yearly, daysOfWeek: [RecurrenceDay(day: .mon, week: 1)]))
    #expect(
      try parse("Every 2 Months on 5th Sunday")
        == RecurrenceRule(
          frequency: .monthly, interval: 2, daysOfWeek: [RecurrenceDay(day: .sun, week: 5)]))
    #expect(
      try parse("monthly on 3rd wednesday")
        == RecurrenceRule(frequency: .monthly, daysOfWeek: [RecurrenceDay(day: .wed, week: 3)]))
    #expect(
      try parse("monthly on 4th thu")
        == RecurrenceRule(frequency: .monthly, daysOfWeek: [RecurrenceDay(day: .thu, week: 4)]))
  }

  @Test("Bad on parts fail with the accepted forms")
  func rejectBad() {
    let bad = [
      "monthly on mon",
      "yearly on mon,fri",
      "weekly on 1,15",
      "daily on 1",
      "daily on sat,sun",
      "every 3 days on mon",
      "monthly on -9223372036854775808",
      "monthly on 9223372036854775807",
      "monthly on 32",
      "monthly on -32",
      "monthly on 0",
      "monthly on 6th fri",
      "monthly on 0th fri",
      "monthly on last",
      "weekly on funday",
      "weekly on mon,funday",
      "weekly on",
      "weekly on ",
      "weekly on ,",
      "weekly on mon,",
      "weekly on mon fri",
      "weekly on last fri",
      "monthly on 1,fri",
      "monthly on 2nd tue,last fri",
      "every 0 weeks on mon",
      "on mon",
      "weekdaily on mon",
      "weekly on on mon",
    ]
    for value in bad {
      do {
        _ = try parse(value)
        Issue.record("Expected failure for \"\(value)\"")
      } catch {
        let message = error.localizedDescription
        #expect(message.contains("Invalid repeat value: \"\(value)\""), "\(value): \(message)")
        #expect(message.contains("weekly on mon,fri"), "\(value): \(message)")
        #expect(message.contains("monthly on last fri"), "\(value): \(message)")
        #expect(message.contains("monthly on 1,15"), "\(value): \(message)")
      }
    }
  }

  @Test("Existing phrases are unchanged")
  func existingPhrases() throws {
    #expect(try parse("annually") == RecurrenceRule(frequency: .yearly))
    #expect(try parse("every 1 days") == RecurrenceRule(frequency: .daily))
    #expect(try parse("daily").daysOfWeek.isEmpty)
  }

  @Test("Add and edit help show a weekday and a last-weekday repeat")
  func helpShowsExamples() {
    for spec in [AddCommand.spec, EditCommand.spec] {
      let help = HelpPrinter.renderCommand(rootName: "remindjoectl", spec: spec).joined(separator: "\n")
      #expect(help.contains("weekly on mon,fri"))
      #expect(help.contains("monthly on last fri"))
    }
  }
}
