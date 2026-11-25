import Foundation
import Testing

@testable import RemindCore

final class FakePrivateFieldsReader: PrivateFieldsReader, @unchecked Sendable {
  private let lock = NSLock()
  private let answer: PrivateFieldsRead
  private var recorded: [(ids: Set<String>, scope: ReminderFetchScope)] = []

  init(_ answer: PrivateFieldsRead) {
    self.answer = answer
  }

  var calls: [(ids: Set<String>, scope: ReminderFetchScope)] {
    lock.withLock { recorded }
  }

  func unavailableReason() -> String? { nil }

  func read(ids: Set<String>, scope: ReminderFetchScope) -> PrivateFieldsRead {
    lock.withLock { recorded.append((ids, scope)) }
    return answer
  }
}

struct PrivateFieldsTests {
  private static func reminder(_ id: String) -> ReminderItem {
    ReminderItem(
      id: id,
      title: "Reminder \(id)",
      notes: nil,
      isCompleted: false,
      completionDate: nil,
      priority: .none,
      dueDate: nil,
      listID: "L1",
      listName: "Inbox"
    )
  }

  @Test("Attaches flagged and urgent to the reminder with the same id")
  func attachesByID() {
    let reader = FakePrivateFieldsReader(
      .fields([
        "B": PrivateReminderFields(flagged: true, urgent: false),
        "A": PrivateReminderFields(flagged: false, urgent: true),
      ]))

    let result = PrivateFields.attach(
      to: [Self.reminder("A"), Self.reminder("B")], scope: .everything, reader: reader)

    #expect(result.unavailableReason == nil)
    #expect(result.reminders.map(\.id) == ["A", "B"])
    #expect(result.reminders[0].flagged == false)
    #expect(result.reminders[0].urgent == true)
    #expect(result.reminders[1].flagged == true)
    #expect(result.reminders[1].urgent == false)
  }

  @Test("A reminder missing from the reader's answer keeps no private fields")
  func missingReminderGetsNothing() {
    let reader = FakePrivateFieldsReader(.fields(["A": PrivateReminderFields(flagged: true, urgent: true)]))

    let result = PrivateFields.attach(
      to: [Self.reminder("A"), Self.reminder("C")], scope: .everything, reader: reader)

    #expect(result.reminders[1] == Self.reminder("C"))
    #expect(result.reminders[1].flagged == nil)
    #expect(result.reminders[1].urgent == nil)
  }

  @Test("Unavailable keeps every reminder as fetched and reports the reason")
  func unavailableKeepsReminders() {
    let reader = FakePrivateFieldsReader(.unavailable(reason: "REMStore missing"))
    let reminders = [Self.reminder("A"), Self.reminder("B")]

    let result = PrivateFields.attach(to: reminders, scope: .everything, reader: reader)

    #expect(result.reminders == reminders)
    #expect(result.unavailableReason == "REMStore missing")
  }

  @Test("Passes the reminder ids and the fetch scope to the reader")
  func passesIDsAndScope() {
    let reader = FakePrivateFieldsReader(.fields([:]))

    _ = PrivateFields.attach(to: [Self.reminder("A"), Self.reminder("B")], scope: .openOnly, reader: reader)
    _ = PrivateFields.attach(to: [Self.reminder("C")], scope: .everything, reader: reader)

    #expect(reader.calls.map(\.ids) == [["A", "B"], ["C"]])
    #expect(reader.calls.map(\.scope) == [.openOnly, .everything])
  }

  @Test("No reader means no read and no reason")
  func noReaderSkips() {
    let reminders = [Self.reminder("A")]

    let result = PrivateFields.attach(to: reminders, scope: .everything, reader: nil)

    #expect(result == PrivateFieldsAttachment(reminders: reminders, unavailableReason: nil))
  }

  @Test("No reminders means no read")
  func emptyListSkipsReader() {
    let reader = FakePrivateFieldsReader(.unavailable(reason: "should not be asked"))

    let result = PrivateFields.attach(to: [], scope: .openOnly, reader: reader)

    #expect(reader.calls.isEmpty)
    #expect(result.unavailableReason == nil)
  }
}
