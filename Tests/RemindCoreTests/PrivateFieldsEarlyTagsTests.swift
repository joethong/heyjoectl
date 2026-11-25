import Foundation
import Testing

@testable import RemindCore

struct PrivateFieldsEarlyTagsTests {
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

  private static func attach(_ fields: [String: PrivateReminderFields], ids: [String]) -> PrivateFieldsAttachment {
    PrivateFields.attach(
      to: ids.map(reminder), scope: .everything, reader: FakePrivateFieldsReader(.fields(fields)))
  }

  @Test("Tags are attached sorted")
  func tagsSorted() {
    let result = Self.attach(
      ["A": PrivateReminderFields(flagged: false, urgent: false, tags: ["work", "home", "Zed"])], ids: ["A"])

    #expect(result.reminders[0].tags == ["Zed", "home", "work"])
  }

  @Test("A read that found no tags gives an empty list")
  func emptyTags() {
    let result = Self.attach(["A": PrivateReminderFields(flagged: false, urgent: false, tags: [])], ids: ["A"])

    #expect(result.reminders[0].tags == [])
  }

  @Test("Early Reminder is present only when the read found one")
  func earlyReminderOnlyWhenSet() {
    let result = Self.attach(
      [
        "A": PrivateReminderFields(earlyReminder: EarlyReminder(count: 1, unit: .days), tags: []),
        "B": PrivateReminderFields(tags: []),
      ], ids: ["A", "B"])

    #expect(result.reminders[0].earlyReminder == EarlyReminder(count: 1, unit: .days))
    #expect(result.reminders[1].earlyReminder == nil)
  }

  @Test("A reminder the read did not mention has no tags and no Early Reminder")
  func missingReminder() {
    let result = Self.attach(["A": PrivateReminderFields(tags: ["x"])], ids: ["A", "B"])

    #expect(result.reminders[1] == Self.reminder("B"))
    #expect(result.reminders[1].tags == nil)
    #expect(result.reminders[1].earlyReminder == nil)
  }

  @Test("Unavailable and skipped reads leave tags and Early Reminder unset")
  func unavailableAndSkipped() {
    let reminders = [Self.reminder("A")]
    let unavailable = PrivateFields.attach(
      to: reminders, scope: .everything, reader: FakePrivateFieldsReader(.unavailable(reason: "no")))
    let skipped = PrivateFields.attach(to: reminders, scope: .everything, reader: nil)

    #expect(unavailable.reminders[0].tags == nil)
    #expect(unavailable.reminders[0].earlyReminder == nil)
    #expect(unavailable.unreadableEarlyReminders == 0)
    #expect(skipped.reminders[0].tags == nil)
    #expect(skipped.unreadableEarlyReminders == 0)
  }

  @Test("Unreadable Early Reminders are counted for the requested reminders only")
  func unreadableCount() {
    let result = Self.attach(
      [
        "A": PrivateReminderFields(tags: [], earlyReminderUnreadable: true),
        "B": PrivateReminderFields(tags: [], earlyReminderUnreadable: true),
        "Z": PrivateReminderFields(tags: [], earlyReminderUnreadable: true),
        "C": PrivateReminderFields(tags: []),
      ], ids: ["A", "B", "C"])

    #expect(result.unreadableEarlyReminders == 2)
    #expect(result.reminders.allSatisfy { $0.earlyReminder == nil })
    #expect(result.unavailableReason == nil)
  }
}
