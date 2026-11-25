import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

private final class StoreLikeReader: PrivateFieldsReader, @unchecked Sendable {
  private let lock = NSLock()
  private let fieldsByID: [String: PrivateReminderFields]
  private let requestedMalformedIDs: Set<String>
  private let unavailable: String?
  private var requested: [Set<String>] = []

  init(
    _ fieldsByID: [String: PrivateReminderFields] = [:],
    requestedMalformedIDs: Set<String> = [],
    unavailable: String? = nil
  ) {
    self.fieldsByID = fieldsByID
    self.requestedMalformedIDs = requestedMalformedIDs
    self.unavailable = unavailable
  }

  var requests: [Set<String>] {
    lock.withLock { requested }
  }

  func unavailableReason() -> String? { nil }

  func read(ids: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead {
    lock.withLock { requested.append(ids) }
    if let unavailable {
      return .unavailable(reason: unavailable)
    }
    if !requestedMalformedIDs.isDisjoint(with: ids) {
      return .unavailable(reason: "a ReminderKit hashtag has no name")
    }
    return .fields(fieldsByID.filter { ids.contains($0.key) })
  }
}

private struct FixedWriter: PrivateFieldsWriter {
  func unavailableReason(for _: PrivateFieldsChange) -> String? { nil }
  func write(_: PrivateFieldsChange, id _: String) -> PrivateFieldsWriteResult { .saved }
}

private struct FixedStore: Sendable {
  let item: ReminderItem

  func save() async throws -> ReminderItem { item }
}

@MainActor
struct WriteOutputPrivateFieldsTests {
  private static let known = PrivateReminderFields(
    flagged: true,
    urgent: false,
    earlyReminder: EarlyReminder(count: 1, unit: .days),
    tags: ["home", "errand"]
  )

  private static func reminder(_ id: String, completed: Bool = false) -> ReminderItem {
    ReminderItem(
      id: id,
      title: "Call bank",
      notes: nil,
      isCompleted: completed,
      completionDate: nil,
      priority: .none,
      dueDate: nil,
      listID: "L1",
      listName: "Inbox"
    )
  }

  private static func reminder(_ id: String, fields: PrivateReminderFields) -> ReminderItem {
    ReminderItem(
      id: id,
      title: "Call bank",
      notes: nil,
      isCompleted: false,
      completionDate: nil,
      priority: .none,
      dueDate: nil,
      listID: "L1",
      listName: "Inbox",
      flagged: fields.flagged,
      urgent: fields.urgent,
      earlyReminder: fields.earlyReminder,
      tags: fields.tags?.sorted()
    )
  }

  private static func runtime(_ arguments: [String]) throws -> RuntimeOptions {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    return RuntimeOptions(parsedValues: invocation.parsedValues)
  }

  private static func keys(of reminder: ReminderItem) throws -> [String: Any] {
    let json = try OutputRenderer.renderJSON(reminder)
    return try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
  }

  @Test(
    "add, edit and complete JSON carry the private keys, and the read asks for the printed reminders only",
    arguments: [
      ["add", "Call bank", "--json"],
      ["edit", "A1", "--title", "New", "--json"],
      ["complete", "A1", "--json"],
    ]
  )
  func jsonCarriesPrivateKeys(arguments: [String]) throws {
    let reader = StoreLikeReader(["A1": Self.known, "B2": PrivateReminderFields(flagged: false)])
    var notes: [String] = []

    let shown = PrivateFieldsSupport.attachWritten(
      [Self.reminder("A1")],
      privateChange: nil,
      runtime: try Self.runtime(arguments),
      reader: reader
    ) { notes.append($0) }

    let json = try Self.keys(of: shown[0])
    #expect(json["flagged"] as? Bool == true)
    #expect(json["urgent"] as? Bool == false)
    #expect(json["tags"] as? [String] == ["errand", "home"])
    let early = try #require(json["earlyReminder"] as? [String: Any])
    #expect(early["count"] as? Int == 1)
    #expect(early["unit"] as? String == "days")
    #expect(reader.requests == [["A1"]])
    #expect(notes.isEmpty)
  }

  @Test("complete asks for the ids it prints and nothing else")
  func completeAsksForPrintedIDs() throws {
    let reader = StoreLikeReader(["A1": Self.known, "B2": Self.known, "C3": Self.known])

    let shown = PrivateFieldsSupport.attachWritten(
      [Self.reminder("A1", completed: true), Self.reminder("B2", completed: true)],
      privateChange: nil,
      runtime: try Self.runtime(["complete", "A1", "B2", "--json"]),
      reader: reader
    ) { _ in }

    #expect(reader.requests == [["A1", "B2"]])
    #expect(shown.allSatisfy { $0.flagged == true })
  }

