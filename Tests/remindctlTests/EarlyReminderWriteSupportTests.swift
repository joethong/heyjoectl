import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

@MainActor
struct EarlyReminderWriteSupportTests {
  static let oneDay = EarlyReminder(count: 1, unit: .days)

  static func change(_ arguments: [String]) throws -> PrivateFieldsChange? {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    let values = invocation.parsedValues
    return try CommandHelpers.privateChange(values, runtime: RuntimeOptions(parsedValues: values))
  }

  static func message(_ body: () async throws -> Void) async -> String? {
    do {
      try await body()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  @Test(
    "--early takes a whole number with m, min, h, d, w or mo, or none, on add and edit",
    arguments: [
      (["add", "Call bank", "--early", "15m"], EarlyReminderChange.set(EarlyReminder(count: 15, unit: .minutes))),
      (["add", "Call bank", "--early", "15min"], .set(EarlyReminder(count: 15, unit: .minutes))),
      (["add", "Call bank", "--early", "1h"], .set(EarlyReminder(count: 1, unit: .hours))),
      (["edit", "4A83", "--early", " 2D "], .set(EarlyReminder(count: 2, unit: .days))),
      (["edit", "4A83", "--early", "1w", "--json"], .set(EarlyReminder(count: 1, unit: .weeks))),
      (["edit", "4A83", "--early", "1mo"], .set(EarlyReminder(count: 1, unit: .months))),
      (["add", "Call bank", "--early", "none"], .remove),
      (["edit", "4A83", "--early", "None"], .remove),
    ]
  )
  func earlyParses(arguments: [String], expected: EarlyReminderChange) throws {
    #expect(try Self.change(arguments) == PrivateFieldsChange(earlyReminder: expected))
  }

  @Test("--early joins the flag and Urgent in one change")
  func earlyWithFlagAndUrgent() throws {
    #expect(
      try Self.change(["edit", "4A83", "--flag", "--not-urgent", "--early", "1d"])
        == PrivateFieldsChange(flagged: true, urgent: false, earlyReminder: .set(Self.oneDay))
    )
  }

  @Test(
    "A bad --early duration is refused before anything is touched",
    arguments: ["0m", "-1h", "1y", "15", "m", "1.5h", "", "15 m", "99999999999999999999m", "1mon"]
  )
  func badDurationsRefused(value: String) throws {
    #expect(
      throws: RemindCoreError.operationFailed(
        "Invalid --early: \"\(value)\" "
          + "(use a whole number above 0 with m, min, h, d, w or mo, up to a year: 525600m, 8760h, 366d, 52w or 12mo, "
          + "such as 15m, 1h, 2d, 1w or 1mo, or none)"
      )
    ) {
      try CommandHelpers.parseEarlyReminder(value)
    }
  }

