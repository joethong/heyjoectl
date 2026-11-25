import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

extension ClearDueEarlyReminderTests {
  @Test("An explicit --early with --clear-due stays strict and fails with exit 1 as before")
  func explicitEarlyStaysStrict() async throws {
    let store = ClearDueStore()
    let (_, removal, _) = try Self.parsed(["--early", "none"])
    let (_, set, _) = try Self.parsed(["--early", "2d"])
    var messages: [String] = []
    for change in [removal, set] {
      do {
        _ = try await PrivateFieldsSupport.save(
          change,
          outcome: .updated,
          writer: ClearDueWriter(results: [.failed(reason: "the save failed")]),
          reader: ClearDueReader([Self.fields(early: Self.oneDay)]),
          publicSave: store.save
        )
      } catch {
        messages.append(error.localizedDescription)
      }
    }

    #expect(removal == PrivateFieldsChange(earlyReminder: .remove))
    #expect(set == PrivateFieldsChange(earlyReminder: .set(EarlyReminder(count: 2, unit: .days))))
    #expect(
      messages == [
        "reminder updated (id R1); Early Reminder not removed: the save failed",
        "reminder updated (id R1); Early Reminder not set: the save failed",
      ]
    )
  }

  @Test("When the write side is missing for --flag, nothing is saved, as before")
  func flagWithUnavailableWriteChangesNothing() async throws {
    let writer = ClearDueWriter(unavailable: "ReminderKit has no REMSaveRequest")
    let reader = ClearDueReader([Self.fields(early: Self.oneDay)])
    let store = ClearDueStore()
    var message: String?
    do {
      _ = try await Self.clearDue(["--flag"], writer: writer, reader: reader, store: store)
    } catch {
      message = error.localizedDescription
    }

    #expect(message == "flag not set: ReminderKit has no REMSaveRequest; nothing was changed")
    #expect(store.saves == 0)
  }
}
