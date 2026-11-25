import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

extension ClearDueEarlyReminderTests {
  @Test(
    "When the Early Reminder cannot be removed, the due date is still cleared, nothing throws, and one note says why",
    arguments: [
      ClearDueLeftCase(
        extra: ["--no-private"],
        writeUnavailable: nil,
        readUnavailable: nil,
        written: .saved,
        answers: [fields(early: oneDay)],
        note: "any Early Reminder was left: turned off by --no-private",
        shown: nil
      ),
      ClearDueLeftCase(
        extra: [],
        writeUnavailable: nil,
        readUnavailable: "ReminderKit did not load (no such file)",
        written: .saved,
        answers: [fields(early: oneDay)],
        note: "any Early Reminder was left: ReminderKit did not load",
        shown: nil
      ),
      ClearDueLeftCase(
        extra: [],
        writeUnavailable: nil,
        readUnavailable: nil,
        written: .saved,
        answers: [.unavailable(reason: timeout)],
        note: "any Early Reminder was left: \(timeout)",
        shown: nil
      ),
      ClearDueLeftCase(
        extra: [],
        writeUnavailable: nil,
        readUnavailable: nil,
        written: .saved,
        answers: [.fields([:])],
        note: "any Early Reminder was left: the reminder was not found in ReminderKit",
        shown: nil
      ),
      ClearDueLeftCase(
        extra: [],
        writeUnavailable: "ReminderKit has no REMDueDateDeltaInterval",
        readUnavailable: nil,
        written: .saved,
        answers: [fields(early: oneDay)],
        note: "the Early Reminder was left: ReminderKit has no REMDueDateDeltaInterval",
        shown: oneDay
      ),
      ClearDueLeftCase(
        extra: [],
        writeUnavailable: nil,
        readUnavailable: nil,
        written: .failed(reason: "the save failed: database is locked"),
        answers: [fields(early: oneDay)],
        note: "the Early Reminder was left: the save failed",
        shown: oneDay
      ),
      ClearDueLeftCase(
        extra: [],
        writeUnavailable: nil,
        readUnavailable: nil,
        written: .failed(reason: "the Early Reminders already on the reminder could not be read"),
        answers: [fields(unreadable: true)],
        note: "the Early Reminder was left: the Early Reminders already on the reminder could not be read",
        shown: nil
      ),
      ClearDueLeftCase(
        extra: [],
        writeUnavailable: nil,
        readUnavailable: nil,
        written: .unknown(reason: "ReminderKit did not finish within 10 seconds"),
        answers: [fields(early: oneDay), .unavailable(reason: timeout)],
        note: "the Early Reminder may or may not have been removed: ReminderKit did not finish within 10 seconds",
        shown: nil
      ),
      ClearDueLeftCase(
        extra: [],
        writeUnavailable: nil,
        readUnavailable: nil,
        written: .unknown(reason: "ReminderKit did not finish within 10 seconds"),
        answers: [fields(early: oneDay), fields(early: oneDay)],
        note: "the Early Reminder was left: ReminderKit did not finish within 10 seconds",
        shown: oneDay
      ),
      ClearDueLeftCase(
        extra: [],
        writeUnavailable: nil,
        readUnavailable: nil,
        written: .saved,
        answers: [fields(early: oneDay), fields(early: oneDay)],
        note: "the Early Reminder was left: read back as Early Reminder 1 day",
        shown: oneDay
      ),
      ClearDueLeftCase(
        extra: [],
        writeUnavailable: nil,
        readUnavailable: nil,
        written: .saved,
        answers: [fields(early: oneDay), .unavailable(reason: timeout)],
        note: "the Early Reminder removal was not read back: \(timeout)",
        shown: nil
      ),
    ]
  )
  func leftWithNote(_ left: ClearDueLeftCase) async throws {
    let writer = ClearDueWriter(unavailable: left.writeUnavailable, results: [left.written])
    let reader = ClearDueReader(left.answers, unavailable: left.readUnavailable)
    let store = ClearDueStore()

    let result = try await Self.clearDue(left.extra + ["--json"], writer: writer, reader: reader, store: store)

    #expect(result.note == "remindctl: due date cleared, but \(left.note)")
    #expect(store.saves == 1)
    #expect(result.reminder.dueDate == nil)
    #expect(result.reminder.earlyReminder == left.shown)
    if left.extra == ["--no-private"] {
      #expect(reader.reads.isEmpty)
    }
  }
}
