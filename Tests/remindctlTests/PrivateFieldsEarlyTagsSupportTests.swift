import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

private struct StubReader: PrivateFieldsReader {
  let answer: PrivateFieldsRead

  func unavailableReason() -> String? { nil }

  func read(ids _: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead { answer }
}

@MainActor
struct PrivateFieldsEarlyTagsSupportTests {
  private static let reminder = ReminderItem(
    id: "A1",
    title: "Call bank",
    notes: nil,
    isCompleted: false,
    completionDate: nil,
    priority: .none,
    dueDate: nil,
    listID: "L1",
    listName: "Inbox"
  )

  private static func runtime(_ arguments: [String]) throws -> RuntimeOptions {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    return RuntimeOptions(parsedValues: invocation.parsedValues)
  }

  @Test("An unreadable Early Reminder prints one stderr note and keeps the rest")
  func unreadableNote() throws {
    let reader = StubReader(
      answer: .fields([
        "A1": PrivateReminderFields(flagged: true, urgent: false, tags: ["home"], earlyReminderUnreadable: true)
      ])
    )
    var notes: [String] = []

    let attached = PrivateFieldsSupport.attach(
      to: [Self.reminder],
      scope: .openOnly,
      runtime: try Self.runtime(["show", "open"]),
      reader: reader
    ) { notes.append($0) }

    #expect(notes == ["remindctl: 1 Early Reminder could not be read"])
    #expect(attached[0].flagged == true)
    #expect(attached[0].tags == ["home"])
    #expect(attached[0].earlyReminder == nil)
  }

  @Test("Several unreadable Early Reminders are one note with the count")
  func unreadablePlural() throws {
    let second = ReminderItem(
      id: "A2",
      title: "Pay rent",
      notes: nil,
      isCompleted: false,
      completionDate: nil,
      priority: .none,
      dueDate: nil,
      listID: "L1",
      listName: "Inbox"
    )
    let reader = StubReader(
      answer: .fields([
        "A1": PrivateReminderFields(tags: [], earlyReminderUnreadable: true),
        "A2": PrivateReminderFields(tags: [], earlyReminderUnreadable: true),
      ])
    )
    var notes: [String] = []

    _ = PrivateFieldsSupport.attach(
      to: [Self.reminder, second],
      scope: .openOnly,
      runtime: try Self.runtime(["show", "open"]),
      reader: reader
    ) { notes.append($0) }

    #expect(notes == ["remindctl: 2 Early Reminders could not be read"])
  }

  @Test("--no-private leaves tags and Early Reminder out of the JSON")
  func noPrivateKeysAbsent() throws {
    let reader = StubReader(
      answer: .fields([
        "A1": PrivateReminderFields(earlyReminder: EarlyReminder(count: 1, unit: .days), tags: ["home"])
      ])
    )

    let attached = PrivateFieldsSupport.attach(
      to: [Self.reminder],
      scope: .everything,
      runtime: try Self.runtime(["show", "all", "--json", "--no-private"]),
      reader: reader
    ) { _ in }
    let json = try OutputRenderer.renderJSON(attached[0])

    #expect(!json.contains("tags"))
    #expect(!json.contains("earlyReminder"))
  }

  @Test("JSON has tags and earlyReminder when known, tags as [] when none, and neither when unknown")
  func jsonKeys() throws {
    var known = Self.reminder
    known.earlyReminder = EarlyReminder(count: 1, unit: .days)
    known.tags = ["home", "work"]
    var none = Self.reminder
    none.tags = []

    let knownJSON = try OutputRenderer.renderJSON(known)
    let noneJSON = try OutputRenderer.renderJSON(none)
    let unknownJSON = try OutputRenderer.renderJSON(Self.reminder)

    #expect(knownJSON.contains("\"earlyReminder\" : {\n    \"count\" : 1,\n    \"unit\" : \"days\"\n  }"))
    #expect(knownJSON.contains("\"tags\" : [\n    \"home\",\n    \"work\"\n  ]"))
    #expect(noneJSON.contains("\"tags\" : [\n\n  ]"))
    #expect(!noneJSON.contains("earlyReminder"))
    #expect(!unknownJSON.contains("tags"))
    #expect(!unknownJSON.contains("earlyReminder"))
  }

  @Test("Standard lines mark tags and the Early Reminder")
  func standardMarks() {
    var both = Self.reminder
    both.flagged = true
    both.earlyReminder = EarlyReminder(count: 1, unit: .days)
    both.tags = ["home", "work"]
    var empty = Self.reminder
    empty.tags = []

    #expect(
      OutputRenderer.standardLine(for: both)
        == "[ ] Call bank [Inbox] — no due date [flagged] [early: 1 day] #home #work"
    )
    #expect(OutputRenderer.standardLine(for: empty) == "[ ] Call bank [Inbox] — no due date")
  }
}
