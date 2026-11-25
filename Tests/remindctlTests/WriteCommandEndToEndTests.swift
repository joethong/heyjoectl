import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

private let firstID = "AAAA1111-0000-4000-8000-000000000001"
private let secondID = "BBBB2222-0000-4000-8000-000000000002"
private let createdID = "CCCC3333-0000-4000-8000-000000000003"

private func item(_ id: String, title: String, due: Date? = nil) -> ReminderItem {
  ReminderItem(
    id: id,
    title: title,
    notes: nil,
    isCompleted: false,
    completionDate: nil,
    priority: .none,
    dueDate: due,
    listID: "L1",
    listName: "Inbox"
  )
}

private final class StubStore: ReminderCommandStore, @unchecked Sendable {
  private let lock = NSLock()
  private var items: [ReminderItem]
  private var recordedDrafts: [(ReminderDraft, ReminderListTarget)] = []
  private var recordedUpdates: [(String, ReminderUpdate)] = []
  private var recordedCompleted: [[String]] = []
  private var recordedDeleted: [[String]] = []

  init(_ items: [ReminderItem] = []) {
    self.items = items
  }

  var drafts: [(ReminderDraft, ReminderListTarget)] { lock.withLock { recordedDrafts } }
  var updates: [(String, ReminderUpdate)] { lock.withLock { recordedUpdates } }
  var completed: [[String]] { lock.withLock { recordedCompleted } }
  var deleted: [[String]] { lock.withLock { recordedDeleted } }

  func requestAccess() async throws {}

  func defaultList() async -> ReminderList? {
    ReminderList(id: "L1", title: "Inbox")
  }

  func reminderItem(withID id: String) async -> ReminderItem? {
    lock.withLock { items.first { $0.id == id } }
  }

  func reminders(in _: String?) async throws -> [ReminderItem] {
    lock.withLock { items }
  }

  func resolveList(_: ReminderListTarget) async throws -> ReminderList {
    ReminderList(id: "L1", title: "Inbox")
  }

  func createReminder(_ draft: ReminderDraft, target: ReminderListTarget) async throws -> ReminderItem {
    let created = ReminderItem(
      id: createdID,
      title: draft.title,
      notes: draft.notes,
      isCompleted: false,
      completionDate: nil,
      priority: draft.priority,
      dueDate: draft.dueDate?.date,
      alarmDate: draft.alarmDate?.date,
      recurrenceRule: draft.recurrenceRule,
      listID: "L1",
      listName: "Inbox"
    )
    lock.withLock {
      recordedDrafts.append((draft, target))
      items.append(created)
    }
    return created
  }

  func updateReminder(id: String, update: ReminderUpdate) async throws -> ReminderItem {
    try lock.withLock {
      guard let index = items.firstIndex(where: { $0.id == id }) else {
        throw RemindCoreError.reminderNotFound(id)
      }
      let old = items[index]
      let due = update.dueDate.map { $0?.date } ?? old.dueDate
      items[index] = item(id, title: update.title ?? old.title, due: due)
      recordedUpdates.append((id, update))
      return items[index]
    }
  }

  func completeReminders(ids: [String]) async throws -> [ReminderItem] {
    lock.withLock {
      recordedCompleted.append(ids)
      return items.filter { ids.contains($0.id) }
    }
  }

  func deleteReminders(ids: [String]) async throws -> Int {
    lock.withLock { recordedDeleted.append(ids) }
    return ids.count
  }
}

private final class StubReminderKit: PrivateFieldsWriter, PrivateFieldsReader, @unchecked Sendable {
  private let lock = NSLock()
  private let failure: String?
  private var stored: [String: PrivateReminderFields]
  private var recorded: [(PrivateFieldsChange, String)] = []

  init(failure: String? = nil, stored: [String: PrivateReminderFields] = [:]) {
    self.failure = failure
    self.stored = stored
  }

  var writes: [(PrivateFieldsChange, String)] { lock.withLock { recorded } }

  func unavailableReason(for _: PrivateFieldsChange) -> String? { nil }

  func unavailableReason() -> String? { nil }

  func read(ids: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead {
    lock.withLock {
      .fields(Dictionary(uniqueKeysWithValues: ids.map { ($0, fields($0)) }))
    }
  }

  func write(_ change: PrivateFieldsChange, id: String) -> PrivateFieldsWriteResult {
    lock.withLock {
      recorded.append((change, id))
      if let failure {
        return .failed(reason: failure)
      }
      let old = fields(id)
      let oldTags = old.tags ?? []
      let tags = change.tags.map { tags in
        oldTags.filter { !tags.remove.contains($0) } + tags.add.filter { !oldTags.contains($0) }
      }
      let early: EarlyReminder? =
        switch change.earlyReminder {
        case .set(let value): value
        case .remove: nil
        case nil: old.earlyReminder
        }
      stored[id] = PrivateReminderFields(
        flagged: change.flagged ?? old.flagged,
        urgent: change.urgent ?? old.urgent,
        earlyReminder: early,
        tags: tags ?? old.tags,
        links: old.links
      )
      return .saved
    }
  }

  private func fields(_ id: String) -> PrivateReminderFields {
    stored[id] ?? PrivateReminderFields(flagged: false, urgent: false, tags: [], links: [])
  }
}

private struct Run {
  let store: StubStore
  let kit: StubReminderKit
  private let opened = Counter()

