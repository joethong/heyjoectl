import Foundation
import RemindCore
import RemindPrivate
import Testing

@testable import remindctl

struct RemindPrivateLinksBridgeTests {
  static let standIns = [
    "REMObjectID": "RPLinkStandInObjectID",
    "REMStore": "RPLinkStandInStore",
    "REMReminder": "RPLinkStandInReminder",
    "REMReminderStorage": "RPLinkStandInStorage",
    "REMSaveRequest": "RPLinkStandInSaveRequest",
    "REMReminderChangeItem": "RPLinkStandInChangeItem",
    "REMReminderFlaggedContextChangeItem": "RPLinkStandInFlaggedContext",
    "REMReminderAttachmentContextChangeItem": "RPLinkStandInAttachmentContext",
    "REMURLAttachment": "RPLinkStandInURLAttachment",
  ]

  static func write(
    _ id: String,
    flagged: Bool? = nil,
    add: [String] = [],
    remove: [String] = [],
    replacing overrides: [String: String] = [:]
  ) -> String? {
    let links = add.isEmpty && remove.isEmpty ? nil : LinksChange(add: add, remove: remove)
    let change = ReminderKitFieldsWriter.bridged(PrivateFieldsChange(flagged: flagged, links: links))
    let result = RPWriteWithClassesForTesting(standIns.merging(overrides) { $1 }, id, change, 10)
    #expect(!result.outcomeUnknown)
    return result.failureReason
  }

  static func attachments(_ urls: [String], _ source: String) -> NSArray {
    urls.map { LinkStandInURLAttachment(NSURL(string: $0), source: source) } as NSArray
  }

  static func read(_ storage: NSObject) -> RPReadResult {
    let id = UUID()
    let store = LinkReadStore([LinkReadReminder(id: id, storage: storage)])
    let result = RPReadStoreForTesting(store, [id.uuidString], false, standIns)
    #expect(result.fields.count == (result.unavailableReason == nil ? 1 : 0))
    return result
  }

  @Test("Links are read from the URL attachments in stored order; other attachments are skipped")
  func readsLinksInOrder() {
    let attachments: NSArray = [
      LinkStandInURLAttachment(NSURL(string: "https://z.example"), source: "stored"),
      LinkStandInFileAttachment(),
      LinkStandInURLAttachment(NSURL(string: "mailto:j@x.example"), source: "stored"),
    ]

    let result = Self.read(LinkReadStorage(attachments: attachments))

    #expect(result.unavailableReason == nil)
    #expect(result.fields.values.first?.links == ["https://z.example", "mailto:j@x.example"])
    #expect(result.fields.values.first?.flagged == true)
  }

  @Test("An attachment of another class is not a link, even when it answers url")
  func readsOnlyURLAttachmentClass() {
    let attachments: NSArray = [
      LinkStandInImageAttachment(),
      LinkStandInURLAttachment(NSURL(string: "https://a.example"), source: "stored"),
    ]

    #expect(Self.read(LinkReadStorage(attachments: attachments)).fields.values.first?.links == ["https://a.example"])
  }

  @Test("A ReminderKit with no URL attachment class leaves links unknown but keeps the other private fields")
  func readWithoutURLAttachmentClass() {
    let id = UUID()
    let storage = LinkReadStorage(attachments: Self.attachments(["https://a.example"], "stored"))
    let store = LinkReadStore([LinkReadReminder(id: id, storage: storage)])

    let result = RPReadStoreForTesting(
      store,
      [id.uuidString],
      false,
      Self.standIns.merging(["REMURLAttachment": "RPNoSuchClass"]) { $1 }
    )

    #expect(result.unavailableReason == nil)
    #expect(result.fields.values.first?.links == nil)
    #expect(result.fields.values.first?.flagged == true)
  }

  @Test("No attachments read as no links")
  func noAttachments() {
    #expect(Self.read(LinkReadStorage(attachments: nil)).fields.values.first?.links == [])
    #expect(Self.read(LinkReadStorage(attachments: NSArray())).fields.values.first?.links == [])
  }