  @Test("--no-private leaves the keys out and does not read")
  func noPrivateLeavesKeysOut() throws {
    let reader = StoreLikeReader(["A1": Self.known])
    var notes: [String] = []

    let shown = PrivateFieldsSupport.attachWritten(
      [Self.reminder("A1")],
      privateChange: nil,
      runtime: try Self.runtime(["complete", "A1", "--json", "--no-private"]),
      reader: reader
    ) { notes.append($0) }

    let json = try Self.keys(of: shown[0])
    for key in ["flagged", "urgent", "earlyReminder", "tags"] {
      #expect(json[key] == nil)
    }
    #expect(reader.requests.isEmpty)
    #expect(notes.isEmpty)
  }

  @Test("Unavailable leaves the keys out and prints one stderr note")
  func unavailableLeavesKeysOut() throws {
    let reader = StoreLikeReader(unavailable: "ReminderKit has no REMStore")
    var notes: [String] = []

    let shown = PrivateFieldsSupport.attachWritten(
      [Self.reminder("A1")],
      privateChange: nil,
      runtime: try Self.runtime(["add", "Call bank", "--json"]),
      reader: reader
    ) { notes.append($0) }

    let json = try Self.keys(of: shown[0])
    for key in ["flagged", "urgent", "earlyReminder", "tags"] {
      #expect(json[key] == nil)
    }
    #expect(
      notes == [
        "remindctl: private fields unavailable: ReminderKit has no REMStore; run `remindctl doctor` for details"
      ]
    )
  }

  @Test(
    "Other output formats do not read",
    arguments: [["--plain"], ["--quiet"], ["--format", "table"]]
  )
  func otherFormatsDoNotRead(flags: [String]) throws {
    let reader = StoreLikeReader(["A1": Self.known])

    let shown = PrivateFieldsSupport.attachWritten(
      [Self.reminder("A1")],
      privateChange: nil,
      runtime: try Self.runtime(["add", "Call bank"] + flags),
      reader: reader
    ) { _ in }

    #expect(reader.requests.isEmpty)
    #expect(shown == [Self.reminder("A1")])
  }

  @Test("After a private write the fields are already read back, so there is no second read")
  func privateWriteIsNotReadTwice() throws {
    let reader = StoreLikeReader(["A1": Self.known])
    let change = PrivateFieldsChange(flagged: true)
    let saved = Self.reminder("A1", fields: Self.known)

    let shown = PrivateFieldsSupport.attachWritten(
      [saved],
      privateChange: change,
      runtime: try Self.runtime(["edit", "A1", "--flag", "--json"]),
      reader: reader
    ) { _ in }

    #expect(reader.requests.isEmpty)
    #expect(shown == [saved])
  }

  @Test("A write and its read-back ask for the written id only, so a reader that checks only requested ids is not hit")
  func writeAsksForOneID() async throws {
    let reader = StoreLikeReader(
      ["A1": PrivateReminderFields(flagged: true, urgent: false)],
      requestedMalformedIDs: ["Z9"]
    )

    let store = FixedStore(item: Self.reminder("A1"))
    let saved = try await PrivateFields.save(
      PrivateFieldsChange(flagged: true),
      writer: FixedWriter(),
      reader: reader,
      outcome: .updated,
      publicSave: store.save
    )
    let shown = PrivateFieldsSupport.attachWritten(
      [Self.reminder("A1")],
      privateChange: nil,
      runtime: try Self.runtime(["edit", "A1", "--json"]),
      reader: reader
    ) { _ in }

    #expect(saved.flagged == true)
    #expect(shown[0].flagged == true)
    #expect(reader.requests == [["A1"], ["A1"]])
  }

  @Test("The standard line after add or edit shows flagged, urgent and tags as show does")
  func confirmationLineShowsMarkers() {
    let reminder = Self.reminder("A1", fields: Self.known)
    let urgent = Self.reminder("A1", fields: PrivateReminderFields(flagged: false, urgent: true, tags: []))

    #expect(
      OutputRenderer.confirmationLine(for: reminder)
        == "✓ Call bank [Inbox] — no due date [flagged] [early: 1 day] #errand #home"
    )
    #expect(OutputRenderer.confirmationLine(for: urgent) == "✓ Call bank [Inbox] — no due date [urgent]")
    #expect(OutputRenderer.confirmationLine(for: Self.reminder("A1")) == "✓ Call bank [Inbox] — no due date")
  }
}
