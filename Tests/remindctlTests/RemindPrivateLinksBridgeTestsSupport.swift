import Foundation
import RemindCore
import RemindPrivate
import Testing

@testable import remindctl

final class LinkWriteLog: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String: [String]] = [:]
  private var stored: [String: AnyObject] = [:]
  private var inContext: [String: AnyObject] = [:]
  private var storageReads: [String: Int] = [:]

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

  func readStorage(_ id: String) {
    lock.withLock { storageReads[id, default: 0] += 1 }
  }

  func storageReads(for id: String) -> Int {
    lock.withLock { storageReads[id] ?? 0 }
  }
}

let linkLog = LinkWriteLog()
let linkNoStorageID = "00000000-0000-0000-0000-0000000011E5"
let linkNoContextID = "00000000-0000-0000-0000-0000000011C0"
let linkAddFailsID = "00000000-0000-0000-0000-0000000011AF"

@objc(RPLinkStandInObjectID)
final class LinkStandInObjectID: NSObject {
  @objc(objectIDWithURL:)
  static func objectID(with url: NSURL) -> AnyObject? {
    url
  }
}

@objc(RPLinkStandInURLAttachment)
final class LinkStandInURLAttachment: NSObject {
  @objc let url: AnyObject?
  let source: String

  init(_ url: AnyObject?, source: String) {
    self.url = url
    self.source = source
  }
}

@objc(RPLinkStandInImageAttachment)
final class LinkStandInImageAttachment: NSObject {
  @objc let url = NSURL(string: "file:///tmp/photo.jpg")
}

@objc(RPLinkStandInURLAttachmentWithoutURL)
final class LinkStandInURLAttachmentWithoutURL: NSObject {}

@objc(RPLinkStandInFileAttachment)
final class LinkStandInFileAttachment: NSObject {
  @objc let fileURL = NSURL(fileURLWithPath: "/tmp/photo.jpg")
}

@objc(RPLinkStandInStorage)
final class LinkStandInStorage: NSObject {
  @objc let attachments: AnyObject?

  init(attachments: AnyObject?) {
    self.attachments = attachments
  }
}

@objc(RPLinkStandInStorageWithoutAttachments)
final class LinkStandInStorageWithoutAttachments: NSObject {}

@objc(RPLinkStandInReminder)
final class LinkStandInReminder: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc var storage: LinkStandInStorage? {
    linkLog.readStorage(id)
    return id == linkNoStorageID ? nil : LinkStandInStorage(attachments: linkLog.stored(for: id))
  }
}

@objc(RPLinkStandInStore)
final class LinkStandInStore: NSObject {
  @objc(fetchReminderWithObjectID:error:)
  func fetchReminder(_ objectID: AnyObject, _ error: NSErrorPointer) -> AnyObject? {
    guard let url = objectID as? URL else { return nil }
    linkLog.record(url.lastPathComponent, "fetch")
    return LinkStandInReminder(id: url.lastPathComponent)
  }
}

@objc(RPLinkStandInFlaggedContext)
final class LinkStandInFlaggedContext: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc(setFlagged:)
  func setFlagged(_ flagged: Int) {
    linkLog.record(id, "setFlagged \(flagged)")
  }
}

@objc(RPLinkStandInAttachmentContext)
final class LinkStandInAttachmentContext: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc var urlAttachments: AnyObject? {
    linkLog.inContext(for: id)
  }

  @objc(addURLAttachmentWithURL:)
  func addURLAttachment(_ url: NSURL) -> AnyObject? {
    linkLog.record(id, "add \(url.absoluteString ?? "?")")
    return id == linkAddFailsID ? nil : NSObject()
  }

  @objc(removeAttachment:)
  func removeAttachment(_ attachment: AnyObject) {
    let link = attachment as? LinkStandInURLAttachment
    linkLog.record(id, "remove \((link?.url as? URL)?.absoluteString ?? "?") (\(link?.source ?? "?"))")
  }
}

@objc(RPLinkStandInAttachmentContextWithoutRemove)
final class LinkStandInAttachmentContextNoRemove: NSObject {
  @objc var urlAttachments: AnyObject? { nil }

  @objc(addURLAttachmentWithURL:)
  func addURLAttachment(_ url: NSURL) -> AnyObject? {
    NSObject()
  }
}

@objc(RPLinkStandInAttachmentContextAddingText)
final class LinkStandInAttachmentContextAddingText: NSObject {
  @objc var urlAttachments: AnyObject? { nil }

  @objc(addURLAttachmentWithURL:)
  func addURLAttachment(_ url: NSURL) -> Bool {
    true
  }

  @objc(removeAttachment:)
  func removeAttachment(_ attachment: AnyObject) {}
}

@objc(RPLinkStandInChangeItem)
final class LinkStandInChangeItem: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc(flaggedContext)
  func flaggedContext() -> AnyObject? {
    LinkStandInFlaggedContext(id: id)
  }

  @objc(attachmentContext)
  func attachmentContext() -> AnyObject? {
    id == linkNoContextID ? nil : LinkStandInAttachmentContext(id: id)
  }
}

@objc(RPLinkStandInChangeItemFlagOnly)
final class LinkStandInChangeItemFlagOnly: NSObject {
  @objc(flaggedContext)
  func flaggedContext() -> AnyObject? {
    nil
  }
}

@objc(RPLinkStandInSaveRequest)
final class LinkStandInSaveRequest: NSObject {
  var id = ""

  @objc(initWithStore:)
  init(store _: AnyObject) {
    super.init()
  }

  @objc(updateReminder:)
  func update(_ reminder: AnyObject) -> AnyObject? {
    guard let reminder = reminder as? LinkStandInReminder else { return nil }
    id = reminder.id
    return LinkStandInChangeItem(id: id)
  }

  @objc(saveSynchronouslyWithError:)
  func save(_ error: NSErrorPointer) -> Bool {
    linkLog.record(id, "save")
    return true
  }
}

@objc(RPLinkReadObjectID)
final class LinkReadObjectID: NSObject {
  @objc let uuid: NSUUID

  init(_ uuid: NSUUID) {
    self.uuid = uuid
  }
}

@objc(RPLinkReadStorage)
final class LinkReadStorage: NSObject {
  @objc let flagged = NSNumber(value: true)
  @objc let isUrgentStateEnabledForCurrentUser = NSNumber(value: false)
  @objc let hashtags: NSSet? = nil
  @objc let dueDateDeltaAlertsData: NSData? = nil
  @objc let parentReminderID: NSObject? = nil
  @objc let assignments: NSSet? = nil
  @objc let attachments: AnyObject?

  init(attachments: AnyObject?) {
    self.attachments = attachments
  }
}

@objc(RPLinkReadReminder)
final class LinkReadReminder: NSObject {
  @objc let objectID: LinkReadObjectID
  @objc let storage: NSObject

  init(id: UUID, storage: NSObject) {
    objectID = LinkReadObjectID(id as NSUUID)
    self.storage = storage
  }
}

@objc(RPLinkReadStore)
final class LinkReadStore: NSObject {
  let reminders: [LinkReadReminder]

  init(_ reminders: [LinkReadReminder]) {
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

@objc(RPLinkReadStorageWithoutAttachments)
final class LinkReadStorageWithoutAttachments: NSObject {
  @objc let flagged = NSNumber(value: true)
  @objc let isUrgentStateEnabledForCurrentUser = NSNumber(value: false)
  @objc let hashtags: NSSet? = nil
  @objc let dueDateDeltaAlertsData: NSData? = nil
  @objc let parentReminderID: NSObject? = nil
  @objc let assignments: NSSet? = nil
}
