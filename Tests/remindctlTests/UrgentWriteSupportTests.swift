import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

@MainActor
struct UrgentWriteSupportTests {
  private static func change(_ arguments: [String]) throws -> PrivateFieldsChange? {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    let values = invocation.parsedValues
    return try CommandHelpers.privateChange(values, runtime: RuntimeOptions(parsedValues: values))
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
    "--urgent and --not-urgent parse on add and edit, alone and with the flag",
    arguments: [
      (["add", "Call bank", "--urgent"], PrivateFieldsChange(urgent: true)),
      (["add", "Call bank", "--not-urgent"], PrivateFieldsChange(urgent: false)),
      (["edit", "4A83", "--urgent", "--json"], PrivateFieldsChange(urgent: true)),
      (["edit", "4A83", "--not-urgent"], PrivateFieldsChange(urgent: false)),
      (["add", "Call bank", "--flag", "--urgent"], PrivateFieldsChange(flagged: true, urgent: true)),
      (["edit", "4A83", "--unflag", "--urgent"], PrivateFieldsChange(flagged: false, urgent: true)),
    ]
  )
  func urgentParses(arguments: [String], expected: PrivateFieldsChange) throws {
    #expect(try Self.change(arguments) == expected)
  }

  @Test("--urgent with --not-urgent is an error", arguments: ["add", "edit"])
  func clash(command: String) throws {
    #expect(throws: RemindCoreError.operationFailed("Use either --urgent or --not-urgent, not both")) {
      try Self.change([command, "x", "--urgent", "--not-urgent"])
    }
  }

  @Test(
    "--no-private with --urgent or --not-urgent is an error",
    arguments: [("add", "--urgent"), ("edit", "--not-urgent")]
  )
  func noPrivateRefuses(command: String, option: String) throws {
    #expect(
      throws: RemindCoreError.operationFailed("\(option) writes through ReminderKit; remove --no-private")
    ) {
      try Self.change([command, "x", option, "--no-private"])
    }
  }

  @Test(
    "Urgent on and off is written after the public save and the printed reminder shows the read-back value",
    arguments: [
      (true, PublicSaveOutcome.created), (false, .created), (true, .updated), (false, .unchanged),
    ]
  )
  func writesUrgentThenReadsBack(urgent: Bool, outcome: PublicSaveOutcome) async throws {
    let store = FakeStore()
    let writer = FakeWriter()
    let change = PrivateFieldsChange(urgent: urgent)

    let reminder = try await PrivateFieldsSupport.save(
      change,
      outcome: outcome,
      writer: writer,
      reader: FlagReader(urgent: urgent),
      publicSave: store.save
    )

    #expect(store.saves == 1)
    #expect(writer.writes.map(\.0) == [change])
    #expect(reminder.urgent == urgent)
    #expect(try OutputRenderer.renderJSON(reminder).contains("\"urgent\" : \(urgent)"))
  }

  @Test("Urgent and the flag go to the writer as one change and both show in the printed reminder")
  func urgentAndFlagTogether() async throws {
    let store = FakeStore()
    let writer = FakeWriter()
    let change = PrivateFieldsChange(flagged: true, urgent: true)

    let reminder = try await PrivateFieldsSupport.save(
      change,
      outcome: .created,
      writer: writer,
      reader: FlagReader(flagged: true, urgent: true),
      publicSave: store.save
    )

    #expect(writer.writes.map(\.0) == [change])
    let json = try OutputRenderer.renderJSON(reminder)
    #expect(json.contains("\"flagged\" : true"))
    #expect(json.contains("\"urgent\" : true"))
  }

  @Test(
    "When writing is not possible, nothing is saved and the message names each field",
    arguments: [
      (PrivateFieldsChange(urgent: true), "Urgent not set: ReminderKit has no REMSaveRequest; nothing was changed"),
      (
        PrivateFieldsChange(flagged: true, urgent: false),
        "flag not set and Urgent not removed: ReminderKit has no REMSaveRequest; nothing was changed"
      ),
    ]
  )
  func unavailableChangesNothing(change: PrivateFieldsChange, expected: String) async throws {
    let store = FakeStore()
    let writer = FakeWriter(unavailable: "ReminderKit has no REMSaveRequest")

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

  @Test("The writer is asked about the change being made, so a flag-only write is not checked for Urgent")
  func preflightGetsTheChange() async throws {
    let writer = FakeWriter()

    _ = try await PrivateFieldsSupport.save(
      PrivateFieldsChange(flagged: true),
      outcome: .created,
      writer: writer,
      reader: FlagReader(flagged: true),
      publicSave: FakeStore().save
    )

    #expect(writer.checks == [PrivateFieldsChange(flagged: true)])
  }

  @Test(
    "A failed or unknown private write after the public save names what was saved and what was not",
    arguments: [
      (
        PrivateFieldsChange(urgent: true), PrivateFieldsWriteResult.failed(reason: "the store is locked"),
        "reminder created (id R1); Urgent not set: the store is locked"
      ),
      (
        PrivateFieldsChange(urgent: false), .failed(reason: "the store is locked"),
        "reminder created (id R1); Urgent not removed: the store is locked"
      ),
      (
        PrivateFieldsChange(flagged: true, urgent: true), .failed(reason: "the store is locked"),
        "reminder created (id R1); flag not set and Urgent not set: the store is locked"
      ),
      (
        PrivateFieldsChange(flagged: false, urgent: true),
        .unknown(reason: "ReminderKit did not answer within 10 seconds"),
        "reminder created (id R1); flag may or may not be removed and Urgent may or may not be set: "
          + "ReminderKit did not answer within 10 seconds"
      ),
    ]
  )
  func failedWriteNamesWhatWasSaved(
    change: PrivateFieldsChange,
    answer: PrivateFieldsWriteResult,
    expected: String
  ) async throws {
    let store = FakeStore()
    let writer = FakeWriter(answer: answer)

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
    #expect(store.saves == 1)
  }

  @Test(
    "A saved Urgent that cannot be read back, or reads back wrong, exits with what was saved",
    arguments: [
      (
        PrivateFieldsChange(urgent: true), UnavailableReader() as any PrivateFieldsReader,
        "reminder created (id R1); Urgent set but not read back: ReminderKit did not answer within 10 seconds"
      ),
      (
        PrivateFieldsChange(urgent: true), FlagReader(urgent: false),
        "reminder created (id R1); Urgent set but read back as urgent false"
      ),
      (
        PrivateFieldsChange(flagged: true, urgent: true), FlagReader(flagged: true, urgent: false),
        "reminder created (id R1); flag set and Urgent set but read back as urgent false"
      ),
      (
        PrivateFieldsChange(flagged: true, urgent: false), FlagReader(flagged: false, urgent: true),
        "reminder created (id R1); flag set and Urgent removed but read back as flagged false, urgent true"
      ),
    ]
  )
  func readBackFailureNamesWhatWasSaved(
    change: PrivateFieldsChange,
    reader: any PrivateFieldsReader,
    expected: String
  ) async throws {
    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        change,
        outcome: .created,
        writer: FakeWriter(),
        reader: reader,
        publicSave: FakeStore().save
      )
    }

    #expect(message == expected)
  }

  @Test("edit with only --urgent or --not-urgent reports the reminder as not changed", arguments: [true, false])
  func editOutcome(urgent: Bool) throws {
    #expect(try EditCommand.saveOutcome(hasPublicChanges: false, privateChange: .init(urgent: urgent)) == .unchanged)
  }
}
