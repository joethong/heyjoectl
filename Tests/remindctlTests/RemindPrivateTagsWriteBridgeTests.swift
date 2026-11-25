import Foundation
import RemindCore
import RemindPrivate
import Testing

@testable import remindctl

private final class TagWriteLog: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String: [String]] = [:]
  private var stored: [String: AnyObject] = [:]
  private var inContext: [String: AnyObject] = [:]

  func record(_ id: String, _ entry: String) {
    lock.withLock { entries[id, default: []].append(entry) }
  }

  func entries(for id: String) -> [String] {
    lock.withLock { entries[id] ?? [] }
  }

  func store(_ id: String, stored: AnyObject?, inContext: AnyObject? = nil) {
    lock.withLock {
      self.stored[id] = stored
      self.inContext[id] = inContext
    }
  }

  func stored(for id: String) -> AnyObject? {
    lock.withLock { stored[id] }
  }

  func inContext(for id: String) -> AnyObject? {
    lock.withLock { inContext[id] }
  }
}

private let tagLog = TagWriteLog()
private let noStorageID = "00000000-0000-0000-0000-00000000075E"
private let noContextID = "00000000-0000-0000-0000-0000000007C0"
private let addFailsID = "00000000-0000-0000-0000-0000000007AF"

@objc(RPTagStandInObjectID)
private final class TagStandInObjectID: NSObject {
  @objc(objectIDWithURL:)
  static func objectID(with url: NSURL) -> AnyObject? {
    url
  }
}

@objc(RPTagStandInHashtag)
private final class TagStandInHashtag: NSObject {
  @objc let name: AnyObject
  let source: String

  init(_ name: AnyObject, source: String) {
    self.name = name
    self.source = source
  }
}

@objc(RPTagStandInHashtagWithoutName)
private final class TagStandInHashtagWithoutName: NSObject {}

@objc(RPTagStandInStorage)
private final class TagStandInStorage: NSObject {
  @objc let hashtags: AnyObject?

  init(hashtags: AnyObject?) {
    self.hashtags = hashtags
  }
}

@objc(RPTagStandInStorageWithoutHashtags)
private final class TagStandInStorageWithoutHashtags: NSObject {}

@objc(RPTagStandInReminder)
private final class TagStandInReminder: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc var storage: TagStandInStorage? {
    id == noStorageID ? nil : TagStandInStorage(hashtags: tagLog.stored(for: id))
  }
}

@objc(RPTagStandInStore)
private final class TagStandInStore: NSObject {
  @objc(fetchReminderWithObjectID:error:)
  func fetchReminder(_ objectID: AnyObject, _ error: NSErrorPointer) -> AnyObject? {
    guard let url = objectID as? URL else { return nil }
    tagLog.record(url.lastPathComponent, "fetch")
    return TagStandInReminder(id: url.lastPathComponent)
  }
}

@objc(RPTagStandInFlaggedContext)
private final class TagStandInFlaggedContext: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc(setFlagged:)
  func setFlagged(_ flagged: Int) {
    tagLog.record(id, "setFlagged \(flagged)")
  }
}

@objc(RPTagStandInHashtagContext)
private final class TagStandInHashtagContext: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc var hashtags: AnyObject? {
    tagLog.inContext(for: id)
  }

  @objc(addHashtagWithType:name:)
  func addHashtag(type: Int, name: String) -> AnyObject? {
    tagLog.record(id, "add \(type) \(name)")
    return id == addFailsID ? nil : NSObject()
  }

  @objc(removeHashtag:)
  func removeHashtag(_ hashtag: AnyObject) {
    let tag = hashtag as? TagStandInHashtag
    tagLog.record(id, "remove \(tag?.name ?? "?" as NSString) (\(tag?.source ?? "?"))")
  }
}

@objc(RPTagStandInHashtagContextWithoutRemove)
private final class TagStandInHashtagContextWithoutRemove: NSObject {
  @objc var hashtags: AnyObject? { nil }

