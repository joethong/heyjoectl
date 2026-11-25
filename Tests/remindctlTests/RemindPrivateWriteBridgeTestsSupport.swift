import Foundation
import RemindCore
import RemindPrivate
import Testing

@testable import remindctl

final class WriteLog: @unchecked Sendable {
  private let lock = NSLock()
  private var entries: [String: [String]] = [:]

  func record(_ id: String, _ entry: String) {
    lock.withLock { entries[id, default: []].append(entry) }
  }

  func entries(for id: String) -> [String] {
    lock.withLock { entries[id] ?? [] }
  }
}

let writeLog = WriteLog()

final class StoredAlerts: @unchecked Sendable {
  private let lock = NSLock()
  private var data: [String: AnyObject] = [:]

  func set(_ id: String, _ value: AnyObject) {
    lock.withLock { data[id] = value }
  }

  func data(for id: String) -> AnyObject? {
    lock.withLock { data[id] }
  }
}

let storedAlerts = StoredAlerts()
let writeNoStorageID = "00000000-0000-0000-0000-0000000005E0"
let fetchFailsID = "00000000-0000-0000-0000-00000000FE7C"
let saveFailsID = "00000000-0000-0000-0000-0000000005A7"
let fetchFindsNothingID = "00000000-0000-0000-0000-00000000F000"
let saveSaysNoID = "00000000-0000-0000-0000-0000000005A0"
let saveIsSlowID = "00000000-0000-0000-0000-000000005100"
let saveRaisesID = "00000000-0000-0000-0000-0000000005E5"
let addAlertFailsID = "00000000-0000-0000-0000-00000000A1E7"
let noAlertContextID = "00000000-0000-0000-0000-00000000C0E7"

@objc(RPStandInObjectID)
final class StandInObjectID: NSObject {
  @objc(objectIDWithURL:)
  static func objectID(with url: NSURL) -> AnyObject? {
    url
  }
}

@objc(RPStandInReminderStorage)
final class StandInReminderStorage: NSObject {
  @objc let dueDateDeltaAlertsData: AnyObject?

  init(dueDateDeltaAlertsData: AnyObject?) {
    self.dueDateDeltaAlertsData = dueDateDeltaAlertsData
  }
}

@objc(RPStandInReminder)
final class StandInReminder: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc var storage: StandInReminderStorage? {
    id == writeNoStorageID ? nil : StandInReminderStorage(dueDateDeltaAlertsData: storedAlerts.data(for: id))
  }
}

@objc(RPStandInReminderWithoutStorage)
final class StandInReminderWithoutStorage: NSObject {}

@objc(RPStandInReminderStorageWithoutAlerts)
final class StandInReminderStorageWithoutAlerts: NSObject {}

@objc(RPStandInStore)
final class WriteStandInStore: NSObject {
  @objc(fetchReminderWithObjectID:error:)
  func fetchReminder(_ objectID: AnyObject, _ error: NSErrorPointer) -> AnyObject? {
    guard let url = objectID as? URL else { return nil }
    let id = url.lastPathComponent
    writeLog.record(id, "fetch \(url.absoluteString)")
    if id == fetchFindsNothingID {
      return nil
    }
    if id == fetchFailsID {
      error?.pointee = NSError(domain: "StandIn", code: 1, userInfo: [NSLocalizedDescriptionKey: "no such reminder"])
    }
    return StandInReminder(id: id)
  }
}

@objc(RPStandInFlaggedContext)
final class StandInFlaggedContext: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc(setFlagged:)
  func setFlagged(_ flagged: Int) {
    writeLog.record(id, "setFlagged \(flagged)")
  }
}

@objc(RPStandInUrgentContext)
final class StandInUrgentContext: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc(setIsUrgentStateEnabledForCurrentUser:)
  func setUrgent(_ urgent: Bool) {
    writeLog.record(id, "setUrgent \(urgent)")
  }
}

@objc(RPStandInDueDateDeltaInterval)
final class StandInDueDateDeltaInterval: NSObject {
  let unit: Int
  let count: Int

  @objc(initWithUnit:count:)
  init(unit: Int, count: Int) {
    self.unit = unit
    self.count = count
    super.init()
  }
}

@objc(RPStandInDueDateDeltaIntervalTakingInt32)
final class StandInDueDateDeltaIntervalTakingInt32: NSObject {
  @objc(initWithUnit:count:)
  init(unit _: Int32, count _: Int32) {
    super.init()
  }
}

@objc(RPStandInDueDateDeltaIntervalReturningNil)
final class StandInDueDateDeltaIntervalReturningNil: NSObject {
  @objc(initWithUnit:count:)
  init?(unit _: Int, count _: Int) {
    nil
  }
}

