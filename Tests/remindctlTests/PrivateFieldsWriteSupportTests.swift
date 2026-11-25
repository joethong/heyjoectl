import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

@MainActor
struct PrivateFieldsWriteSupportTests {
  private static func parsed(_ arguments: [String]) throws -> (ParsedValues, RuntimeOptions) {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    return (invocation.parsedValues, RuntimeOptions(parsedValues: invocation.parsedValues))
  }

  private static func change(_ arguments: [String]) throws -> PrivateFieldsChange? {
    let (values, runtime) = try parsed(arguments)
    return try CommandHelpers.privateChange(values, runtime: runtime)
  }

  private static func message(_ body: () async throws -> Void) async -> String? {
    do {
      try await body()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  @Test(
    "--flag and --unflag parse on add and edit",
    arguments: [
      (["add", "Call bank", "--flag"], true),
      (["add", "Call bank", "--unflag"], false),
      (["edit", "4A83", "--flag"], true),
      (["edit", "4A83", "--unflag", "--json"], false),
    ]
  )
  func flagsParse(arguments: [String], flagged: Bool) throws {
    #expect(try Self.change(arguments) == PrivateFieldsChange(flagged: flagged))
  }

  @Test("Without --flag or --unflag there is no private change")
  func noChange() throws {
    #expect(try Self.change(["add", "Call bank"]) == nil)
    #expect(try Self.change(["edit", "4A83", "--title", "New", "--no-private"]) == nil)
  }

  @Test("--flag with --unflag is an error", arguments: ["add", "edit"])
  func clash(command: String) throws {
    #expect(throws: RemindCoreError.operationFailed("Use either --flag or --unflag, not both")) {
      try Self.change([command, "x", "--flag", "--unflag"])
    }
  }

  @Test(
    "--no-private with --flag or --unflag is an error",
    arguments: [("add", "--flag"), ("edit", "--unflag")]
  )
  func noPrivateRefuses(command: String, flag: String) throws {
    #expect(
      throws: RemindCoreError.operationFailed("\(flag) writes through ReminderKit; remove --no-private")
    ) {
      try Self.change([command, "x", flag, "--no-private"])
    }
  }

  @Test(
    "Flag and unflag are written after the public save and the printed reminder shows the read-back value",
    arguments: [
      (true, PublicSaveOutcome.created), (false, .created), (true, .updated), (false, .updated),
    ]
  )
  func writesThenReadsBack(flagged: Bool, outcome: PublicSaveOutcome) async throws {
    let store = FakeStore()
    let writer = FakeWriter()

    let reminder = try await PrivateFieldsSupport.save(
      PrivateFieldsChange(flagged: flagged),
      outcome: outcome,
      writer: writer,
      reader: FlagReader(flagged: flagged),
      publicSave: store.save
    )

    #expect(store.saves == 1)
    #expect(writer.writes.map(\.0) == [PrivateFieldsChange(flagged: flagged)])
    #expect(writer.writes.map(\.1) == ["R1"])
    #expect(reminder.flagged == flagged)
    #expect(try OutputRenderer.renderJSON(reminder).contains("\"flagged\" : \(flagged)"))
  }