  @objc(addHashtagWithType:name:)
  func addHashtag(type _: Int, name _: String) -> AnyObject? {
    NSObject()
  }
}

@objc(RPTagStandInHashtagContextAddingInt32)
private final class TagStandInHashtagContextAddingInt32: NSObject {
  @objc var hashtags: AnyObject? { nil }

  @objc(addHashtagWithType:name:)
  func addHashtag(type _: Int32, name _: String) -> AnyObject? {
    NSObject()
  }

  @objc(removeHashtag:)
  func removeHashtag(_ hashtag: AnyObject) {}
}

@objc(RPTagStandInChangeItem)
private final class TagStandInChangeItem: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc(flaggedContext)
  func flaggedContext() -> AnyObject? {
    TagStandInFlaggedContext(id: id)
  }

  @objc(hashtagContext)
  func hashtagContext() -> AnyObject? {
    id == noContextID ? nil : TagStandInHashtagContext(id: id)
  }
}

@objc(RPTagStandInChangeItemFlagOnly)
private final class TagStandInChangeItemFlagOnly: NSObject {
  @objc(flaggedContext)
  func flaggedContext() -> AnyObject? {
    nil
  }
}

@objc(RPTagStandInSaveRequest)
private final class TagStandInSaveRequest: NSObject {
  var id = ""

  @objc(initWithStore:)
  init(store _: AnyObject) {
    super.init()
  }

  @objc(updateReminder:)
  func update(_ reminder: AnyObject) -> AnyObject? {
    guard let reminder = reminder as? TagStandInReminder else { return nil }
    id = reminder.id
    return TagStandInChangeItem(id: id)
  }

  @objc(saveSynchronouslyWithError:)
  func save(_ error: NSErrorPointer) -> Bool {
    tagLog.record(id, "save")
    return true
  }
}

struct RemindPrivateTagsWriteBridgeTests {
  private static let standIns = [
    "REMObjectID": "RPTagStandInObjectID",
    "REMStore": "RPTagStandInStore",
    "REMReminder": "RPTagStandInReminder",
    "REMReminderStorage": "RPTagStandInStorage",
    "REMSaveRequest": "RPTagStandInSaveRequest",
    "REMReminderChangeItem": "RPTagStandInChangeItem",
    "REMReminderFlaggedContextChangeItem": "RPTagStandInFlaggedContext",
    "REMReminderHashtagContextChangeItem": "RPTagStandInHashtagContext",
    "REMHashtag": "RPTagStandInHashtag",
  ]

  private static func write(
    _ id: String,
    flagged: Bool? = nil,
    add: [String] = [],
    remove: [String] = [],
    replacing overrides: [String: String] = [:]
  ) -> String? {
    let tags = add.isEmpty && remove.isEmpty ? nil : TagsChange(add: add, remove: remove)
    let change = ReminderKitFieldsWriter.bridged(PrivateFieldsChange(flagged: flagged, tags: tags))
    let result = RPWriteWithClassesForTesting(standIns.merging(overrides) { $1 }, id, change, 10)
    #expect(!result.outcomeUnknown)
    return result.failureReason
  }

  private static func tags(_ names: [String], _ source: String) -> NSSet {
    NSSet(array: names.map { TagStandInHashtag($0 as NSString, source: source) })
  }

  @Test("Tags the reminder does not have are added with type 1 in one save")
  func addsNewTags() {
    let id = UUID().uuidString
    tagLog.store(id, stored: nil)

    #expect(Self.write(id, add: ["home", "errand"]) == nil)
    #expect(tagLog.entries(for: id) == ["fetch", "add 1 home", "add 1 errand", "save"])
  }

