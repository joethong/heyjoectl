import Foundation
import Testing

@testable import RemindCore
@testable import remindctl

@MainActor
struct DirectIDResolveTests {
  private static let openID = "4A83B7C2-1D2E-4F5A-9B6C-7D8E9F0A1B2C"
  private static let doneID = "4A83F0E1-2C3D-4E5F-8A9B-0C1D2E3F4A5B"
  private static let otherID = "9E1D0C2B-3A4F-4E5D-8C7B-6A5F4E3D2C1B"

  private static func item(_ id: String, completed: Bool, due: TimeInterval = 1_700_000_000) -> ReminderItem {
    ReminderItem(
      id: id,
      title: id,
      notes: nil,
      isCompleted: completed,
      completionDate: completed ? Date(timeIntervalSince1970: 1_700_000_000) : nil,
      priority: .none,
      dueDate: Date(timeIntervalSince1970: due),
      listID: "list1",
      listName: "Work"
    )
  }

  private actor FakeStore {
    let all: [ReminderItem]
    let direct: [String: ReminderItem]
    private(set) var lookups: [String] = []
    private(set) var fetches = 0

    init(all: [ReminderItem], direct: [ReminderItem]? = nil) {
      self.all = all
      self.direct = Dictionary(uniqueKeysWithValues: (direct ?? all).map { ($0.id, $0) })
    }

    func lookUp(_ id: String) -> ReminderItem? {
      lookups.append(id)
      return direct[id]
    }

    func fetchAll() -> [ReminderItem] {
      fetches += 1
      return all
    }

    nonisolated func resolve(_ inputs: [String]) async throws -> [ReminderItem] {
      try await CommandHelpers.resolveShowIdentifiers(
        inputs, lookUp: { await self.lookUp($0) }, fetchAll: { await self.fetchAll() })
    }
  }

  private static func standardStore() -> FakeStore {
    FakeStore(all: [
      item(openID, completed: false),
      item(doneID, completed: true),
      item(otherID, completed: false, due: 1_700_000_100),
    ])
  }

  @Test("Full ids are looked up directly and the store is not fetched")
  func fullIDsSkipFetch() async throws {
    let store = Self.standardStore()
    let resolved = try await store.resolve([Self.doneID, Self.openID])
    #expect(resolved.map(\.id) == [Self.doneID, Self.openID])
    #expect(await store.fetches == 0)
    #expect(await store.lookups == [Self.doneID, Self.openID])
  }

  @Test("A full id in lower case or with spaces is looked up directly")
  func fullIDAnyCase() async throws {
    let store = Self.standardStore()
    let resolved = try await store.resolve(["  \(Self.openID.lowercased()) "])
    #expect(resolved.map(\.id) == [Self.openID])
    #expect(await store.fetches == 0)
  }

  @Test("The same full id twice gives the reminder once, as today")
  func duplicateFullIDs() async throws {
    let store = Self.standardStore()
    let resolved = try await store.resolve([Self.openID, Self.openID.lowercased()])
    #expect(resolved.map(\.id) == [Self.openID])
    #expect(await store.fetches == 0)
  }

  @Test("A full id mixed with a number or a prefix takes the fetch path")
  func mixedInputsFetch() async throws {
    let store = Self.standardStore()
    let resolved = try await store.resolve([Self.otherID, "4A83B"])
    #expect(resolved.map(\.id) == [Self.otherID, Self.openID])
    #expect(await store.fetches == 1)
    #expect(await store.lookups.isEmpty)
  }

  @Test("A number takes the fetch path and counts from the default listing")
  func numberFetches() async throws {
    let store = Self.standardStore()
    let resolved = try await store.resolve(["2", "1"])
    #expect(await store.fetches == 1)
    #expect(await store.lookups.isEmpty)
    #expect(resolved.map(\.id) == [Self.otherID, Self.openID])
  }

  @Test("A prefix matching one open and one completed reminder is still refused")
  func ambiguousPrefixAcrossCompleted() async throws {
    let store = Self.standardStore()
    do {
      _ = try await store.resolve(["4A83"])
      Issue.record("expected an ambiguous identifier error")
    } catch RemindCoreError.ambiguousIdentifier(let input, let matches) {
      #expect(input == "4A83")
      #expect(Set(matches) == [Self.openID, Self.doneID])
    }
    #expect(await store.fetches == 1)
  }

  @Test("A full id the direct lookup cannot find falls back and gives today's error")
  func notFoundFallsBack() async throws {
    let missing = "00000000-1111-4222-8333-444444444444"
    let store = Self.standardStore()
    do {
      _ = try await store.resolve([Self.openID, missing])
      Issue.record("expected reminder not found")
    } catch let error as RemindCoreError {
      #expect(error.localizedDescription == RemindCoreError.reminderNotFound(missing).localizedDescription)
    }
    #expect(await store.lookups == [Self.openID, missing])
    #expect(await store.fetches == 1)
  }

  @Test("An orphan the lookup skips but the fetch holds resolves through the fetch")
  func orphanFallsBack() async throws {
    let store = FakeStore(
      all: [Self.item(Self.openID, completed: false)],
      direct: [])
    let resolved = try await store.resolve([Self.openID])
    #expect(resolved.map(\.id) == [Self.openID])
    #expect(await store.fetches == 1)
  }

  @Test("A lookup that returns a different reminder is not trusted")
  func mismatchedLookupFallsBack() async throws {
    let other = Self.item(Self.otherID, completed: false)
    let all = [Self.item(Self.openID, completed: false), other]
    let resolved = try await CommandHelpers.resolveShowIdentifiers(
      [Self.openID], lookUp: { _ in other }, fetchAll: { all })
    #expect(resolved.map(\.id) == [Self.openID])
  }

  @Test("A full id with characters after it takes the fetch path")
  func overLongFetches() async throws {
    let input = Self.openID + "ZZ"
    let store = Self.standardStore()
    do {
      _ = try await store.resolve([input])
      Issue.record("expected reminder not found")
    } catch let error as RemindCoreError {
      #expect(error.localizedDescription == RemindCoreError.reminderNotFound(input).localizedDescription)
    }
    #expect(await store.fetches == 1)
    #expect(await store.lookups.isEmpty)
  }

  @Test("A 36-character input that is not a UUID takes the fetch path")
  func nonUUIDFetches() async throws {
    let store = Self.standardStore()
    do {
      _ = try await store.resolve(["4A83B7C2x1D2E-4F5A-9B6C-7D8E9F0A1B2C"])
      Issue.record("expected reminder not found")
    } catch let error as RemindCoreError {
      #expect(
        error.localizedDescription
          == RemindCoreError.reminderNotFound("4A83B7C2x1D2E-4F5A-9B6C-7D8E9F0A1B2C").localizedDescription)
    }
    #expect(await store.fetches == 1)
    #expect(await store.lookups.isEmpty)
  }

  @Test(
    "Each id command resolves through the store-backed resolver",
    arguments: ["Edit", "Complete", "Delete", "Info", "Link"])
  func commandsUseStoreResolver(_ name: String) throws {
    let source = try String(
      contentsOf: URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/remindctl/Commands/\(name)Command.swift"),
      encoding: .utf8)
    #expect(source.contains("CommandHelpers.resolveShowIdentifiers("))
    #expect(source.contains("in: store)"))
    #expect(!source.contains("store.reminders(in: nil)"))
  }
}
