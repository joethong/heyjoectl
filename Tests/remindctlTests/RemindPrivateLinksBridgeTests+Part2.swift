import Foundation
import RemindCore
import RemindPrivate
import Testing

@testable import remindctl

extension RemindPrivateLinksBridgeTests {
  @Test(
    "A flag-only write does not check the link classes or methods",
    arguments: [
      ["REMReminderAttachmentContextChangeItem": "RPNoSuchClass"],
      ["REMReminderChangeItem": "RPLinkStandInChangeItemFlagOnly"],
      ["REMReminderStorage": "RPLinkStandInStorageWithoutAttachments"],
      ["REMURLAttachment": "RPNoSuchClass"],
    ]
  )
  func flagOnlyIgnoresLinkRequirements(overrides: [String: String]) {
    let id = UUID().uuidString
    linkLog.store(id, stored: "not an array" as NSString)

    #expect(Self.write(id, flagged: true, replacing: overrides) == nil)
    #expect(linkLog.entries(for: id) == ["fetch", "setFlagged 1", "save"])
  }

  @Test(
    "Links already on the reminder that cannot be read fail the write before anything is changed or saved",
    arguments: ["stored not an array", "stored url not a URL", "change not an array", "change url not a URL"]
  )
  func unreadableLinksFail(shape: String) {
    let unreadable: [String: (AnyObject, AnyObject?)] = [
      "stored not an array": ("x" as NSString, nil),
      "stored url not a URL": ([LinkStandInURLAttachment(7 as NSNumber, source: "stored")] as NSArray, nil),
      "change not an array": (NSArray(), "x" as NSString),
      "change url not a URL": (NSArray(), [LinkStandInURLAttachment(NSNull(), source: "context")] as NSArray),
    ]
    let id = UUID().uuidString
    let (stored, inContext) = unreadable[shape]!
    linkLog.store(id, stored: stored, inContext: inContext)

    #expect(
      Self.write(id, flagged: true, add: ["https://a.example"])
        == "the links already on the reminder could not be read"
    )
    #expect(linkLog.entries(for: id) == ["fetch"])
  }

  @Test("A reminder with no storage fails a link write before any change")
  func noStorageFails() {
    #expect(
      Self.write(linkNoStorageID, remove: ["https://a.example"])
        == "the links already on the reminder could not be read"
    )
    #expect(linkLog.entries(for: linkNoStorageID).last == "fetch")
  }

  @Test("This Mac's ReminderKit has every class and method a link write needs, with the expected types")
  func installedReminderKit() {
    let change = ReminderKitFieldsWriter.bridged(
      PrivateFieldsChange(links: LinksChange(add: ["https://a.example"], remove: ["https://b.example"]))
    )

    #expect(RPWriteUnavailableReason(change) == nil)
  }

  @Test("No attachment context, or no attachment from ReminderKit, fails the link write without saving")
  func nilAnswersFail() {
    #expect(
      Self.write(linkNoContextID, add: ["https://a.example"])
        == "REMReminderChangeItem attachmentContext returned no link change"
    )
    #expect(!linkLog.entries(for: linkNoContextID).contains("save"))

    #expect(
      Self.write(linkAddFailsID, add: ["https://a.example"])
        == "REMReminderAttachmentContextChangeItem addURLAttachmentWithURL: returned no link"
    )
    #expect(!linkLog.entries(for: linkAddFailsID).contains("save"))
  }
}