  @Test("A tag the reminder already has, in any case, on the reminder or in the change, is not added again")
  func repeatAddDoesNotDuplicate() {
    let stored = UUID().uuidString
    let inContext = UUID().uuidString
    tagLog.store(stored, stored: Self.tags(["Home"], "stored"))
    tagLog.store(inContext, stored: Self.tags([], "stored"), inContext: Self.tags(["HOME"], "context"))

    #expect(Self.write(stored, add: ["home", "errand"]) == nil)
    #expect(Self.write(inContext, add: ["home"]) == nil)
    #expect(tagLog.entries(for: stored) == ["fetch", "add 1 errand", "save"])
    #expect(tagLog.entries(for: inContext) == ["fetch", "save"])
  }

  @Test("--untag removes each matching tag one by one, whatever its case, and leaves the others")
  func removesStoredTag() {
    let id = UUID().uuidString
    tagLog.store(id, stored: Self.tags(["Home", "work"], "stored"))

    #expect(Self.write(id, remove: ["home"]) == nil)
    #expect(tagLog.entries(for: id) == ["fetch", "remove Home (stored)", "save"])
  }

  @Test("--untag also removes a matching tag the change item holds on its own")
  func removesContextTag() {
    let id = UUID().uuidString
    tagLog.store(id, stored: Self.tags(["home"], "stored"), inContext: Self.tags(["home", "work"], "context"))

    #expect(Self.write(id, remove: ["HOME"]) == nil)
    let entries = tagLog.entries(for: id)
    #expect(entries.first == "fetch")
    #expect(entries.last == "save")
    #expect(Set(entries.dropFirst().dropLast()) == ["remove home (stored)", "remove home (context)"])
  }

  @Test("--untag of a tag the reminder does not have removes nothing and still saves")
  func removingAbsentTag() {
    let id = UUID().uuidString
    tagLog.store(id, stored: Self.tags(["work"], "stored"))

    #expect(Self.write(id, remove: ["home"]) == nil)
    #expect(tagLog.entries(for: id) == ["fetch", "save"])
  }

  @Test("The flag, a removal and an addition go in the same change and one save")
  func combinedWrite() {
    let id = UUID().uuidString
    tagLog.store(id, stored: Self.tags(["work"], "stored"))

    #expect(Self.write(id, flagged: true, add: ["home"], remove: ["work"]) == nil)
    #expect(tagLog.entries(for: id) == ["fetch", "setFlagged 1", "remove work (stored)", "add 1 home", "save"])
  }

  @Test(
    "A tag write with a missing tag class, method or type is refused before anything is fetched or saved",
    arguments: [
      (["REMReminderHashtagContextChangeItem": "RPNoSuchClass"], "ReminderKit has no RPNoSuchClass"),
      (
        ["REMReminderChangeItem": "RPTagStandInChangeItemFlagOnly"],
        "RPTagStandInChangeItemFlagOnly has no hashtagContext"
      ),
      (
        ["REMReminderStorage": "RPTagStandInStorageWithoutHashtags"],
        "RPTagStandInStorageWithoutHashtags has no hashtags"
      ),
      (["REMHashtag": "RPTagStandInHashtagWithoutName"], "RPTagStandInHashtagWithoutName has no name"),
    ]
  )
  func refusesBeforeAnyCall(overrides: [String: String], reason: String) {
    let adding = UUID().uuidString
    let removing = UUID().uuidString

    #expect(Self.write(adding, add: ["home"], replacing: overrides) == reason)
    #expect(Self.write(removing, flagged: true, remove: ["home"], replacing: overrides) == reason)
    #expect(tagLog.entries(for: adding).isEmpty)
    #expect(tagLog.entries(for: removing).isEmpty)
  }