  @Test("When writing is not possible, nothing is saved and the reason is given")
  func unavailableChangesNothing() async throws {
    let store = FakeStore()
    let writer = FakeWriter(unavailable: "ReminderKit has no REMSaveRequest")

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        PrivateFieldsChange(flagged: true),
        outcome: .created,
        writer: writer,
        reader: FlagReader(flagged: true),
        publicSave: store.save
      )
    }

    #expect(message == "flag not set: ReminderKit has no REMSaveRequest; nothing was changed")
    #expect(store.saves == 0)
    #expect(writer.writes.isEmpty)
  }

  @Test(
    "When ReminderKit cannot read back, no private write saves anything",
    arguments: [
      (PrivateFieldsChange(flagged: true), "flag not set"),
      (PrivateFieldsChange(urgent: true), "Urgent not set"),
      (PrivateFieldsChange(earlyReminder: .set(EarlyReminder(count: 1, unit: .days))), "Early Reminder not set"),
      (PrivateFieldsChange(tags: TagsChange(add: ["home"])), "tag home not added"),
    ]
  )
  func readSideUnavailableChangesNothing(change: PrivateFieldsChange, refused: String) async throws {
    let store = FakeStore()
    let writer = FakeWriter()
    let reason = "REMStore has no fetchRemindersForEventKitBridgingWithListIDs:error:"

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        change,
        outcome: .created,
        writer: writer,
        reader: FlagReader(unavailable: reason),
        publicSave: store.save
      )
    }

    #expect(message == "\(refused): \(reason); nothing was changed")
    #expect(store.saves == 0)
    #expect(writer.writes.isEmpty)
  }

  @Test(
    "A failed private write after the public save names what was saved and what was not",
    arguments: [
      (true, PublicSaveOutcome.created, "reminder created (id R1); flag not set: the store is locked"),
      (false, .updated, "reminder updated (id R1); flag not removed: the store is locked"),
      (true, .unchanged, "reminder not changed (id R1); flag not set: the store is locked"),
    ]
  )
  func failedWriteNamesWhatWasSaved(flagged: Bool, outcome: PublicSaveOutcome, expected: String) async throws {
    let store = FakeStore()
    let writer = FakeWriter(answer: .failed(reason: "the store is locked"))

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        PrivateFieldsChange(flagged: flagged),
        outcome: outcome,
        writer: writer,
        reader: FlagReader(flagged: flagged),
        publicSave: store.save
      )
    }

    #expect(message == expected)
    #expect(store.saves == 1)
  }

  @Test("Without a private change the public save runs alone and nothing is read back")
  func noPrivateChangeSkipsWriterAndReader() async throws {
    let store = FakeStore()
    let writer = FakeWriter(unavailable: "should not be asked")

    let reminder = try await PrivateFieldsSupport.save(
      nil,
      outcome: .created,
      writer: writer,
      reader: FlagReader(flagged: true),
      publicSave: store.save
    )

    #expect(store.saves == 1)
    #expect(writer.writes.isEmpty)
    #expect(reminder.flagged == nil)
  }

  @Test("edit with only --flag or --unflag skips the public save; with no change at all it is an error")
  func editOutcome() throws {
    #expect(try EditCommand.saveOutcome(hasPublicChanges: true, privateChange: nil) == .updated)
    #expect(try EditCommand.saveOutcome(hasPublicChanges: true, privateChange: .init(flagged: true)) == .updated)
    #expect(try EditCommand.saveOutcome(hasPublicChanges: false, privateChange: .init(flagged: false)) == .unchanged)
    #expect(throws: RemindCoreError.operationFailed("No changes specified")) {
      try EditCommand.saveOutcome(hasPublicChanges: false, privateChange: nil)
    }
  }

  @Test("A write that timed out or raised says the flag may or may not be set")
  func unknownWriteSaysSo() async throws {
    let store = FakeStore()
    let writer = FakeWriter(answer: .unknown(reason: "ReminderKit did not answer within 10 seconds"))

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        PrivateFieldsChange(flagged: false),
        outcome: .updated,
        writer: writer,
        reader: FlagReader(flagged: false),
        publicSave: store.save
      )
    }

    #expect(
      message
        == "reminder updated (id R1); flag may or may not be removed: ReminderKit did not answer within 10 seconds"
    )
  }

  @Test(
    "A saved flag that cannot be read back, or reads back wrong, exits with what was saved",
    arguments: [
      (
        UnavailableReader() as any PrivateFieldsReader,
        "reminder created (id R1); flag set but not read back: ReminderKit did not answer within 10 seconds"
      ),
      (FlagReader(flagged: false), "reminder created (id R1); flag set but read back as flagged false"),
    ]
  )
  func readBackFailureNamesWhatWasSaved(reader: any PrivateFieldsReader, expected: String) async throws {
    let store = FakeStore()
    let writer = FakeWriter()

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        PrivateFieldsChange(flagged: true),
        outcome: .created,
        writer: writer,
        reader: reader,
        publicSave: store.save
      )
    }

    #expect(message == expected)
    #expect(writer.writes.count == 1)
  }
}