  init(
    store: StubStore = StubStore([item(firstID, title: "Call bank"), item(secondID, title: "Buy milk")]),
    kit: StubReminderKit = StubReminderKit()
  ) {
    self.store = store
    self.kit = kit
  }

  var storesOpened: Int { opened.value }

  func makeStore() -> any ReminderCommandStore {
    opened.increment()
    return store
  }

  static func parsed(_ arguments: [String]) throws -> (ParsedValues, RuntimeOptions) {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    let runtime = RuntimeOptions(parsedValues: invocation.parsedValues)
    try runtime.validate()
    return (invocation.parsedValues, runtime)
  }

  func add(_ arguments: [String]) async throws -> ReminderItem {
    let (values, runtime) = try Self.parsed(["add"] + arguments)
    return try await AddCommand.run(values, runtime: runtime, makeStore: makeStore, writer: kit, reader: kit)
  }

  func edit(_ arguments: [String]) async throws -> (reminder: ReminderItem, note: String?) {
    let (values, runtime) = try Self.parsed(["edit"] + arguments)
    return try await EditCommand.run(values, runtime: runtime, makeStore: makeStore, writer: kit, reader: kit)
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0
  var value: Int { lock.withLock { count } }
  func increment() { lock.withLock { count += 1 } }
}

private func message(_ body: () async throws -> Void) async -> String? {
  do {
    try await body()
    return nil
  } catch {
    return error.localizedDescription
  }
}

struct WriteCommandEndToEndTests {
  @Test("add with due, repeat, alarm, --flag and --tag saves one draft, then writes the private fields")
  func addEverything() async throws {
    let run = Run()

    let shown = try await run.add([
      "Pay rent", "--due", "2026-12-01 09:00", "--repeat", "monthly", "--alarm", "2026-12-01 08:30",
      "--flag", "--tag", "bills",
    ])

    let (draft, target) = try #require(run.store.drafts.first)
    #expect(run.store.drafts.count == 1)
    #expect(target == .id("L1"))
    #expect(draft.title == "Pay rent")
    #expect(draft.dueDate == (try CommandHelpers.parseDueDate("2026-12-01 09:00")))
    #expect(draft.alarmDate == (try CommandHelpers.parseDueDate("2026-12-01 08:30")))
    #expect(draft.recurrenceRule?.frequency == .monthly)
    #expect(run.kit.writes.count == 1)
    #expect(run.kit.writes.first?.0 == PrivateFieldsChange(flagged: true, tags: TagsChange(add: ["bills"])))
    #expect(run.kit.writes.first?.1 == createdID)
    #expect(shown.id == createdID)
    #expect(shown.flagged == true)
    #expect(shown.tags == ["bills"])
  }

  @Test("edit of the title and due date updates the resolved reminder and writes nothing private")
  func editTitleAndDue() async throws {
    let run = Run()

    let result = try await run.edit(["aaaa", "--title", "Call the bank", "--due", "2026-12-02"])

    let (id, update) = try #require(run.store.updates.first)
    #expect(run.store.updates.count == 1)
    #expect(id == firstID)
    #expect(update.title == "Call the bank")
    #expect(update.dueDate == .some(try CommandHelpers.parseDueDate("2026-12-02")))
    #expect(run.kit.writes.isEmpty)
    #expect(result.reminder.title == "Call the bank")
    #expect(result.reminder.flagged == false)
    #expect(result.note == nil)
  }

  @Test("edit --clear-due clears the due date, then removes the Early Reminder it leaves")
  func editClearDue() async throws {
    let early = EarlyReminder(count: 1, unit: .days)
    let store = StubStore([item(firstID, title: "Call bank", due: Date(timeIntervalSince1970: 1_800_000_000))])
    let kit = StubReminderKit(stored: [firstID: PrivateReminderFields(earlyReminder: early, tags: [], links: [])])
    let run = Run(store: store, kit: kit)

    let result = try await run.edit([firstID, "--clear-due"])

    let (id, update) = try #require(run.store.updates.first)
    #expect(id == firstID)
    #expect(update.dueDate == .some(nil))
    #expect(run.kit.writes.count == 1)
    #expect(run.kit.writes.first?.0 == PrivateFieldsChange(earlyReminder: .remove))
    #expect(run.kit.writes.first?.1 == firstID)
    #expect(result.reminder.dueDate == nil)
    #expect(result.reminder.earlyReminder == nil)
    #expect(result.note == nil)
  }

