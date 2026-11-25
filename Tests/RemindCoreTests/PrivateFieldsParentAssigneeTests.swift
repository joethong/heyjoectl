import Foundation
import Testing

@testable import RemindCore

struct PrivateFieldsParentAssigneeTests {
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
      to: ids.map(reminder),
      scope: .everything,
      reader: FakePrivateFieldsReader(.fields(fields))
    )
  }

  private static func assignment(
    _ id: String,
    display: String? = nil,
    first: String? = nil,
    last: String? = nil,
    status: Int = 0,
    date: TimeInterval? = nil
  ) -> ReminderAssignment {
    ReminderAssignment(
      id: id,
      displayName: display,
      firstName: first,
      lastName: last,
      status: status,
      assignedDate: date.map(Date.init(timeIntervalSince1970:))
    )
  }

  @Test("The parent id is set only on the sub-task the read named it for")
  func parentOnlyOnSubTasks() {
    let result = Self.attach(
      [
        "A": PrivateReminderFields(flagged: false, urgent: false, parentID: "P1"),
        "B": PrivateReminderFields(flagged: false, urgent: false),
      ],
      ids: ["A", "B"]
    )

    #expect(result.reminders[0].parentID == "P1")
    #expect(result.reminders[1].parentID == nil)
  }

  @Test("The assignee is attached with and without a name")
  func assigneeWithAndWithoutName() {
    let named = ReminderAssignee(id: "S1", name: "Anna Lee", status: 1)
    let unnamed = ReminderAssignee(id: "S2", status: 0)
    let result = Self.attach(
      [
        "A": PrivateReminderFields(assignee: named),
        "B": PrivateReminderFields(assignee: unnamed),
        "C": PrivateReminderFields(),
      ],
      ids: ["A", "B", "C"]
    )

    #expect(result.reminders[0].assignee == named)
    #expect(result.reminders[1].assignee == unnamed)
    #expect(result.reminders[1].assignee?.name == nil)
    #expect(result.reminders[2].assignee == nil)
  }

  @Test("A reminder the read did not mention has no parent and no assignee")
  func missingReminder() {
    let result = Self.attach(["A": PrivateReminderFields(parentID: "P1")], ids: ["A", "B"])

    #expect(result.reminders[1] == Self.reminder("B"))
  }

  @Test("Unavailable and skipped reads leave the parent and assignee unset")
  func unavailableAndSkipped() {
    let reminders = [Self.reminder("A")]
    let unavailable = PrivateFields.attach(
      to: reminders,
      scope: .everything,
      reader: FakePrivateFieldsReader(.unavailable(reason: "no"))
    )
    let skipped = PrivateFields.attach(to: reminders, scope: .everything, reader: nil)

    #expect(unavailable.reminders[0].parentID == nil)
    #expect(unavailable.reminders[0].assignee == nil)
    #expect(skipped.reminders[0].parentID == nil)
    #expect(skipped.reminders[0].assignee == nil)
  }

  @Test("The newest assignment wins")
  func newestWins() {
    let chosen = ReminderAssignee.newest(of: [
      Self.assignment("old", display: "Old", status: 0, date: 100),
      Self.assignment("new", display: "New", status: 2, date: 300),
      Self.assignment("mid", display: "Mid", status: 1, date: 200),
    ])

    #expect(chosen == ReminderAssignee(id: "new", name: "New", status: 2))
  }

  @Test("An assignment with a date beats one without, and a tie picks the same one every time")
  func datelessAndTies() {
    let dated = Self.assignment("a", date: 1)
    let dateless = Self.assignment("z")
    let first = Self.assignment("b", date: 5)
    let second = Self.assignment("c", date: 5)

    #expect(ReminderAssignee.newest(of: [dateless, dated])?.id == "a")
    #expect(ReminderAssignee.newest(of: [first, second])?.id == "c")
    #expect(ReminderAssignee.newest(of: [second, first])?.id == "c")
    #expect(ReminderAssignee.newest(of: []) == nil)
  }

  @Test("The name is the display name, else first and last, else nothing")
  func nameFallbacks() {
    #expect(Self.assignment("1", display: "Anna L.", first: "Anna", last: "Lee").assignee.name == "Anna L.")
    #expect(Self.assignment("1", display: "", first: "Anna", last: "Lee").assignee.name == "Anna Lee")
    #expect(Self.assignment("1", first: "Anna").assignee.name == "Anna")
    #expect(Self.assignment("1", last: "Lee").assignee.name == "Lee")
    #expect(Self.assignment("1", display: "", first: "", last: "").assignee.name == nil)
    #expect(Self.assignment("1").assignee.name == nil)
  }

  @Test("The assignee carries the id and the status as given")
  func assigneeFields() {
    #expect(
      Self.assignment("S9", display: "Bo", status: 3).assignee == ReminderAssignee(id: "S9", name: "Bo", status: 3)
    )
  }
}
