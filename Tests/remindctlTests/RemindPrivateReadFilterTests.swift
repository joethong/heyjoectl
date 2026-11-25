import Foundation
import RemindPrivate
import Testing

@objc(RPReadFilterObjectID)
private final class ReadFilterObjectID: NSObject {
  @objc let uuid: NSUUID

  init(_ uuid: NSUUID) {
    self.uuid = uuid
  }
}

@objc(RPReadFilterHashtag)
private final class ReadFilterHashtag: NSObject {
  @objc let name: NSObject?

  init(_ name: NSObject?) {
    self.name = name
  }
}

@objc(RPReadFilterStorage)
private final class ReadFilterStorage: NSObject {
  @objc let flagged = NSNumber(value: true)
  @objc let isUrgentStateEnabledForCurrentUser = NSNumber(value: false)
  @objc let hashtags: NSSet
  @objc let dueDateDeltaAlertsData: NSData? = nil
  @objc let parentReminderID: NSObject? = nil
  @objc let assignments: NSSet? = nil

  init(hashtags: [ReadFilterHashtag]) {
    self.hashtags = NSSet(array: hashtags)
  }
}

@objc(RPReadFilterReminder)
private final class ReadFilterReminder: NSObject {
  @objc let objectID: ReadFilterObjectID?
  @objc let storage: ReadFilterStorage

  init(id: UUID?, hashtags: [ReadFilterHashtag]) {
    objectID = id.map { ReadFilterObjectID($0 as NSUUID) }
    storage = ReadFilterStorage(hashtags: hashtags)
  }
}

@objc(RPReadFilterStore)
private final class ReadFilterStore: NSObject {
  let reminders: [ReadFilterReminder]

  init(_ reminders: [ReadFilterReminder]) {
    self.reminders = reminders
  }

  @objc(fetchListsForEventKitBridgingWithError:)
  func fetchLists() throws -> NSArray {
    []
  }

  @objc(fetchRemindersForEventKitBridgingWithListIDs:error:)
  func fetchReminders(_ listIDs: NSArray) throws -> NSArray {
    reminders as NSArray
  }
}

struct RemindPrivateReadFilterTests {
  private static let good = UUID()
  private static let malformed = UUID()
  private static var store: ReadFilterStore {
    ReadFilterStore([
      ReadFilterReminder(id: good, hashtags: [ReadFilterHashtag("home" as NSString)]),
      ReadFilterReminder(id: malformed, hashtags: [ReadFilterHashtag(nil)]),
      ReadFilterReminder(id: nil, hashtags: []),
    ])
  }

  @Test("A reminder that was not asked for, malformed or with no id, does not stop the read of the one that was")
  func otherReminderIsNotChecked() {
    let result = RPReadStoreForTesting(Self.store, [Self.good.uuidString], false, [:])

    #expect(result.unavailableReason == nil)
    #expect(Array(result.fields.keys) == [Self.good.uuidString])
    #expect(result.fields[Self.good.uuidString]?.tags == ["home"])
  }

  @Test("A malformed reminder that was asked for still makes the read unavailable")
  func askedReminderIsChecked() {
    let result = RPReadStoreForTesting(Self.store, [Self.good.uuidString, Self.malformed.uuidString], false, [:])

    #expect(result.unavailableReason == "a ReminderKit hashtag has no name")
    #expect(result.fields.isEmpty)
  }
}
