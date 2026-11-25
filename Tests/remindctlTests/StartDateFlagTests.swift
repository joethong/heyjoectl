import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

@MainActor
struct StartDateFlagTests {
  private func resolve(_ arguments: [String]) throws -> ParsedValues {
    try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments).parsedValues
  }

  @Test("Edit parses --start like --due")
  func editStartIsParsed() throws {
    let timed = try EditCommand.parsedDateUpdates(
      dueValue: nil,
      clearDue: false,
      alarmValue: nil,
      clearAlarm: false,
      startValue: "2026-07-10 09:00",
      clearStart: false
    )
    let dateOnly = try EditCommand.parsedDateUpdates(
      dueValue: nil,
      clearDue: false,
      alarmValue: nil,
      clearAlarm: false,
      startValue: "2026-07-10",
      clearStart: false
    )

    #expect(timed.startDate != nil)
    #expect(timed.startDate!!.isDateOnly == false)
    #expect(dateOnly.startDate!!.isDateOnly)
    #expect(timed.dueDate == nil)
  }

  @Test("Edit --clear-start clears and leaving it out changes nothing")
  func editClearStart() throws {
    let cleared = try EditCommand.parsedDateUpdates(
      dueValue: nil,
      clearDue: false,
      alarmValue: nil,
      clearAlarm: false,
      startValue: nil,
      clearStart: true
    )
    let untouched = try EditCommand.parsedDateUpdates(
      dueValue: "2026-07-10",
      clearDue: false,
      alarmValue: nil,
      clearAlarm: false
    )

    #expect(cleared.startDate != nil)
    #expect(cleared.startDate! == nil)
    #expect(untouched.startDate == nil)
  }

  @Test("Edit rejects --start together with --clear-start")
  func editClash() {
    #expect(throws: RemindCoreError.operationFailed("Use either --start or --clear-start, not both")) {
      _ = try EditCommand.parsedDateUpdates(
        dueValue: nil,
        clearDue: false,
        alarmValue: nil,
        clearAlarm: false,
        startValue: "2026-07-10",
        clearStart: true
      )
    }
  }

  @Test("Edit rejects a start date it cannot read")
  func editInvalidStart() {
    #expect(throws: RemindCoreError.invalidDate("not a date")) {
      _ = try EditCommand.parsedDateUpdates(
        dueValue: nil,
        clearDue: false,
        alarmValue: nil,
        clearAlarm: false,
        startValue: "not a date",
        clearStart: false
      )
    }
  }

  @Test("Add parses --start and keeps --clear-start as a request for an empty start")
  func addStart() throws {
    let timed = try AddCommand.parsedStartDate(startValue: "2026-07-10 09:00", clearStart: false)
    let dateOnly = try AddCommand.parsedStartDate(startValue: "2026-07-10", clearStart: false)
    let cleared = try AddCommand.parsedStartDate(startValue: nil, clearStart: true)
    let untouched = try AddCommand.parsedStartDate(startValue: nil, clearStart: false)

    #expect(timed!!.isDateOnly == false)
    #expect(dateOnly!!.isDateOnly)
    #expect(cleared != nil)
    #expect(cleared! == nil)
    #expect(untouched == nil)
  }

  @Test("Add rejects --start together with --clear-start")
  func addClash() {
    #expect(throws: RemindCoreError.operationFailed("Use either --start or --clear-start, not both")) {
      _ = try AddCommand.parsedStartDate(startValue: "2026-07-10", clearStart: true)
    }
  }

  @Test("The command line carries --start and --clear-start to both commands")
  func commandLineWiring() throws {
    let add = try resolve(["add", "Title", "--start", "2026-07-10 09:00", "--clear-start"])
    #expect(add.option("start") == "2026-07-10 09:00")
    #expect(add.flag("clearStart"))

    let edit = try resolve(["edit", "1", "--start", "2026-07-10"])
    #expect(edit.option("start") == "2026-07-10")
    #expect(!edit.flag("clearStart"))

    let clear = try resolve(["edit", "1", "--clear-start"])
    #expect(clear.option("start") == nil)
    #expect(clear.flag("clearStart"))
  }

  @Test("Info shows the start date and time zone only when set")
  func infoLines() {
    func item(startDate: Date?, allDay: Bool?, timeZone: String?) -> ReminderItem {
      ReminderItem(
        id: "A1",
        title: "Synthetic",
        notes: nil,
        isCompleted: false,
        completionDate: nil,
        priority: .none,
        dueDate: nil,
        startDate: startDate,
        startDateIsAllDay: allDay,
        timeZone: timeZone,
        listID: "list",
        listName: "Inbox"
      )
    }
    let date = Date(timeIntervalSince1970: 1_788_082_200)

    #expect(OutputRenderer.startAndZoneLines(for: item(startDate: nil, allDay: nil, timeZone: nil)).isEmpty)
    #expect(
      OutputRenderer.startAndZoneLines(for: item(startDate: date, allDay: false, timeZone: nil))
        == ["Start: \(DateParsing.formatDisplay(date))"]
    )
    #expect(
      OutputRenderer.startAndZoneLines(for: item(startDate: date, allDay: true, timeZone: "America/New_York"))
        == ["Start: \(DateParsing.formatDisplay(date, isDateOnly: true))", "Time zone: America/New_York"]
    )
    #expect(
      OutputRenderer.startAndZoneLines(for: item(startDate: nil, allDay: nil, timeZone: "America/New_York"))
        == ["Time zone: America/New_York"]
    )
  }
}
