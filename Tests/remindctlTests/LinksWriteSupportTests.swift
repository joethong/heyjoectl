import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

final class LinkWriter: PrivateFieldsWriter, @unchecked Sendable {
  private let lock = NSLock()
  private let unavailable: String?
  private let answer: PrivateFieldsWriteResult
  private var recorded: [PrivateFieldsChange] = []
  private var checked: [PrivateFieldsChange] = []

  init(unavailable: String? = nil, answer: PrivateFieldsWriteResult = .saved) {
    self.unavailable = unavailable
    self.answer = answer
  }

  var writes: [PrivateFieldsChange] {
    lock.withLock { recorded }
  }

  var checks: [PrivateFieldsChange] {
    lock.withLock { checked }
  }

  func unavailableReason(for change: PrivateFieldsChange) -> String? {
    lock.withLock { checked.append(change) }
    return unavailable
  }

  func write(_ change: PrivateFieldsChange, id _: String) -> PrivateFieldsWriteResult {
    lock.withLock { recorded.append(change) }
    return answer
  }
}

final class LinkReader: PrivateFieldsReader, @unchecked Sendable {
  private let lock = NSLock()
  private let unavailable: String?
  private let answers: [PrivateFieldsRead]
  private var count = 0

  init(_ links: [String]?..., tags: [String]? = []) {
    unavailable = nil
    answers = links.map { links in
      .fields(["R1": PrivateReminderFields(flagged: false, urgent: false, tags: tags, links: links)])
    }
  }

  init(answers: [PrivateFieldsRead], unavailable: String? = nil) {
    self.answers = answers
    self.unavailable = unavailable
  }

  var reads: Int {
    lock.withLock { count }
  }

  func unavailableReason() -> String? { unavailable }

  func read(ids _: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead {
    lock.withLock {
      count += 1
      return answers[min(count, answers.count) - 1]
    }
  }
}

final class LinkStore: @unchecked Sendable {
  private let lock = NSLock()
  private var saveCount = 0

  var saves: Int {
    lock.withLock { saveCount }
  }

  func save() async throws -> ReminderItem {
    lock.withLock { saveCount += 1 }
    return LinksWriteSupportTests.reminder
  }
}

@MainActor
struct LinksWriteSupportTests {
  nonisolated static let reminder = ReminderItem(
    id: "R1",
    title: "Buy milk",
    notes: nil,
    isCompleted: false,
    completionDate: nil,
    priority: .none,
    dueDate: nil,
    listID: "L1",
    listName: "Inbox"
  )

  static func runtime(_ arguments: [String]) throws -> (ParsedValues, RuntimeOptions) {
    let values = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments).parsedValues
    return (values, RuntimeOptions(parsedValues: values))
  }

  static func change(_ arguments: [String]) throws -> PrivateFieldsChange? {
    let (values, runtime) = try runtime(arguments)
    return try CommandHelpers.privateChange(values, runtime: runtime)
  }

  static func message(_ body: () async throws -> Void) async -> String? {
    do {
      try await body()
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  static func save(
    _ links: LinksChange,
    outcome: PublicSaveOutcome = .updated,
    writer: LinkWriter = LinkWriter(),
    before: [String]? = [],
    readBack: [String]?,
    store: LinkStore = LinkStore()
  ) async throws -> ReminderItem {
    try await PrivateFieldsSupport.save(
      PrivateFieldsChange(links: links),
      outcome: outcome,
      writer: writer,
      reader: LinkReader(before, readBack),
      publicSave: store.save
    )
  }

  static func json(_ reminder: ReminderItem) throws -> [String: Any]? {
    try JSONSerialization.jsonObject(with: Data(OutputRenderer.renderJSON(reminder).utf8)) as? [String: Any]
  }

  @Test(
    "--link and --unlink parse on add and edit, repeated, with repeats dropped",
    arguments: [
      (["add", "Buy milk", "--link", "https://example.com/a"], LinksChange(add: ["https://example.com/a"])),
      (["add", "Buy milk", "--unlink", "https://example.com/a"], LinksChange(remove: ["https://example.com/a"])),
      (["edit", "4A83", "--unlink", "mailto:joe@example.com"], LinksChange(remove: ["mailto:joe@example.com"])),
      (
        [
          "edit", "4A83", "--link", "http://a.example", "--link", "https://b.example/x?y=1#z", "--link",
          "http://a.example",
        ],
        LinksChange(add: ["http://a.example", "https://b.example/x?y=1#z"])
      ),
      (
        ["add", "Buy milk", "--link", "HTTPS://example.com", "--unlink", "https://example.com/old"],
        LinksChange(add: ["HTTPS://example.com"], remove: ["https://example.com/old"])
      ),
      (
        ["edit", "4A83", "--link", "HTTPS://Example.com/a", "--link", "https://example.com/a"],
        LinksChange(add: ["HTTPS://Example.com/a"])
      ),
      (
        ["edit", "4A83", "--link", "https://example.com/A", "--link", "https://example.com/a"],
        LinksChange(add: ["https://example.com/A", "https://example.com/a"])
      ),
      (
        [
          "edit", "4A83", "--unlink", "tel:+15551234567", "--unlink", "x-app://item/7", "--unlink",
          "https:example.com",
        ],
        LinksChange(remove: ["tel:+15551234567", "x-app://item/7", "https:example.com"])
      ),
    ]
  )
  func linksParse(arguments: [String], expected: LinksChange) throws {
    #expect(try Self.change(arguments) == PrivateFieldsChange(links: expected))
  }

  @Test("Links go in the same change as the flag and tags")
  func linksWithOtherFields() throws {
    #expect(
      try Self.change(["edit", "4A83", "--flag", "--tag", "home", "--link", "https://example.com"])
        == PrivateFieldsChange(
          flagged: true,
          tags: TagsChange(add: ["home"]),
          links: LinksChange(add: ["https://example.com"])
        )
    )
  }

  @Test(
    "A value that is not an absolute http, https or mailto URL is refused",
    arguments: [
      "", "example.com", "/path/only", "ftp://example.com", "file:///tmp/x", "javascript:alert(1)", "https://",
      "https:example.com", "mailto:", "https://exa mple.com", "x-apple-reminderkit://REMCDReminder/1", "http//x",
    ]
  )
  func badURLsRefused(value: String) throws {
    for command in [["edit", "4A83"], ["add", "Buy milk"]] {
      #expect(
        throws: RemindCoreError.operationFailed(
          "Invalid --link: \"\(value)\" (use an absolute http, https or mailto URL, such as https://example.com)"
        )
      ) {
        try Self.change(command + ["--link", value])
      }
    }
  }

