import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

final class FakeWriter: PrivateFieldsWriter, @unchecked Sendable {
  private let lock = NSLock()
  private let unavailable: String?
  private let answer: PrivateFieldsWriteResult
  private var recorded: [(PrivateFieldsChange, String)] = []
  private var checked: [PrivateFieldsChange] = []

  init(unavailable: String? = nil, answer: PrivateFieldsWriteResult = .saved) {
    self.unavailable = unavailable
    self.answer = answer
  }

  var writes: [(PrivateFieldsChange, String)] {
    lock.withLock { recorded }
  }

  var checks: [PrivateFieldsChange] {
    lock.withLock { checked }
  }

  func unavailableReason(for change: PrivateFieldsChange) -> String? {
    lock.withLock { checked.append(change) }
    return unavailable
  }

  func write(_ change: PrivateFieldsChange, id: String) -> PrivateFieldsWriteResult {
    lock.withLock { recorded.append((change, id)) }
    return answer
  }
}

struct FlagReader: PrivateFieldsReader {
  var flagged = false
  var urgent = false
  var earlyReminder: EarlyReminder?
  var earlyReminderUnreadable = false
  var unavailable: String?

  func unavailableReason() -> String? { unavailable }

  func read(ids: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead {
    let fields = PrivateReminderFields(
      flagged: flagged,
      urgent: urgent,
      earlyReminder: earlyReminder,
      earlyReminderUnreadable: earlyReminderUnreadable
    )
    return .fields(Dictionary(uniqueKeysWithValues: ids.map { ($0, fields) }))
  }
}

struct MissingReminderReader: PrivateFieldsReader {
  func unavailableReason() -> String? { nil }

  func read(ids _: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead {
    .fields([:])
  }
}

struct UnavailableReader: PrivateFieldsReader {
  func unavailableReason() -> String? { nil }

  func read(ids _: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead {
    .unavailable(reason: "ReminderKit did not answer within 10 seconds")
  }
}

final class FakeStore: @unchecked Sendable {
  private let lock = NSLock()
  private var saveCount = 0

  var saves: Int {
    lock.withLock { saveCount }
  }

  func save() async throws -> ReminderItem {
    lock.withLock { saveCount += 1 }
    return ReminderItem(
      id: "R1",
      title: "Call bank",
      notes: nil,
      isCompleted: false,
      completionDate: nil,
      priority: .none,
      dueDate: nil,
      listID: "L1",
      listName: "Inbox"
    )
  }
}
