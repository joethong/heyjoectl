import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

final class TagWriter: PrivateFieldsWriter, @unchecked Sendable {
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

final class TagReader: PrivateFieldsReader, @unchecked Sendable {
  private let lock = NSLock()
  private let answers: [PrivateFieldsRead?]
  private var count = 0

  init(_ tags: [String]?..., flagged: Bool = false) {
    answers = tags.map { tags in .fields(["R1": PrivateReminderFields(flagged: flagged, urgent: false, tags: tags)]) }
  }

  init(answers: [PrivateFieldsRead]) {
    self.answers = answers
  }

  var reads: Int {
    lock.withLock { count }
  }

  func unavailableReason() -> String? { nil }

  func read(ids _: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead {
    lock.withLock {
      count += 1
      return answers[min(count, answers.count) - 1] ?? .fields([:])
    }
  }
}

final class TagStore: @unchecked Sendable {
  private let lock = NSLock()
  private var saveCount = 0

  var saves: Int {
    lock.withLock { saveCount }
  }

  func save() async throws -> ReminderItem {
    lock.withLock { saveCount += 1 }
    return ReminderItem(
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
  }
}

@MainActor
struct TagsWriteSupportTests {
  static func change(_ arguments: [String]) throws -> PrivateFieldsChange? {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    let values = invocation.parsedValues
    return try CommandHelpers.privateChange(values, runtime: RuntimeOptions(parsedValues: values))
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
    _ change: PrivateFieldsChange,
    outcome: PublicSaveOutcome = .updated,
    writer: TagWriter = TagWriter(),
    before: [String]? = [],
    readBack: [String]?,
    store: TagStore = TagStore()
  ) async throws -> ReminderItem {
    try await PrivateFieldsSupport.save(
      change,
      outcome: outcome,
      writer: writer,
      reader: TagReader(before, readBack),
      publicSave: store.save
    )
  }

  @Test(
    "--tag and --untag parse on add and edit, repeated, with a leading # stripped and repeats dropped",
    arguments: [
      (["add", "Buy milk", "--tag", "home"], TagsChange(add: ["home"])),
      (["edit", "4A83", "--untag", "home", "--json"], TagsChange(remove: ["home"])),
      (["add", "Buy milk", "--tag", "home", "--tag", "#errand"], TagsChange(add: ["home", "errand"])),
      (
        ["edit", "4A83", "--tag", "#Home", "--tag", "home", "--untag", "work"],
        TagsChange(add: ["Home"], remove: ["work"])
      ),
      (["edit", "4A83", "--untag", "#a", "--untag", "b", "--untag", "A"], TagsChange(remove: ["a", "b"])),
      (["add", "Buy milk", "--untag", "home"], TagsChange(remove: ["home"])),
    ]
  )
  func tagsParse(arguments: [String], expected: TagsChange) throws {
    #expect(try Self.change(arguments) == PrivateFieldsChange(tags: expected))
  }

  @Test("Tags go in the same change as the flag")
  func tagsWithFlag() throws {
    #expect(
      try Self.change(["edit", "4A83", "--flag", "--tag", "home"])
        == PrivateFieldsChange(flagged: true, tags: TagsChange(add: ["home"]))
    )
  }

  @Test(
    "An empty name or one with a space is refused",
    arguments: [
      ("--tag", ""), ("--tag", "#"), ("--untag", "  "), ("--tag", "two words"), ("--untag", "tab\there"),
      ("--tag", "#new\nline"),
    ]
  )
  func badNamesRefused(option: String, name: String) throws {
    for command in [["edit", "4A83"], ["add", "Buy milk"]] {
      #expect(
        throws: RemindCoreError.operationFailed(
          "Invalid \(option): \"\(name)\" (use a tag name with no spaces, such as home or errand)"
        )
      ) {
        try Self.change(command + [option, name])
      }
    }
  }

  @Test("Every leading # is stripped", arguments: [("--tag", "##home"), ("--untag", "###home")])
  func leadingHashesStripped(option: String, name: String) throws {
    let tags = try Self.change(["edit", "4A83", option, name])?.tags
    #expect(tags == (option == "--tag" ? TagsChange(add: ["home"]) : TagsChange(remove: ["home"])))
  }

  @Test("A name with a comma is refused", arguments: [("--tag", "home,errand"), ("--untag", "#home,")])
  func commaRefused(option: String, name: String) throws {
    for command in [["edit", "4A83"], ["add", "Buy milk"]] {
      #expect(
        throws: RemindCoreError.operationFailed(
          "Invalid \(option): \"\(name)\" (one tag name with no commas; repeat \(option) for more)"
        )
      ) {
        try Self.change(command + [option, name])
      }
    }
  }