  @Test("--unlink refuses only a value that is not a URL at all", arguments: ["", "https://exa mple.com", "a b"])
  func badUnlinkRefused(value: String) throws {
    for command in [["edit", "4A83"], ["add", "Buy milk"]] {
      #expect(
        throws: RemindCoreError.operationFailed(
          "Invalid --unlink: \"\(value)\" (use a link as `info` prints it, such as https://example.com)"
        )
      ) {
        try Self.change(command + ["--unlink", value])
      }
    }
  }

  @Test(
    "A URL both linked and unlinked is an error, with the scheme and host in any case",
    arguments: [("add", "https://example.com"), ("edit", "https://example.com"), ("edit", "HTTPS://Example.COM")]
  )
  func clash(command: String, unlinked: String) throws {
    #expect(
      throws: RemindCoreError.operationFailed(
        "Use either --link https://example.com or --unlink https://example.com, not both"
      )
    ) {
      try Self.change([command, "x", "--link", "https://example.com", "--unlink", unlinked])
    }
  }

  @Test("A path that differs only in case is a different link, not a clash")
  func pathCaseIsNoClash() throws {
    #expect(
      try Self.change(["edit", "x", "--link", "https://example.com/A", "--unlink", "https://example.com/a"])
        == PrivateFieldsChange(links: LinksChange(add: ["https://example.com/A"], remove: ["https://example.com/a"]))
    )
  }

  @Test(
    "--no-private with --link or --unlink is an error",
    arguments: [
      (["add", "x", "--link", "https://example.com"], "--link"),
      (["edit", "x", "--unlink", "https://example.com"], "--unlink"),
      (["edit", "x", "--untag", "home", "--link", "https://example.com"], "--untag"),
    ]
  )
  func noPrivateRefuses(arguments: [String], option: String) throws {
    #expect(throws: RemindCoreError.operationFailed("\(option) writes through ReminderKit; remove --no-private")) {
      try Self.change(arguments + ["--no-private"])
    }
  }

  @Test(
    "Links are written after the public save and the printed reminder shows the read-back links in stored order",
    arguments: [
      (LinksChange(add: ["https://a.example"]), PublicSaveOutcome.created, [String](), ["https://a.example"]),
      (
        LinksChange(add: ["https://b.example"]), .updated, ["https://z.example"],
        ["https://z.example", "https://b.example"]
      ),
      (LinksChange(add: ["https://a.example"]), .unchanged, ["https://a.example"], ["https://a.example"]),
      (
        LinksChange(remove: ["https://a.example"]), .unchanged, ["https://a.example", "mailto:j@x.example"],
        ["mailto:j@x.example"]
      ),
      (LinksChange(remove: ["https://a.example"]), .unchanged, ["https://b.example"], ["https://b.example"]),
      (
        LinksChange(add: ["https://b.example"], remove: ["https://a.example"]), .updated, ["https://a.example"],
        ["https://b.example"]
      ),
      (LinksChange(add: ["HTTPS://Example.com"]), .unchanged, ["https://example.com"], ["https://example.com"]),
      (
        LinksChange(remove: ["https://EXAMPLE.com/a"]), .unchanged, ["https://example.com/a", "https://example.com/A"],
        ["https://example.com/A"]
      ),
      (LinksChange(add: ["https://Example.com/x"]), .updated, [], ["https://example.com/x"]),
      (
        LinksChange(remove: ["tel:+15551234567"]), .unchanged, ["tel:+15551234567", "https://a.example"],
        ["https://a.example"]
      ),
    ]
  )
  func writesThenReadsBack(
    links: LinksChange,
    outcome: PublicSaveOutcome,
    before: [String],
    readBack: [String]
  ) async throws {
    let store = LinkStore()
    let writer = LinkWriter()
    let change = PrivateFieldsChange(links: links)

    let reminder = try await Self.save(
      links,
      outcome: outcome,
      writer: writer,
      before: before,
      readBack: readBack,
      store: store
    )

    #expect(store.saves == 1)
    #expect(writer.checks == [change])
    #expect(writer.writes == [change])
    #expect(reminder.links == readBack)
    #expect(try Self.json(reminder)?["links"] as? [String] == readBack)
  }

  @Test("Removing the last link leaves the links key out")
  func lastLinkRemoved() async throws {
    let reminder = try await Self.save(
      LinksChange(remove: ["https://a.example"]),
      before: ["https://a.example"],
      readBack: []
    )

    #expect(reminder.links == nil)
    #expect(try Self.json(reminder)?.keys.contains("links") == false)
  }
}
