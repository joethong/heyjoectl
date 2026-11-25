import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

final class ClearDueWriter: PrivateFieldsWriter, @unchecked Sendable {
  private let lock = NSLock()
  private let unavailable: String?
  private var results: [PrivateFieldsWriteResult]
  private var recorded: [PrivateFieldsChange] = []

  init(unavailable: String? = nil, results: [PrivateFieldsWriteResult] = [.saved]) {
    self.unavailable = unavailable
    self.results = results
  }

  var writes: [PrivateFieldsChange] { lock.withLock { recorded } }

  func unavailableReason(for change: PrivateFieldsChange) -> String? {
    unavailable
  }

  func write(_ change: PrivateFieldsChange, id: String) -> PrivateFieldsWriteResult {
    lock.withLock {
      recorded.append(change)
      return results.count > 1 ? results.removeFirst() : results[0]
    }
  }
}

final class ClearDueReader: PrivateFieldsReader, @unchecked Sendable {
  private let lock = NSLock()
  private var answers: [PrivateFieldsRead]
  private let unavailable: String?
  private var asked: [Set<String>] = []

  init(_ answers: [PrivateFieldsRead], unavailable: String? = nil) {
    self.answers = answers
    self.unavailable = unavailable
  }

  var reads: [Set<String>] { lock.withLock { asked } }

  func unavailableReason() -> String? { unavailable }

  func read(ids: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead {
    lock.withLock {
      asked.append(ids)
      return answers.count > 1 ? answers.removeFirst() : answers[0]
    }
  }
}

final class ClearDueStore: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var saves: Int { lock.withLock { count } }

  func save() async throws -> ReminderItem {
    lock.withLock { count += 1 }
    return ReminderItem(
      id: "R1",
      title: "Call bank",
      notes: nil,
      isCompleted: false,
      completionDate: nil,
      priority: .none,
      dueDate: nil,
      listID: "L1",
      listName: "Inbox"
    )
  }
}

struct ClearDueLeftCase: Sendable {
  let extra: [String]
  let writeUnavailable: String?
  let readUnavailable: String?
  let written: PrivateFieldsWriteResult
  let answers: [PrivateFieldsRead]
  let note: String
  let shown: EarlyReminder?
}

struct ClearDueEarlyReminderTests {
  static let oneDay = EarlyReminder(count: 1, unit: .days)
  static let timeout = "ReminderKit did not answer within 10 seconds"

  static func fields(
    flagged: Bool = false,
    early: EarlyReminder? = nil,
    unreadable: Bool = false
  ) -> PrivateFieldsRead {
    let fields = PrivateReminderFields(
      flagged: flagged,
      urgent: false,
      earlyReminder: early,
      tags: [],
      earlyReminderUnreadable: unreadable
    )
    return .fields(["R1": fields])
  }

  static func parsed(
    _ arguments: [String],
    clearDue: Bool = true
  ) throws -> (runtime: RuntimeOptions, change: PrivateFieldsChange?, removes: Bool) {
    let invocation = try CommandRouter().program.resolve(
      arguments: ["remindjoectl", "edit", "R1"] + (clearDue ? ["--clear-due"] : []) + arguments
    )
    let values = invocation.parsedValues
    let runtime = RuntimeOptions(parsedValues: values)
    let change = try CommandHelpers.privateChange(values, runtime: runtime)
    let removes = EditCommand.removesImpliedEarlyReminder(clearDue: values.flag("clearDue"), privateChange: change)
    return (runtime, change, removes)
  }

  static func clearDue(
    _ arguments: [String] = ["--json"],
    writer: ClearDueWriter,
    reader: ClearDueReader,
    store: ClearDueStore
  ) async throws -> (reminder: ReminderItem, note: String?) {
    let (runtime, change, removes) = try parsed(arguments)
    let saved = try await PrivateFieldsSupport.save(
      change,
      outcome: .updated,
      writer: writer,
      reader: reader,
      publicSave: store.save
    )
    guard removes else {
      return (saved, nil)
    }
    return PrivateFieldsSupport.removeEarlyReminder(from: saved, runtime: runtime, writer: writer, reader: reader)
  }

  @Test("--clear-due on a reminder with an Early Reminder removes it with a checked, read-back write")
  func removesEarlyReminder() async throws {
    let writer = ClearDueWriter()
    let reader = ClearDueReader([Self.fields(early: Self.oneDay), Self.fields()])
    let store = ClearDueStore()

    let result = try await Self.clearDue(writer: writer, reader: reader, store: store)

    #expect(result.note == nil)
    #expect(store.saves == 1)
    #expect(writer.writes == [PrivateFieldsChange(earlyReminder: .remove)])
    #expect(reader.reads == [["R1"], ["R1"]])
    #expect(result.reminder.earlyReminder == nil)
    #expect(result.reminder.flagged == false)
  }