  @Test("A missing removeHashtag: refuses --untag but not --tag")
  func removeNeededOnlyToRemove() {
    let adding = UUID().uuidString
    let removing = UUID().uuidString
    let overrides = ["REMReminderHashtagContextChangeItem": "RPTagStandInHashtagContextWithoutRemove"]

    #expect(
      Self.write(removing, remove: ["home"], replacing: overrides)
        == "RPTagStandInHashtagContextWithoutRemove has no removeHashtag:"
    )
    #expect(tagLog.entries(for: removing).isEmpty)
    #expect(Self.write(adding, add: ["home"], replacing: overrides) == nil)
    #expect(tagLog.entries(for: adding).last == "save")
  }

  @Test("A changed addHashtagWithType:name: refuses --tag but not --untag")
  func addNeededOnlyToAdd() {
    let adding = UUID().uuidString
    let removing = UUID().uuidString
    let overrides = ["REMReminderHashtagContextChangeItem": "RPTagStandInHashtagContextAddingInt32"]

    #expect(
      Self.write(adding, add: ["home"], replacing: overrides)
        == "RPTagStandInHashtagContextAddingInt32 addHashtagWithType:name: has an unexpected signature"
    )
    #expect(tagLog.entries(for: adding).isEmpty)
    #expect(Self.write(removing, remove: ["home"], replacing: overrides) == nil)
    #expect(tagLog.entries(for: removing).last == "save")
  }

  @Test(
    "A flag-only write does not check the tag classes or methods",
    arguments: [
      ["REMReminderHashtagContextChangeItem": "RPNoSuchClass"],
      ["REMReminderHashtagContextChangeItem": "RPTagStandInHashtagContextWithoutRemove"],
      ["REMReminderHashtagContextChangeItem": "RPTagStandInHashtagContextAddingInt32"],
      ["REMReminderChangeItem": "RPTagStandInChangeItemFlagOnly"],
      ["REMReminderStorage": "RPTagStandInStorageWithoutHashtags"],
      ["REMHashtag": "RPNoSuchClass"],
    ]
  )
  func flagOnlyIgnoresTagRequirements(overrides: [String: String]) {
    let id = UUID().uuidString
    tagLog.store(id, stored: "not a set" as NSString)

    #expect(Self.write(id, flagged: true, replacing: overrides) == nil)
    #expect(tagLog.entries(for: id) == ["fetch", "setFlagged 1", "save"])
  }

  @Test(
    "Tags already on the reminder that cannot be read fail the write before anything is changed or saved",
    arguments: ["stored not a set", "stored name not text", "change not a set", "change name not text"]
  )
  func unreadableTagsFail(shape: String) {
    let unreadable: [String: (AnyObject, AnyObject?)] = [
      "stored not a set": ("not a set" as NSString, nil),
      "stored name not text": (NSSet(array: [TagStandInHashtag(7 as NSNumber, source: "stored")]), nil),
      "change not a set": (NSSet(), "not a set" as NSString),
      "change name not text": (NSSet(), NSSet(array: [TagStandInHashtag(NSNull(), source: "context")])),
    ]
    let id = UUID().uuidString
    let (stored, inContext) = unreadable[shape]!
    tagLog.store(id, stored: stored, inContext: inContext)

    #expect(Self.write(id, flagged: true, add: ["home"]) == "the tags already on the reminder could not be read")
    #expect(tagLog.entries(for: id) == ["fetch"])
  }

  @Test("A reminder with no storage fails a tag write before any change")
  func noStorageFails() {
    #expect(Self.write(noStorageID, remove: ["home"]) == "the tags already on the reminder could not be read")
    #expect(tagLog.entries(for: noStorageID).last == "fetch")
  }

  @Test("No tag context, or no tag from ReminderKit, fails the tag write without saving")
  func nilAnswersFail() {
    #expect(
      Self.write(noContextID, add: ["home"]) == "REMReminderChangeItem hashtagContext returned no tag change"
    )
    #expect(!tagLog.entries(for: noContextID).contains("save"))

    #expect(
      Self.write(addFailsID, add: ["home"])
        == "REMReminderHashtagContextChangeItem addHashtagWithType:name: returned no tag"
    )
    #expect(!tagLog.entries(for: addFailsID).contains("save"))
  }
}
