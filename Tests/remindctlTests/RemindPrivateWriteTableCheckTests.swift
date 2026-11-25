import Foundation
import RemindPrivate
import Testing

private struct WriteRequirement: Sendable {
  let className: String
  let selector: String
  let classMethod: Bool
  let types: String

  init(_ className: String, _ selector: String, _ types: String, classMethod: Bool = false) {
    self.className = className
    self.selector = selector
    self.types = types
    self.classMethod = classMethod
  }
}

private let writeRequirements = [
  WriteRequirement("REMObjectID", "objectIDWithURL:", "@@:@", classMethod: true),
  WriteRequirement("REMStore", "fetchReminderWithObjectID:error:", "@@:@^@"),
  WriteRequirement("REMSaveRequest", "initWithStore:", "@@:@"),
  WriteRequirement("REMSaveRequest", "updateReminder:", "@@:@"),
  WriteRequirement("REMSaveRequest", "saveSynchronouslyWithError:", "B@:^@"),
  WriteRequirement("REMReminderChangeItem", "flaggedContext", "@@:"),
  WriteRequirement("REMReminderFlaggedContextChangeItem", "setFlagged:", "v@:q"),
  WriteRequirement("REMReminderChangeItem", "urgentAlarmContext", "@@:"),
  WriteRequirement("REMReminderUrgentAlarmContextChangeItem", "setIsUrgentStateEnabledForCurrentUser:", "v@:B"),
  WriteRequirement("REMReminder", "storage", "@@:"),
  WriteRequirement("REMReminderStorage", "dueDateDeltaAlertsData", "@@:"),
  WriteRequirement("REMReminderChangeItem", "dueDateDeltaAlertContext", "@@:"),
  WriteRequirement("REMReminderDueDateDeltaAlertContextChangeItem", "removeAllFetchedDueDateDeltaAlerts", "v@:"),
  WriteRequirement("REMReminderDueDateDeltaAlertContextChangeItem", "addDueDateDeltaAlertWithDueDateDelta:", "@@:@"),
  WriteRequirement("REMReminderDueDateDeltaAlertContextChangeItem", "removeDueDateDeltaAlertsWithIdentifiers:", "v@:@"),
  WriteRequirement("REMDueDateDeltaInterval", "initWithUnit:count:", "@@:qq"),
  WriteRequirement("REMReminderStorage", "hashtags", "@@:"),
  WriteRequirement("REMHashtag", "name", "@@:"),
  WriteRequirement("REMReminderChangeItem", "hashtagContext", "@@:"),
  WriteRequirement("REMReminderHashtagContextChangeItem", "hashtags", "@@:"),
  WriteRequirement("REMReminderHashtagContextChangeItem", "addHashtagWithType:name:", "@@:q@"),
  WriteRequirement("REMReminderHashtagContextChangeItem", "removeHashtag:", "v@:@"),
  WriteRequirement("REMReminderStorage", "attachments", "@@:"),
  WriteRequirement("REMURLAttachment", "url", "@@:"),
  WriteRequirement("REMReminderChangeItem", "attachmentContext", "@@:"),
  WriteRequirement("REMReminderAttachmentContextChangeItem", "urlAttachments", "@@:"),
  WriteRequirement("REMReminderAttachmentContextChangeItem", "addURLAttachmentWithURL:", "@@:@"),
  WriteRequirement("REMReminderAttachmentContextChangeItem", "removeAttachment:", "v@:@"),
]

private let standInLock = NSLock()

private func standInClass(
  _ className: String, rows: [WriteRequirement], named name: String
) -> String {
  standInLock.withLock {
    if NSClassFromString(name) != nil {
      return name
    }
    let copy: AnyClass = objc_allocateClassPair(NSObject.self, name, 0)!
    let imp = imp_implementationWithBlock({} as @convention(block) () -> Void as Any)
    for row in rows where row.className == className {
      let target: AnyClass = row.classMethod ? object_getClass(copy)! : copy
      class_addMethod(target, sel_registerName(row.selector), imp, row.types)
    }
    objc_registerClassPair(copy)
    return name
  }
}

func writeTableStandIns(
  without: (className: String, selector: String)? = nil,
  types: (className: String, selector: String, encoding: String)? = nil
) -> [String: String] {
  var rows = writeRequirements
  var suffix = ""
  if let without {
    rows.removeAll { $0.className == without.className && $0.selector == without.selector }
    suffix = "_Without_" + without.selector.replacingOccurrences(of: ":", with: "_")
  }
  if let types {
    rows = rows.map {
      $0.className == types.className && $0.selector == types.selector
        ? WriteRequirement($0.className, $0.selector, types.encoding, classMethod: $0.classMethod) : $0
    }
    suffix = "_Types_" + types.selector.replacingOccurrences(of: ":", with: "_")
  }
  var names: [String: String] = [:]
  for className in Set(writeRequirements.map(\.className)) {
    let altered = (without?.className == className || types?.className == className) ? suffix : ""
    names[className] = standInClass(className, rows: rows, named: "RPWriteTable\(className)\(altered)")
  }
  return names
}

struct RemindPrivateWriteTableCheckTests {
  @Test("Stand-ins with every write class and method pass the whole-table check")
  func completeStandIns() {
    #expect(RPWriteTableUnavailableReasonWithClassesForTesting(writeTableStandIns()) == nil)
  }

  @Test(
    "Every write method is checked, including ones a given change would not use",
    arguments: writeRequirements.map { ($0.className, $0.selector) })
  func eachRequirementIsChecked(className: String, selector: String) {
    let names = writeTableStandIns(without: (className, selector))

    let reason = RPWriteTableUnavailableReasonWithClassesForTesting(names)

    #expect(reason == "\(names[className]!) has no \(selector)")
  }

  @Test("A write method with a changed signature makes writes unavailable")
  func changedSignature() {
    let names = writeTableStandIns(types: ("REMSaveRequest", "saveSynchronouslyWithError:", "@@:"))

    let reason = RPWriteTableUnavailableReasonWithClassesForTesting(names)

    #expect(reason == "\(names["REMSaveRequest"]!) saveSynchronouslyWithError: has an unexpected signature")
  }

  @Test("A missing ReminderKit class makes writes unavailable")
  func missingClass() {
    let names = writeTableStandIns().merging(["REMReminderAttachmentContextChangeItem": "RPNoSuchClass"]) { $1 }

    #expect(RPWriteTableUnavailableReasonWithClassesForTesting(names) == "ReminderKit has no RPNoSuchClass")
  }

  @Test("This Mac's ReminderKit has every class and method any write needs, with the expected types")
  func installedReminderKit() {
    #expect(RPWriteTableUnavailableReason() == nil)
  }
}
