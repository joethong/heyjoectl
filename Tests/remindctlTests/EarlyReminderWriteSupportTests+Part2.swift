import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

extension EarlyReminderWriteSupportTests {
  @Test(
    "An Early Reminder that cannot be read back, or reads back wrong, exits with what was saved",
    arguments: [
      (
        EarlyReminderChange.set(EarlyReminder(count: 1, unit: .days)), UnavailableReader() as any PrivateFieldsReader,
        "reminder created (id R1); Early Reminder set but not read back: ReminderKit did not answer within 10 seconds"
      ),
      (
        .set(EarlyReminder(count: 1, unit: .days)), FlagReader(),
        "reminder created (id R1); Early Reminder set but read back as no Early Reminder"
      ),
      (
        .set(EarlyReminder(count: 1, unit: .days)), FlagReader(earlyReminder: EarlyReminder(count: 1, unit: .hours)),
        "reminder created (id R1); Early Reminder set but read back as Early Reminder 1 hour"
      ),
      (
        .remove, FlagReader(earlyReminder: EarlyReminder(count: 2, unit: .weeks)),
        "reminder created (id R1); Early Reminder removed but read back as Early Reminder 2 weeks"
      ),
      (
        .remove, MissingReminderReader(),
        "reminder created (id R1); Early Reminder removed but read back as no Early Reminder value"
      ),
      (
        .remove, FlagReader(earlyReminderUnreadable: true),
        "reminder created (id R1); Early Reminder removed but read back as an unreadable Early Reminder"
      ),
    ]
  )
  func readBackFailureNamesWhatWasSaved(
    early: EarlyReminderChange,
    reader: any PrivateFieldsReader,
    expected: String
  ) async throws {
    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        PrivateFieldsChange(earlyReminder: early),
        outcome: .created,
        writer: FakeWriter(),
        reader: reader,
        publicSave: FakeStore().save
      )
    }

    #expect(message == expected)
  }

  @Test("A flag-only or Urgent-only write leaves the Early Reminder out of the change the writer checks")
  func otherFieldsLeaveEarlyOut() throws {
    #expect(try Self.change(["add", "x", "--flag"])?.earlyReminder == nil)
    #expect(try Self.change(["edit", "4A83", "--urgent"])?.earlyReminder == nil)
  }

  @Test("edit with only --early reports the reminder as not changed")
  func editOutcome() throws {
    let outcome = try EditCommand.saveOutcome(hasPublicChanges: false, privateChange: .init(earlyReminder: .remove))
    #expect(outcome == .unchanged)
  }
}
