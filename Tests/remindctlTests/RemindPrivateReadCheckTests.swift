import Foundation
import RemindPrivate
import Testing

@objc(RPReadCheckStandInStoreWithoutReminders)
private final class ReadCheckStandInStoreWithoutReminders: NSObject {
  @objc(fetchListsForEventKitBridgingWithError:)
  func fetchLists() throws -> NSArray {
    []
  }
}

@objc(RPReadCheckStandInStoreWithWrongSignature)
private final class ReadCheckStandInStoreWithWrongSignature: NSObject {
  @objc(fetchListsForEventKitBridgingWithError:)
  func fetchLists(_ count: Int) -> NSArray {
    []
  }
}

@objc(RPReadCheckStore)
private final class ReadCheckStore: NSObject {
  @objc(fetchListsForEventKitBridgingWithError:)
  func fetchLists() throws -> NSArray {
    []
  }

  @objc(fetchRemindersForEventKitBridgingWithListIDs:error:)
  func fetchReminders(_ listIDs: NSArray) throws -> NSArray {
    []
  }
}

@objc(RPReadCheckListStorage)
private final class ReadCheckListStorage: NSObject {
  @objc var objectID: NSObject?
}

@objc(RPReadCheckObjectID)
private final class ReadCheckObjectID: NSObject {
  @objc var uuid: NSObject?
}

@objc(RPReadCheckReminder)
private final class ReadCheckReminder: NSObject {
  @objc var storage: NSObject?
}

@objc(RPReadCheckReminderStorage)
private final class ReadCheckReminderStorage: NSObject {
  @objc var objectID: NSObject?
  @objc var flagged = 0
  @objc var isUrgentStateEnabledForCurrentUser = false
  @objc var hashtags: NSObject?
  @objc var dueDateDeltaAlertsData: NSObject?
  @objc var parentReminderID: NSObject?
  @objc var assignments: NSObject?
}

@objc(RPReadCheckHashtag)
private final class ReadCheckHashtag: NSObject {
  @objc var name: NSObject?
}

@objc(RPReadCheckAssignment)
private final class ReadCheckAssignment: NSObject {
  @objc var assigneeID: NSObject?
  @objc var status = 0
  @objc var assignedDate: NSObject?
}

private let readStandIns = [
  "REMStore": "RPReadCheckStore",
  "REMListStorage": "RPReadCheckListStorage",
  "REMObjectID": "RPReadCheckObjectID",
  "REMReminder": "RPReadCheckReminder",
  "REMReminderStorage": "RPReadCheckReminderStorage",
  "REMHashtag": "RPReadCheckHashtag",
  "REMAssignment": "RPReadCheckAssignment",
]

private func standIn(_ className: String, without selector: String) -> String {
  let base: AnyClass = NSClassFromString(readStandIns[className]!)!
  let name = "RPReadCheck\(className)Without_\(selector.replacingOccurrences(of: ":", with: "_"))"
  if let existing = NSClassFromString(name) {
    return NSStringFromClass(existing)
  }
  let copy: AnyClass = objc_allocateClassPair(NSObject.self, name, 0)!
  var count: UInt32 = 0
  let methods = class_copyMethodList(base, &count)!
  for method in UnsafeBufferPointer(start: methods, count: Int(count))
  where NSStringFromSelector(method_getName(method)) != selector {
    class_addMethod(copy, method_getName(method), method_getImplementation(method), method_getTypeEncoding(method))
  }
  free(methods)
  objc_registerClassPair(copy)
  return name
}

struct RemindPrivateReadCheckTests {
  @Test("Stand-ins with every read class and method pass the read-side check")
  func completeStandIns() {
    #expect(RPReadUnavailableReasonWithClassesForTesting(readStandIns) == nil)
  }

  @Test(
    "Each class and method the read uses is checked before any save",
    arguments: [
      ("REMStore", "fetchListsForEventKitBridgingWithError:"),
      ("REMStore", "fetchRemindersForEventKitBridgingWithListIDs:error:"),
      ("REMListStorage", "objectID"),
      ("REMObjectID", "uuid"),
      ("REMReminder", "storage"),
      ("REMReminderStorage", "objectID"),
      ("REMReminderStorage", "flagged"),
      ("REMReminderStorage", "isUrgentStateEnabledForCurrentUser"),
      ("REMReminderStorage", "hashtags"),
      ("REMReminderStorage", "dueDateDeltaAlertsData"),
      ("REMReminderStorage", "parentReminderID"),
      ("REMReminderStorage", "assignments"),
      ("REMHashtag", "name"),
      ("REMAssignment", "assigneeID"),
      ("REMAssignment", "status"),
      ("REMAssignment", "assignedDate"),
    ])
  func eachRequirementIsChecked(className: String, selector: String) {
    let missing = standIn(className, without: selector)
    let reason = RPReadUnavailableReasonWithClassesForTesting(
      readStandIns.merging([className: missing]) { $1 })

    #expect(reason == "\(missing) has no \(selector)")
  }

  @Test("A missing read selector makes the read side unavailable, naming the selector")
  func missingSelector() {
    let reason = RPReadUnavailableReasonWithClassesForTesting([
      "REMStore": "RPReadCheckStandInStoreWithoutReminders"
    ])

    #expect(
      reason == "RPReadCheckStandInStoreWithoutReminders has no fetchRemindersForEventKitBridgingWithListIDs:error:")
  }

  @Test("A read selector with a changed signature makes the read side unavailable")
  func changedSignature() {
    let reason = RPReadUnavailableReasonWithClassesForTesting([
      "REMStore": "RPReadCheckStandInStoreWithWrongSignature"
    ])

    let method = "RPReadCheckStandInStoreWithWrongSignature fetchListsForEventKitBridgingWithError:"
    #expect(reason == "\(method) has an unexpected signature")
  }

  @Test("A missing ReminderKit class makes the read side unavailable")
  func missingClass() {
    let reason = RPReadUnavailableReasonWithClassesForTesting(["REMStore": "RPReadCheckNoSuchClass"])

    #expect(reason == "ReminderKit has no RPReadCheckNoSuchClass")
  }

  @Test("This Mac's ReminderKit has every class and method the read needs")
  func installedReminderKit() {
    #expect(RPReadUnavailableReason() == nil)
  }
}
