import Foundation
import RemindCore
import Testing

@testable import remindctl

private final class TagFilterReader: PrivateFieldsReader, @unchecked Sendable {
  private let lock = NSLock()
  private let answer: PrivateFieldsRead
  private var recordedScopes: [ReminderFetchScope] = []

  init(_ answer: PrivateFieldsRead) {
    self.answer = answer
  }

  convenience init(tags: [String: [String]]) {
    self.init(.fields(tags.mapValues { PrivateReminderFields(flagged: false, urgent: false, tags: $0) }))
  }

  var scopes: [ReminderFetchScope] {
    lock.withLock { recordedScopes }
  }

  func unavailableReason() -> String? { nil }

  func read(ids _: Set<String>, scope: ReminderFetchScope) -> PrivateFieldsRead {
    lock.withLock { recordedScopes.append(scope) }
    return answer
  }
}

@MainActor
struct TagFilterTests {
  private static func reminder(_ id: String, completed: Bool = false) -> ReminderItem {
    ReminderItem(
      id: id,
      title: "Milk \(id)",
      notes: nil,
      isCompleted: completed,
      completionDate: nil,
      priority: .none,
      dueDate: nil,
      listID: "L1",
      listName: "Inbox"
    )
  }

  private static let reminders = [reminder("R1"), reminder("R2"), reminder("R3")]
  private static let stored = ["R1": ["errand", "home"], "R2": ["Home"], "R3": []]

  private static func runtime(_ arguments: [String]) throws -> RuntimeOptions {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    return RuntimeOptions(parsedValues: invocation.parsedValues)
  }

  private static func filter(_ arguments: [String]) throws -> TagFilter? {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    let values = invocation.parsedValues
    return try TagFilter.parse(values.options["tag"] ?? [], runtime: RuntimeOptions(parsedValues: values))
  }

  private static func shown(
    _ arguments: [String],
    reader: TagFilterReader = TagFilterReader(tags: stored),
    notes: UnsafeMutablePointer<[String]>? = nil
  ) throws -> [String] {
    let filter = try filter(arguments)
    return try ShowCommand.shown(
      reminders,
      filter: .all,
      runtime: try runtime(arguments),
      tagFilter: filter,
      reader: reader
    ) { notes?.pointee.append($0) }.map(\.id)
  }

  private static func message(_ body: () throws -> Void) -> String? {
    do {
      try body()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  @Test("--tag parses on show and search, repeated, with the leading # dropped")
  func parses() throws {
    #expect(try Self.filter(["show", "all"]) == nil)
    #expect(try Self.filter(["show", "all", "--tag", "home"])?.names == ["home"])
    #expect(try Self.filter(["show", "--tag", "#Home", "--tag", "errand"])?.names == ["Home", "errand"])
    #expect(try Self.filter(["search", "milk", "--tag", "##home", "--completed"])?.names == ["home"])
  }

  @Test("One tag keeps the reminders that have it")
  func oneTag() throws {
    #expect(try Self.shown(["show", "all", "--tag", "home"]) == ["R1", "R2"])
    #expect(try Self.shown(["show", "all", "--tag", "errand"]) == ["R1"])
  }

  @Test("Two tags need both")
  func twoTags() throws {
    #expect(try Self.shown(["show", "all", "--tag", "home", "--tag", "errand"]) == ["R1"])
  }

  @Test("The match ignores case and a leading #", arguments: ["HOME", "#home", "#Home", "##hOmE"])
  func caseAndHash(name: String) throws {
    #expect(try Self.shown(["show", "all", "--tag", name]) == ["R1", "R2"])
  }

  @Test("No match gives an empty list, and JSON renders the empty array")
  func noMatch() throws {
    #expect(try Self.shown(["show", "all", "--tag", "nothing"]).isEmpty)
    #expect(try Self.shown(["show", "all", "--tag", "home", "--tag", "nothing"]).isEmpty)
    let arguments = ["show", "all", "--tag", "nothing", "--json"]
    let noMatch = try ShowCommand.shown(
      Self.reminders,
      filter: .all,
      runtime: try Self.runtime(arguments),
      tagFilter: try Self.filter(arguments),
      reader: TagFilterReader(tags: Self.stored)
    ) { _ in }
    #expect(try OutputRenderer.renderJSON(noMatch) == "[\n\n]")
    let search = ["search", "milk", "--tag", "nothing", "--json"]
    let noFound = try SearchCommand.found(
      Self.reminders,
      query: "milk",
      includeCompleted: false,
      runtime: try Self.runtime(search),
      tagFilter: try Self.filter(search),
      reader: TagFilterReader(tags: Self.stored)
    ) { _ in }
    #expect(try OutputRenderer.renderJSON(noFound) == "[\n\n]")
  }

  @Test(
    "A bad tag name is refused like the write side refuses it",
    arguments: [
      ("", "Invalid --tag: \"\" (use a tag name with no spaces, such as home or errand)"),
      ("#", "Invalid --tag: \"#\" (use a tag name with no spaces, such as home or errand)"),
      ("two words", "Invalid --tag: \"two words\" (use a tag name with no spaces, such as home or errand)"),
      ("a,b", "Invalid --tag: \"a,b\" (one tag name with no commas; repeat --tag for more)"),
    ]
  )
  func badName(name: String, expected: String) {
    for command in [["show", "all"], ["search", "milk"]] {
      #expect(Self.message { _ = try Self.filter(command + ["--tag", name]) } == expected)
    }
  }

  @Test("--no-private refuses --tag before anything is read")
  func noPrivate() {
    for command in [["show", "all"], ["search", "milk"]] {
      #expect(
        Self.message { _ = try Self.filter(command + ["--tag", "home", "--no-private"]) }
          == "--tag filters on tags read through ReminderKit; remove --no-private"
      )
    }
  }

  @Test("--no-private without --tag is not refused")
  func noPrivateWithoutTag() throws {
    #expect(try Self.filter(["show", "all", "--no-private"]) == nil)
  }

  @Test("An unavailable private read refuses --tag and shows no list")
  func unavailable() {
    let reader = TagFilterReader(.unavailable(reason: "ReminderKit did not load (dlopen failed)"))
    var notes: [String] = []
    let message = Self.message {
      _ = try Self.shown(["show", "all", "--tag", "home"], reader: reader, notes: &notes)
    }
    #expect(
      message
        == "--tag filters on tags read through ReminderKit, which is unavailable: ReminderKit did not load; "
        + "run `remindctl doctor` for details"
    )
    #expect(notes.isEmpty)
  }