  @Test("An upper-case M alone is refused, not read as minutes", arguments: ["1M", " 30M "])
  func upperCaseMRefused(value: String) throws {
    #expect(
      throws: RemindCoreError.operationFailed(
        "Invalid --early: \"\(value)\" (M could mean minutes or months; use m for minutes or mo for months)"
      )
    ) {
      try CommandHelpers.parseEarlyReminder(value)
    }
    #expect(try CommandHelpers.parseEarlyReminder("1MO") == .set(EarlyReminder(count: 1, unit: .months)))
  }

  @Test(
    "--early takes up to one year in its own unit",
    arguments: [
      ("525600m", EarlyReminder(count: 525_600, unit: .minutes)),
      ("525600min", EarlyReminder(count: 525_600, unit: .minutes)),
      ("8760h", EarlyReminder(count: 8760, unit: .hours)),
      ("366d", EarlyReminder(count: 366, unit: .days)),
      ("52w", EarlyReminder(count: 52, unit: .weeks)),
      ("12mo", EarlyReminder(count: 12, unit: .months)),
    ]
  )
  func earlyAcceptsOneYear(value: String, expected: EarlyReminder) throws {
    #expect(try CommandHelpers.parseEarlyReminder(value) == .set(expected))
  }

  @Test(
    "--early above one year in its own unit is refused before anything is touched",
    arguments: ["525601m", "525601min", "8761h", "367d", "53w", "13mo", "9223372036854775807mo"]
  )
  func earlyRefusesMoreThanOneYear(value: String) throws {
    #expect(
      throws: RemindCoreError.operationFailed(
        "Invalid --early: \"\(value)\" "
          + "(use a whole number above 0 with m, min, h, d, w or mo, up to a year: 525600m, 8760h, 366d, 52w or 12mo, "
          + "such as 15m, 1h, 2d, 1w or 1mo, or none)"
      )
    ) {
      try CommandHelpers.parseEarlyReminder(value)
    }
  }

  @Test("A bad --early on the command line stops add and edit before any save", arguments: ["add", "edit"])
  func badDurationStopsCommand(command: String) throws {
    #expect(throws: RemindCoreError.self) {
      try Self.change([command, "x", "--early", "0d", "--flag"])
    }
    #expect {
      try Self.change([command, "x", "--early", "-1h"])
    } throws: { error in
      String(describing: error) == "Missing value for option --early"
    }
  }

  @Test("--no-private with --early is an error", arguments: [("add", "1d"), ("edit", "none")])
  func noPrivateRefuses(command: String, value: String) throws {
    #expect(throws: RemindCoreError.operationFailed("--early writes through ReminderKit; remove --no-private")) {
      try Self.change([command, "x", "--early", value, "--no-private"])
    }
  }

  @Test(
    "Setting and removing an Early Reminder is written after the public save and the printed reminder shows it",
    arguments: [
      (EarlyReminderChange.set(EarlyReminder(count: 1, unit: .days)), PublicSaveOutcome.created),
      (.set(EarlyReminder(count: 30, unit: .minutes)), .updated),
      (.remove, .created),
      (.remove, .unchanged),
    ]
  )
  func writesThenReadsBack(early: EarlyReminderChange, outcome: PublicSaveOutcome) async throws {
    let store = FakeStore()
    let writer = FakeWriter()
    let change = PrivateFieldsChange(earlyReminder: early)
    let shown: EarlyReminder? =
      if case .set(let value) = early { value } else { nil }

    let reminder = try await PrivateFieldsSupport.save(
      change,
      outcome: outcome,
      writer: writer,
      reader: FlagReader(earlyReminder: shown),
      publicSave: store.save
    )

    #expect(store.saves == 1)
    #expect(writer.checks == [change])
    #expect(writer.writes.map(\.0) == [change])
    #expect(reminder.earlyReminder == shown)
    let json = try OutputRenderer.renderJSON(reminder)
    if let shown {
      #expect(json.contains("\"count\" : \(shown.count)"))
      #expect(json.contains("\"unit\" : \"\(shown.unit.rawValue)\""))
    } else {
      #expect(!json.contains("earlyReminder"))
    }
  }

  @Test("The Early Reminder, the flag and Urgent go to the writer as one change and all show in the printed reminder")
  func allThreeTogether() async throws {
    let writer = FakeWriter()
    let change = PrivateFieldsChange(flagged: true, urgent: true, earlyReminder: .set(Self.oneDay))

    let reminder = try await PrivateFieldsSupport.save(
      change,
      outcome: .created,
      writer: writer,
      reader: FlagReader(flagged: true, urgent: true, earlyReminder: Self.oneDay),
      publicSave: FakeStore().save
    )

    #expect(writer.writes.map(\.0) == [change])
    #expect(reminder.flagged == true)
    #expect(reminder.urgent == true)
    #expect(reminder.earlyReminder == Self.oneDay)
  }

  @Test(
    "When writing is not possible, nothing is saved and the message names each field",
    arguments: [
      (
        PrivateFieldsChange(earlyReminder: .set(EarlyReminder(count: 1, unit: .days))),
        "Early Reminder not set: ReminderKit has no REMDueDateDeltaInterval; nothing was changed"
      ),
      (
        PrivateFieldsChange(flagged: true, earlyReminder: .remove),
        "flag not set and Early Reminder not removed: ReminderKit has no REMDueDateDeltaInterval; nothing was changed"
      ),
    ]
  )
  func unavailableChangesNothing(change: PrivateFieldsChange, expected: String) async throws {
    let store = FakeStore()
    let writer = FakeWriter(unavailable: "ReminderKit has no REMDueDateDeltaInterval")

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        change,
        outcome: .created,
        writer: writer,
        reader: FlagReader(),
        publicSave: store.save
      )
    }

    #expect(message == expected)
    #expect(store.saves == 0)
    #expect(writer.writes.isEmpty)
  }

  @Test(
    "A failed or unknown private write after the public save names what was saved and what was not",
    arguments: [
      (
        PrivateFieldsChange(earlyReminder: .set(EarlyReminder(count: 1, unit: .days))),
        PrivateFieldsWriteResult.failed(reason: "the store is locked"),
        "reminder created (id R1); Early Reminder not set: the store is locked"
      ),
      (
        PrivateFieldsChange(earlyReminder: .remove), .failed(reason: "the store is locked"),
        "reminder created (id R1); Early Reminder not removed: the store is locked"
      ),
      (
        PrivateFieldsChange(flagged: true, urgent: false, earlyReminder: .set(EarlyReminder(count: 1, unit: .days))),
        .unknown(reason: "ReminderKit did not answer within 10 seconds"),
        "reminder created (id R1); flag may or may not be set and Urgent may or may not be removed "
          + "and Early Reminder may or may not be set: ReminderKit did not answer within 10 seconds"
      ),
    ]
  )
  func failedWriteNamesWhatWasSaved(
    change: PrivateFieldsChange,
    answer: PrivateFieldsWriteResult,
    expected: String
  ) async throws {
    let store = FakeStore()

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        change,
        outcome: .created,
        writer: FakeWriter(answer: answer),
        reader: FlagReader(),
        publicSave: store.save
      )
    }

    #expect(message == expected)
    #expect(store.saves == 1)
  }
}