  @Test("With --flag the flag is saved first, then the Early Reminder is removed on its own")
  func flagThenRemoval() async throws {
    let writer = ClearDueWriter()
    let reader = ClearDueReader([
      Self.fields(flagged: true, early: Self.oneDay), Self.fields(flagged: true, early: Self.oneDay),
      Self.fields(flagged: true),
    ])
    let store = ClearDueStore()

    let result = try await Self.clearDue(["--flag", "--json"], writer: writer, reader: reader, store: store)

    #expect(result.note == nil)
    #expect(writer.writes == [PrivateFieldsChange(flagged: true), PrivateFieldsChange(earlyReminder: .remove)])
    #expect(result.reminder.flagged == true)
    #expect(result.reminder.earlyReminder == nil)
  }

  @Test("With --flag, an Early Reminder removal that cannot be read back leaves out the stale Early Reminder")
  func flagThenUnreadRemoval() async throws {
    let writer = ClearDueWriter(results: [.saved, .unknown(reason: "ReminderKit did not finish within 10 seconds")])
    let reader = ClearDueReader([
      Self.fields(flagged: true, early: Self.oneDay), Self.fields(flagged: true, early: Self.oneDay),
      .unavailable(reason: Self.timeout),
    ])

    let result = try await Self.clearDue(["--flag", "--json"], writer: writer, reader: reader, store: ClearDueStore())

    #expect(result.reminder.flagged == true)
    #expect(result.reminder.earlyReminder == nil)
    #expect(
      result.note
        == "remindctl: due date cleared, but the Early Reminder may or may not have been removed: "
        + "ReminderKit did not finish within 10 seconds"
    )
  }

  @Test("An unreadable Early Reminder is removed too")
  func removesUnreadable() async throws {
    let writer = ClearDueWriter()
    let reader = ClearDueReader([Self.fields(unreadable: true), Self.fields()])

    let result = try await Self.clearDue(writer: writer, reader: reader, store: ClearDueStore())

    #expect(writer.writes == [PrivateFieldsChange(earlyReminder: .remove)])
    #expect(result.note == nil)
  }

  @Test("--clear-due on a reminder without an Early Reminder writes nothing private and prints no note")
  func noEarlyReminder() async throws {
    let writer = ClearDueWriter()
    let store = ClearDueStore()

    let result = try await Self.clearDue(writer: writer, reader: ClearDueReader([Self.fields()]), store: store)

    #expect(result.note == nil)
    #expect(store.saves == 1)
    #expect(writer.writes.isEmpty)
  }

  @Test(
    "A failed or unknown write that the read-back shows did remove the Early Reminder prints no note",
    arguments: [
      PrivateFieldsWriteResult.failed(reason: "the save failed"),
      .unknown(reason: "ReminderKit did not finish within 10 seconds"),
    ]
  )
  func readBackShowsRemoved(written: PrivateFieldsWriteResult) async throws {
    let writer = ClearDueWriter(results: [written])
    let reader = ClearDueReader([Self.fields(early: Self.oneDay), Self.fields()])

    let result = try await Self.clearDue(writer: writer, reader: reader, store: ClearDueStore())

    #expect(result.note == nil)
    #expect(result.reminder.earlyReminder == nil)
  }

  @Test(
    "Only --clear-due without an explicit --early adds the implied removal",
    arguments: [
      (["--clear-due"], true),
      (["--clear-due", "--flag"], true),
      (["--clear-due", "--early", "none"], false),
      (["--clear-due", "--early", "2d"], false),
      (["--title", "x"], false),
      (["--early", "none"], false),
    ]
  )
  func impliedRemovalOnlyWithoutExplicitEarly(arguments: [String], removes: Bool) throws {
    #expect(try Self.parsed(arguments, clearDue: false).removes == removes)
  }

  @Test("--clear-due --early 2d keeps the new Early Reminder and writes no removal after it")
  func explicitEarlyIsNotRemovedAgain() async throws {
    let twoDays = EarlyReminder(count: 2, unit: .days)
    let writer = ClearDueWriter()
    let reader = ClearDueReader([Self.fields(early: twoDays)])

    let result = try await Self.clearDue(
      ["--early", "2d", "--json"],
      writer: writer,
      reader: reader,
      store: ClearDueStore()
    )

    #expect(writer.writes == [PrivateFieldsChange(earlyReminder: .set(twoDays))])
    #expect(result.reminder.earlyReminder == twoDays)
    #expect(result.note == nil)
  }
}