  @Test("--tag reads the tags in the plain and quiet formats too")
  func readsWhateverTheFormat() throws {
    for flag in ["--plain", "--quiet"] {
      #expect(try Self.shown(["show", "all", "--tag", "home", flag]) == ["R1", "R2"])
    }
  }

  @Test("A reminder ReminderKit does not return has no tags and is not shown")
  func missingFromRead() throws {
    let reader = TagFilterReader(tags: ["R1": ["home"]])
    #expect(try Self.shown(["show", "all", "--tag", "home"], reader: reader) == ["R1"])
  }

  @Test("Show keeps the fetch scope of its filter")
  func showScope() throws {
    let reader = TagFilterReader(tags: Self.stored)
    _ = try ShowCommand.shown(
      Self.reminders,
      filter: .open,
      runtime: try Self.runtime(["show", "open"]),
      tagFilter: try Self.filter(["show", "open", "--tag", "home"]),
      reader: reader
    ) { _ in }
    #expect(reader.scopes == [.openOnly])
  }

  @Test("Search without --completed filters open reminders only")
  func searchOpenOnly() throws {
    let all = [Self.reminder("R1"), Self.reminder("R2", completed: true)]
    let reader = TagFilterReader(tags: ["R1": ["home"]])
    let arguments = ["search", "milk", "--tag", "home"]
    let found = try SearchCommand.found(
      all,
      query: "milk",
      includeCompleted: false,
      runtime: try Self.runtime(arguments),
      tagFilter: try Self.filter(arguments),
      reader: reader
    ) { _ in }
    #expect(found.map(\.id) == ["R1"])
    #expect(reader.scopes == [.openOnly])
  }

  @Test("Search with --completed filters completed reminders as well")
  func searchCompleted() throws {
    let all = [Self.reminder("R1"), Self.reminder("R2", completed: true), Self.reminder("R3", completed: true)]
    let reader = TagFilterReader(tags: ["R1": ["home"], "R2": ["home"], "R3": ["work"]])
    let arguments = ["search", "milk", "--completed", "--tag", "home"]
    let found = try SearchCommand.found(
      all,
      query: "milk",
      includeCompleted: true,
      runtime: try Self.runtime(arguments),
      tagFilter: try Self.filter(arguments),
      reader: reader
    ) { _ in }
    #expect(found.map(\.id) == ["R1", "R2"])
    #expect(reader.scopes == [.everything])
  }

  @Test("Without --tag the output is what attach alone gives, in show and in search")
  func unchangedWithoutTag() throws {
    let fields = TagFilterReader(tags: Self.stored)
    let runtime = try Self.runtime(["show", "all"])
    let expected = PrivateFieldsSupport.attach(
      to: Self.reminders,
      scope: .everything,
      runtime: runtime,
      reader: fields
    ) { _ in }
    let shown = try ShowCommand.shown(
      Self.reminders,
      filter: .all,
      runtime: runtime,
      tagFilter: nil,
      reader: fields
    ) { _ in }
    #expect(shown == expected)
    #expect(shown.map(\.tags) == [["errand", "home"], ["Home"], []])

    let found = try SearchCommand.found(
      Self.reminders,
      query: "milk",
      includeCompleted: false,
      runtime: runtime,
      tagFilter: nil,
      reader: fields
    ) { _ in }
    #expect(found == expected)
  }

  @Test("Without --tag a missing private read still shows the list with a note")
  func unavailableWithoutTag() throws {
    let reader = TagFilterReader(.unavailable(reason: "ReminderKit has no REMStore"))
    var notes: [String] = []
    let shown = try ShowCommand.shown(
      Self.reminders,
      filter: .all,
      runtime: try Self.runtime(["show", "all"]),
      tagFilter: nil,
      reader: reader
    ) { notes.append($0) }
    #expect(shown == Self.reminders)
    #expect(notes.count == 1)
  }

  @Test("Show and search help list --tag with a usage example")
  func help() {
    for (spec, example) in [
      (ShowCommand.spec, "remindctl show all --tag errand --tag home"),
      (SearchCommand.spec, "remindctl search milk --tag errand --tag home"),
    ] {
      let lines = HelpPrinter.renderCommand(rootName: "remindjoectl", spec: spec)
      #expect(lines.contains { $0.hasPrefix("  --tag <value>") })
      #expect(spec.usageExamples.filter { $0.contains("--tag") } == [example])
    }
  }
}
