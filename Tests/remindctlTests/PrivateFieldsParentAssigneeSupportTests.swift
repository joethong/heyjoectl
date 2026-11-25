import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

private struct ParentStubReader: PrivateFieldsReader {
  let answer: PrivateFieldsRead

  func unavailableReason() -> String? { nil }

  func read(ids _: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead { answer }
}

@MainActor
struct PrivateFieldsParentAssigneeSupportTests {
  private static let reminder = ReminderItem(
    id: "A1",
    title: "Call bank",
    notes: nil,
    isCompleted: false,
    completionDate: nil,
    priority: .none,
    dueDate: nil,
    listID: "L1",
    listName: "Inbox"
  )

  private static let parentID = "4F7C2E10-9B3A-4D5E-8A61-0C2B7D9E1F34"
  private static let assignee = ReminderAssignee(
    id: "D2A8B6C4-1E3F-4A5B-9C7D-8E0F1A2B3C4D",
    name: "Anna Lee",
    status: 1
  )

  private static func runtime(_ arguments: [String]) throws -> RuntimeOptions {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    return RuntimeOptions(parsedValues: invocation.parsedValues)
  }

  private static func json(for arguments: [String], answer: PrivateFieldsRead) throws -> String {
    let attached = PrivateFieldsSupport.attach(
      to: [reminder],
      scope: .everything,
      runtime: try runtime(arguments),
      reader: ParentStubReader(answer: answer)
    ) { _ in }
    return try OutputRenderer.renderJSON(attached[0])
  }

  private static let known: PrivateFieldsRead = .fields([
    "A1": PrivateReminderFields(flagged: false, urgent: false, parentID: parentID, assignee: assignee)
  ])

  @Test("JSON has parentID and assignee when the read found them")
  func jsonWhenKnown() throws {
    let json = try Self.json(for: ["show", "all", "--json"], answer: Self.known)

    #expect(json.contains("\"parentID\" : \"\(Self.parentID)\""))
    #expect(json.contains("\"assignee\" : {"))
    #expect(json.contains("\"id\" : \"\(Self.assignee.id)\""))
    #expect(json.contains("\"name\" : \"Anna Lee\""))
    #expect(json.contains("\"status\" : 1"))
  }

  @Test("The assignee has exactly an id, a name and a status, so no address can be in the output")
  func assigneeKeysOnly() throws {
    let json = try Self.json(for: ["show", "all", "--json"], answer: Self.known)
    let object = try #require(
      try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    )
    let assignee = try #require(object["assignee"] as? [String: Any])

    #expect(Set(assignee.keys) == ["id", "name", "status"])
    #expect(!json.contains("@"))
    #expect(!json.localizedCaseInsensitiveContains("address"))
  }

  @Test("An assignee without a name leaves the name key out")
  func unnamedAssignee() throws {
    let json = try Self.json(
      for: ["show", "all", "--json"],
      answer: .fields(["A1": PrivateReminderFields(assignee: ReminderAssignee(id: "S2", status: 0))])
    )

    #expect(json.contains("\"assignee\" : {"))
    #expect(!json.contains("\"name\""))
  }

  @Test("A top-level reminder with nobody assigned has neither key")
  func neitherWhenNone() throws {
    let json = try Self.json(
      for: ["show", "all", "--json"],
      answer: .fields(["A1": PrivateReminderFields(flagged: false, urgent: false)])
    )

    #expect(!json.contains("parentID"))
    #expect(!json.contains("assignee"))
  }

  @Test("--no-private leaves both keys out of the JSON")
  func noPrivateKeysAbsent() throws {
    let json = try Self.json(for: ["show", "all", "--json", "--no-private"], answer: Self.known)

    #expect(!json.contains("parentID"))
    #expect(!json.contains("assignee"))
  }

  @Test("An unavailable read leaves both keys out of the JSON")
  func unavailableKeysAbsent() throws {
    let json = try Self.json(for: ["show", "all", "--json"], answer: .unavailable(reason: "no"))

    #expect(!json.contains("parentID"))
    #expect(!json.contains("assignee"))
  }

  @Test("Standard lines say which reminder it is a sub-task of and who it is assigned to")
  func standardMarks() {
    var both = Self.reminder
    both.parentID = Self.parentID
    both.assignee = Self.assignee
    var unnamed = Self.reminder
    unnamed.assignee = ReminderAssignee(id: "D2A8B6C4-1E3F-4A5B-9C7D-8E0F1A2B3C4D", status: 0)
    var parentOnly = Self.reminder
    parentOnly.parentID = Self.parentID

    #expect(
      OutputRenderer.standardLine(for: both)
        == "[ ] Call bank [Inbox] — no due date [sub-task of 4F7C2E10] [assigned to Anna Lee]"
    )
    #expect(
      OutputRenderer.standardLine(for: unnamed) == "[ ] Call bank [Inbox] — no due date [assigned to D2A8B6C4]"
    )
    #expect(
      OutputRenderer.standardLine(for: parentOnly) == "[ ] Call bank [Inbox] — no due date [sub-task of 4F7C2E10]"
    )
    #expect(OutputRenderer.standardLine(for: Self.reminder) == "[ ] Call bank [Inbox] — no due date")
  }

  @Test("The plain line stays the same when the parent and assignee are set")
  func plainLineUnchanged() {
    var both = Self.reminder
    both.parentID = Self.parentID
    both.assignee = Self.assignee

    #expect(OutputRenderer.plainLine(for: both) == OutputRenderer.plainLine(for: Self.reminder))
    #expect(OutputRenderer.plainLine(for: both) == "A1\tInbox\t0\tnone\t\tCall bank")
  }
}