  @Test(
    "Attachments that cannot be read leave links unknown but keep the other private fields",
    arguments: ["not an array", "url not a URL"]
  )
  func unreadableAttachments(shape: String) {
    let attachments: AnyObject =
      shape == "not an array" ? "x" as NSString : [LinkStandInURLAttachment("x" as NSString, source: "s")] as NSArray

    let result = Self.read(LinkReadStorage(attachments: attachments))

    #expect(result.unavailableReason == nil)
    #expect(result.fields.values.first?.links == nil)
    #expect(result.fields.values.first?.flagged == true)
  }

  @Test("A storage with no attachments method leaves links unknown but keeps the other private fields")
  func storageWithoutAttachments() {
    let result = Self.read(LinkReadStorageWithoutAttachments())

    #expect(result.unavailableReason == nil)
    #expect(result.fields.values.first?.links == nil)
    #expect(result.fields.values.first?.flagged == true)
  }

  @Test("Links the reminder does not have are added in one save")
  func addsNewLinks() {
    let id = UUID().uuidString
    linkLog.store(id, stored: nil)

    #expect(Self.write(id, add: ["https://a.example", "mailto:j@x.example"]) == nil)
    #expect(linkLog.entries(for: id) == ["fetch", "add https://a.example", "add mailto:j@x.example", "save"])
  }

  @Test("A link the reminder already has, stored or in the change, is not added again")
  func repeatAddDoesNotDuplicate() {
    let stored = UUID().uuidString
    let inContext = UUID().uuidString
    linkLog.store(stored, stored: Self.attachments(["https://a.example"], "stored"))
    linkLog.store(inContext, stored: NSArray(), inContext: Self.attachments(["https://a.example"], "context"))

    #expect(Self.write(stored, add: ["https://a.example", "https://b.example"]) == nil)
    #expect(Self.write(inContext, add: ["https://a.example"]) == nil)
    #expect(linkLog.entries(for: stored) == ["fetch", "add https://b.example", "save"])
    #expect(linkLog.entries(for: inContext) == ["fetch", "save"])
  }