  @Test("A private-only edit skips the public save and writes to the resolved reminder")
  func editPrivateOnly() async throws {
    let run = Run()

    let result = try await run.edit(["aaaa", "--flag"])

    #expect(run.store.updates.isEmpty)
    #expect(run.kit.writes.count == 1)
    #expect(run.kit.writes.first?.0 == PrivateFieldsChange(flagged: true))
    #expect(run.kit.writes.first?.1 == firstID)
    #expect(result.reminder.id == firstID)
    #expect(result.reminder.flagged == true)
  }

  @Test(
    "A failed private write after the save names what was saved",
    arguments: [
      (["add", "Call bank", "--flag"], 1, "reminder created (id \(createdID)); flag not set: the store is locked"),
      (
        ["edit", "aaaa", "--title", "Ring bank", "--flag"], 1,
        "reminder updated (id \(firstID)); flag not set: the store is locked"
      ),
      (["edit", "aaaa", "--flag"], 0, "reminder not changed (id \(firstID)); flag not set: the store is locked"),
    ]
  )
  func failedPrivateWrite(arguments: [String], publicSaves: Int, expected: String) async throws {
    let run = Run(kit: StubReminderKit(failure: "the store is locked"))

    let message = await message {
      if arguments[0] == "add" {
        _ = try await run.add(Array(arguments.dropFirst()))
      } else {
        _ = try await run.edit(Array(arguments.dropFirst()))
      }
    }

    #expect(message == expected)
    #expect(run.kit.writes.count == 1)
    #expect(run.store.drafts.count + run.store.updates.count == publicSaves)
  }

  @Test(
    "Private options are parsed before any store is opened",
    arguments: [
      (["add", "Call bank", "--flag", "--unflag"], "Use either --flag or --unflag, not both"),
      (["add", "Call bank", "--no-private", "--urgent"], "--urgent writes through ReminderKit; remove --no-private"),
      (["edit", "aaaa", "--flag", "--unflag"], "Use either --flag or --unflag, not both"),
      (["edit", "aaaa", "--early", "soon"], "Invalid --early: \"soon\""),
    ]
  )
  func privateParsedFirst(arguments: [String], expected: String) async throws {
    let run = Run()
    let (values, runtime) = try Run.parsed(arguments)

    let message = await message {
      if arguments[0] == "add" {
        _ = try await AddCommand.run(
          values,
          runtime: runtime,
          makeStore: run.makeStore,
          writer: run.kit,
          reader: run.kit
        )
      } else {
        _ = try await EditCommand.run(
          values,
          runtime: runtime,
          makeStore: run.makeStore,
          writer: run.kit,
          reader: run.kit
        )
      }
    }

    #expect(message?.hasPrefix(expected) == true)
    #expect(run.storesOpened == 0)
    #expect(run.kit.writes.isEmpty)
  }

  @Test("complete, delete, info and link act on the resolved id", arguments: ["aaaa", firstID.lowercased()])
  func idCommandsUseResolvedID(input: String) async throws {
    let run = Run()

    let (completeValues, completeRuntime) = try Run.parsed(["complete", input])
    let completed = try await CompleteCommand.run(
      completeValues,
      runtime: completeRuntime,
      makeStore: run.makeStore,
      reader: run.kit
    )
    #expect(run.store.completed == [[firstID]])
    #expect(completed.map(\.id) == [firstID])

    let (deleteValues, deleteRuntime) = try Run.parsed(["delete", input, "--force", "--quiet"])
    try await DeleteCommand.run(deleteValues, runtime: deleteRuntime, makeStore: run.makeStore)
    #expect(run.store.deleted == [[firstID]])

    let (infoValues, infoRuntime) = try Run.parsed(["info", input])
    let info = try await InfoCommand.run(infoValues, runtime: infoRuntime, makeStore: run.makeStore, reader: run.kit)
    #expect(info.id == firstID)

    let (linkValues, _) = try Run.parsed(["link", input])
    let link = try await LinkCommand.resolve(values: linkValues, makeStore: run.makeStore)
    #expect(link.id == firstID)
  }

  @Test("complete and delete with --dry-run change nothing")
  func dryRunsChangeNothing() async throws {
    let run = Run()

    let (completeValues, completeRuntime) = try Run.parsed(["complete", "aaaa", "--dry-run"])
    let preview = try await CompleteCommand.run(
      completeValues,
      runtime: completeRuntime,
      makeStore: run.makeStore,
      reader: run.kit
    )
    #expect(preview.map(\.id) == [firstID])
    #expect(run.store.completed.isEmpty)

    let (deleteValues, deleteRuntime) = try Run.parsed(["delete", "aaaa", "--dry-run", "--quiet"])
    try await DeleteCommand.run(deleteValues, runtime: deleteRuntime, makeStore: run.makeStore)
    #expect(run.store.deleted.isEmpty)
  }

  @Test("link --list resolves the list through the store")
  func linkList() async throws {
    let run = Run()
    let (values, _) = try Run.parsed(["link", "--list", "Inbox"])

    let link = try await LinkCommand.resolve(values: values, makeStore: run.makeStore)

    #expect(link.kind == "list")
    #expect(link.id == "L1")
  }
}