  @Test("A name both added and removed is an error, whatever its case", arguments: ["add", "edit"])
  func clash(command: String) throws {
    #expect(throws: RemindCoreError.operationFailed("Use either --tag home or --untag home, not both")) {
      try Self.change([command, "x", "--tag", "home", "--untag", "#HOME"])
    }
  }

  @Test("--no-private with --tag or --untag is an error", arguments: [("add", "--tag"), ("edit", "--untag")])
  func noPrivateRefuses(command: String, option: String) throws {
    #expect(throws: RemindCoreError.operationFailed("\(option) writes through ReminderKit; remove --no-private")) {
      try Self.change([command, "x", option, "home", "--no-private"])
    }
  }

  @Test("--no-private still names --early first when it is given with a tag")
  func noPrivateNamesEarlyFirst() throws {
    #expect(throws: RemindCoreError.operationFailed("--early writes through ReminderKit; remove --no-private")) {
      try Self.change(["edit", "x", "--early", "1d", "--tag", "home", "--no-private"])
    }
  }

  @Test(
    "Tags are written after the public save and the printed reminder shows the read-back tags",
    arguments: [
      (TagsChange(add: ["home"]), PublicSaveOutcome.created, [], ["home"]),
      (TagsChange(add: ["home", "errand"]), .updated, ["work"], ["errand", "home", "work"]),
      (TagsChange(add: ["home"]), .unchanged, ["Home"], ["Home"]),
      (TagsChange(add: ["home"]), .unchanged, ["Home", "home"], ["Home", "home"]),
      (TagsChange(remove: ["home"]), .unchanged, ["home", "work"], ["work"]),
      (TagsChange(remove: ["home"]), .unchanged, [], []),
      (TagsChange(add: ["errand"], remove: ["HOME"]), .updated, ["home"], ["errand"]),
    ]
  )
  func writesThenReadsBack(
    tags: TagsChange,
    outcome: PublicSaveOutcome,
    before: [String],
    readBack: [String]
  ) async throws {
    let store = TagStore()
    let writer = TagWriter()
    let change = PrivateFieldsChange(tags: tags)

    let reminder = try await Self.save(
      change,
      outcome: outcome,
      writer: writer,
      before: before,
      readBack: readBack,
      store: store
    )

    #expect(store.saves == 1)
    #expect(writer.checks == [change])
    #expect(writer.writes == [change])
    #expect(reminder.tags == readBack.sorted())
    let json = try OutputRenderer.renderJSON(reminder)
    let printed = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
    #expect(printed?["tags"] as? [String] == readBack.sorted())
  }

  @Test(
    "When writing is not possible, nothing is saved and the message names the tags",
    arguments: [
      (TagsChange(add: ["home"]), "tag home not added: ReminderKit has no REMSaveRequest; nothing was changed"),
      (
        TagsChange(add: ["home", "errand"], remove: ["work"]),
        "tags home, errand not added and tag work not removed: ReminderKit has no REMSaveRequest; nothing was changed"
      ),
    ]
  )
  func unavailableChangesNothing(tags: TagsChange, expected: String) async throws {
    let store = TagStore()
    let writer = TagWriter(unavailable: "ReminderKit has no REMSaveRequest")

    let message = await Self.message {
      _ = try await Self.save(PrivateFieldsChange(tags: tags), writer: writer, readBack: [], store: store)
    }

    #expect(message == expected)
    #expect(store.saves == 0)
    #expect(writer.writes.isEmpty)
  }

  @Test(
    "A failed or unknown tag write after the public save names what was saved and what was not",
    arguments: [
      (
        PrivateFieldsChange(tags: TagsChange(add: ["home"])),
        PrivateFieldsWriteResult.failed(reason: "the store is locked"),
        "reminder created (id R1); tag home not added: the store is locked"
      ),
      (
        PrivateFieldsChange(flagged: true, tags: TagsChange(remove: ["home", "work"])),
        .failed(reason: "the store is locked"),
        "reminder created (id R1); flag not set and tags home, work not removed: the store is locked"
      ),
      (
        PrivateFieldsChange(tags: TagsChange(add: ["errand"], remove: ["home"])),
        .unknown(reason: "ReminderKit did not answer within 10 seconds"),
        "reminder created (id R1); tag errand may or may not be added and tag home may or may not be removed: "
          + "ReminderKit did not answer within 10 seconds"
      ),
    ]
  )
  func failedWriteNamesWhatWasSaved(
    change: PrivateFieldsChange,
    answer: PrivateFieldsWriteResult,
    expected: String
  ) async throws {
    let store = TagStore()

    let message = await Self.message {
      _ = try await Self.save(
        change,
        outcome: .created,
        writer: TagWriter(answer: answer),
        readBack: [],
        store: store
      )
    }

    #expect(message == expected)
    #expect(store.saves == 1)
  }

  @Test(
    "Tags that read back differently exit with what was saved and what was read",
    arguments: [
      (TagsChange(add: ["home"]), [], [], "tag home added but read back as no tags"),
      (TagsChange(add: ["home"]), [], ["home", "Home"], "tag home added but read back as tags Home, home"),
      (TagsChange(remove: ["home"]), ["home"], ["HOME", "work"], "tag home removed but read back as tags HOME, work"),
      (
        TagsChange(add: ["errand"], remove: ["home"]), ["home"], ["home"],
        "tag errand added and tag home removed but read back as tags home"
      ),
      (TagsChange(remove: ["home"]), ["home", "work"], [], "tag home removed but read back as no tags"),
      (TagsChange(add: ["errand"]), ["work"], ["errand"], "tag errand added but read back as tags errand"),
      (TagsChange(add: ["errand"]), [], ["errand", "work"], "tag errand added but read back as tags errand, work"),
    ]
  )
  func readBackMismatch(tags: TagsChange, before: [String], readBack: [String], expected: String) async throws {
    let message = await Self.message {
      _ = try await Self.save(PrivateFieldsChange(tags: tags), before: before, readBack: readBack)
    }

    #expect(message == "reminder updated (id R1); \(expected)")
  }

  @Test("Tags missing from the read-back exit with what was saved")
  func noTagsValue() async throws {
    let message = await Self.message {
      _ = try await Self.save(PrivateFieldsChange(tags: TagsChange(remove: ["home"])), readBack: nil)
    }

    #expect(message == "reminder updated (id R1); tag home removed but read back as no tags value")
  }
}