  @Test("--unlink removes each matching attachment one by one, stored and in the change, and leaves the others")
  func removesMatchingLinks() {
    let id = UUID().uuidString
    linkLog.store(
      id,
      stored: Self.attachments(["https://a.example", "https://b.example"], "stored"),
      inContext: Self.attachments(["https://a.example"], "context")
    )

    #expect(Self.write(id, remove: ["https://a.example"]) == nil)
    let entries = linkLog.entries(for: id)
    #expect(entries.first == "fetch")
    #expect(entries.last == "save")
    #expect(
      Set(entries.dropFirst().dropLast())
        == ["remove https://a.example (stored)", "remove https://a.example (context)"]
    )
  }

  @Test("Links match with the scheme and host in any case, and the path as written")
  func caseInsensitiveSchemeAndHost() {
    let adding = UUID().uuidString
    let removing = UUID().uuidString
    linkLog.store(adding, stored: Self.attachments(["https://example.com"], "stored"))
    linkLog.store(removing, stored: Self.attachments(["https://example.com/a", "https://example.com/A"], "stored"))

    #expect(Self.write(adding, add: ["HTTPS://Example.com"]) == nil)
    #expect(Self.write(removing, remove: ["https://EXAMPLE.com/a"]) == nil)
    #expect(linkLog.entries(for: adding) == ["fetch", "save"])
    #expect(linkLog.entries(for: removing) == ["fetch", "remove https://example.com/a (stored)", "save"])
  }

  @Test("--unlink removes a stored link of any scheme, such as tel: or an app's own")
  func removesAnyScheme() {
    let id = UUID().uuidString
    linkLog.store(id, stored: Self.attachments(["tel:+15551234567", "x-app://item/7", "https://a.example"], "stored"))

    #expect(Self.write(id, remove: ["tel:+15551234567", "x-app://item/7"]) == nil)
    #expect(
      linkLog.entries(for: id)
        == ["fetch", "remove tel:+15551234567 (stored)", "remove x-app://item/7 (stored)", "save"]
    )
  }

  @Test("--unlink never removes an attachment of another class, even one that answers url")
  func keepsOtherAttachments() {
    let id = UUID().uuidString
    linkLog.store(
      id,
      stored: [LinkStandInImageAttachment()] as NSArray,
      inContext: [LinkStandInImageAttachment()] as NSArray
    )

    #expect(Self.write(id, remove: ["file:///tmp/photo.jpg"]) == nil)
    #expect(linkLog.entries(for: id) == ["fetch", "save"])
  }

  @Test("A write that does not touch links never reads the reminder's storage for them")
  func flagOnlyDoesNotReadStorage() {
    let flagOnly = UUID().uuidString
    let linking = UUID().uuidString
    linkLog.store(linking, stored: nil)

    #expect(Self.write(flagOnly, flagged: true) == nil)
    #expect(Self.write(linking, flagged: true, add: ["https://a.example"]) == nil)
    #expect(linkLog.entries(for: flagOnly) == ["fetch", "setFlagged 1", "save"])
    #expect(linkLog.storageReads(for: flagOnly) == 0)
    #expect(linkLog.storageReads(for: linking) == 1)
  }

  @Test("--unlink of a link the reminder does not have removes nothing and still saves")
  func removingAbsentLink() {
    let id = UUID().uuidString
    linkLog.store(id, stored: Self.attachments(["https://b.example"], "stored"))

    #expect(Self.write(id, remove: ["https://a.example"]) == nil)
    #expect(linkLog.entries(for: id) == ["fetch", "save"])
  }

  @Test("The flag, a removal and an addition go in the same change and one save")
  func combinedWrite() {
    let id = UUID().uuidString
    linkLog.store(id, stored: Self.attachments(["https://a.example"], "stored"))

    #expect(Self.write(id, flagged: true, add: ["https://b.example"], remove: ["https://a.example"]) == nil)
    #expect(
      linkLog.entries(for: id)
        == ["fetch", "setFlagged 1", "remove https://a.example (stored)", "add https://b.example", "save"]
    )
  }

  @Test(
    "A link write with a missing class, method or type, write or read side, is refused before anything is fetched",
    arguments: [
      (["REMReminderAttachmentContextChangeItem": "RPNoSuchClass"], "ReminderKit has no RPNoSuchClass"),
      (
        ["REMReminderChangeItem": "RPLinkStandInChangeItemFlagOnly"],
        "RPLinkStandInChangeItemFlagOnly has no attachmentContext"
      ),
      (
        ["REMReminderStorage": "RPLinkStandInStorageWithoutAttachments"],
        "RPLinkStandInStorageWithoutAttachments has no attachments"
      ),
      (["REMURLAttachment": "RPLinkStandInURLAttachmentWithoutURL"], "RPLinkStandInURLAttachmentWithoutURL has no url"),
    ]
  )
  func refusesBeforeAnyCall(overrides: [String: String], reason: String) {
    let adding = UUID().uuidString
    let removing = UUID().uuidString

    #expect(Self.write(adding, add: ["https://a.example"], replacing: overrides) == reason)
    #expect(Self.write(removing, flagged: true, remove: ["https://a.example"], replacing: overrides) == reason)
    #expect(linkLog.entries(for: adding).isEmpty)
    #expect(linkLog.entries(for: removing).isEmpty)
  }

  @Test("A missing removeAttachment: refuses --unlink but not --link")
  func removeNeededOnlyToRemove() {
    let adding = UUID().uuidString
    let removing = UUID().uuidString
    let overrides = ["REMReminderAttachmentContextChangeItem": "RPLinkStandInAttachmentContextWithoutRemove"]

    #expect(
      Self.write(removing, remove: ["https://a.example"], replacing: overrides)
        == "RPLinkStandInAttachmentContextWithoutRemove has no removeAttachment:"
    )
    #expect(linkLog.entries(for: removing).isEmpty)
    #expect(Self.write(adding, add: ["https://a.example"], replacing: overrides) == nil)
    #expect(linkLog.entries(for: adding).last == "save")
  }

  @Test("A changed addURLAttachmentWithURL: refuses --link but not --unlink")
  func addNeededOnlyToAdd() {
    let adding = UUID().uuidString
    let removing = UUID().uuidString
    let overrides = ["REMReminderAttachmentContextChangeItem": "RPLinkStandInAttachmentContextAddingText"]

    #expect(
      Self.write(adding, add: ["https://a.example"], replacing: overrides)
        == "RPLinkStandInAttachmentContextAddingText addURLAttachmentWithURL: has an unexpected signature"
    )
    #expect(linkLog.entries(for: adding).isEmpty)
    #expect(Self.write(removing, remove: ["https://a.example"], replacing: overrides) == nil)
    #expect(linkLog.entries(for: removing).last == "save")
  }
}