@objc(RPStandInDueDateDeltaAlertContext)
final class StandInDueDateDeltaAlertContext: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc(removeAllFetchedDueDateDeltaAlerts)
  func removeAll() {
    writeLog.record(id, "removeAllFetchedDueDateDeltaAlerts")
  }

  @objc(removeDueDateDeltaAlertsWithIdentifiers:)
  func removeAlerts(_ identifiers: NSArray) {
    let ids = identifiers.map { ($0 as? NSUUID)?.uuidString ?? "not a UUID" }
    writeLog.record(id, "removeAlerts \(ids.joined(separator: " "))")
  }

  @objc(addDueDateDeltaAlertWithDueDateDelta:)
  func addAlert(_ delta: AnyObject) -> AnyObject? {
    guard let delta = delta as? StandInDueDateDeltaInterval else { return nil }
    writeLog.record(id, "addAlert \(delta.unit) \(delta.count)")
    return id == addAlertFailsID ? nil : NSObject()
  }
}

@objc(RPStandInDeltaContextNoRemoveByID)
final class StandInDeltaContextNoRemoveByID: NSObject {
  @objc(removeAllFetchedDueDateDeltaAlerts)
  func removeAll() {}

  @objc(addDueDateDeltaAlertWithDueDateDelta:)
  func addAlert(_ delta: AnyObject) -> AnyObject? {
    NSObject()
  }
}

@objc(RPStandInDeltaContextRemovingByString)
final class StandInDeltaContextRemovingByString: NSObject {
  @objc(removeAllFetchedDueDateDeltaAlerts)
  func removeAll() {}

  @objc(addDueDateDeltaAlertWithDueDateDelta:)
  func addAlert(_ delta: AnyObject) -> AnyObject? {
    NSObject()
  }

  @objc(removeDueDateDeltaAlertsWithIdentifiers:)
  func removeAlerts(_ identifiers: Int) {}
}

@objc(RPStandInDeltaContextNoAdd)
final class StandInDeltaContextNoAdd: NSObject {
  @objc(removeAllFetchedDueDateDeltaAlerts)
  func removeAll() {}
}

@objc(RPStandInChangeItem)
final class StandInChangeItem: NSObject {
  let id: String

  init(id: String) {
    self.id = id
  }

  @objc(flaggedContext)
  func flaggedContext() -> AnyObject? {
    StandInFlaggedContext(id: id)
  }

  @objc(urgentAlarmContext)
  func urgentAlarmContext() -> AnyObject? {
    StandInUrgentContext(id: id)
  }

  @objc(dueDateDeltaAlertContext)
  func dueDateDeltaAlertContext() -> AnyObject? {
    id == noAlertContextID ? nil : StandInDueDateDeltaAlertContext(id: id)
  }
}

@objc(RPStandInChangeItemWithoutUrgent)
final class StandInChangeItemWithoutUrgent: NSObject {
  @objc(flaggedContext)
  func flaggedContext() -> AnyObject? {
    nil
  }
}

@objc(RPStandInChangeItemFlagOnly)
final class StandInChangeItemFlagOnly: NSObject {
  @objc(flaggedContext)
  func flaggedContext() -> AnyObject? {
    nil
  }
}

@objc(RPStandInUrgentOnlyChangeItem)
final class StandInUrgentOnlyChangeItem: NSObject {
  @objc(urgentAlarmContext)
  func urgentAlarmContext() -> AnyObject? {
    nil
  }
}

@objc(RPStandInUrgentContextTakingInteger)
final class StandInUrgentContextTakingInteger: NSObject {
  @objc(setIsUrgentStateEnabledForCurrentUser:)
  func setUrgent(_ urgent: Int) {}
}

@objc(RPStandInSaveRequest)
final class StandInSaveRequest: NSObject {
  var id = ""

  @objc(initWithStore:)
  init(store _: AnyObject) {
    super.init()
  }

  @objc(updateReminder:)
  func update(_ reminder: AnyObject) -> AnyObject? {
    guard let reminder = reminder as? StandInReminder else { return nil }
    id = reminder.id
    return StandInChangeItem(id: id)
  }

  @objc(saveSynchronouslyWithError:)
  func save(_ error: NSErrorPointer) -> Bool {
    writeLog.record(id, "save")
    if id == saveIsSlowID {
      Thread.sleep(forTimeInterval: 1)
    }
    if id == saveRaisesID {
      NSException(name: .internalInconsistencyException, reason: "store went away").raise()
    }
    if id == saveFailsID {
      error?.pointee = NSError(domain: "StandIn", code: 2, userInfo: [NSLocalizedDescriptionKey: "the store is locked"])
    }
    return id != saveSaysNoID
  }
}

@objc(RPStandInSaveRequestWithoutSave)
final class StandInSaveRequestWithoutSave: NSObject {
  @objc(initWithStore:)
  init(store _: AnyObject) {
    super.init()
  }

  @objc(updateReminder:)
  func update(_ reminder: AnyObject) -> AnyObject? {
    nil
  }
}

@objc(RPStandInFlaggedContextTakingBool)
final class StandInFlaggedContextTakingBool: NSObject {
  @objc(setFlagged:)
  func setFlagged(_ flagged: Bool) {}
}
