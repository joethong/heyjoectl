import Foundation
import RemindCore
import RemindPrivate

struct ReminderKitFieldsReader: PrivateFieldsReader {
  func unavailableReason() -> String? {
    RPReadUnavailableReason()
  }

  func read(ids: Set<String>, scope: ReminderFetchScope) -> PrivateFieldsRead {
    let result = RPReadReminderFields(ids, scope == .openOnly, 10)
    if let reason = result.unavailableReason {
      return .unavailable(reason: reason)
    }
    return .fields(result.fields.mapValues(Self.fields))
  }

  private static func assignment(from bridged: RPAssignment) -> ReminderAssignment {
    ReminderAssignment(
      id: bridged.assigneeID,
      displayName: bridged.displayName,
      firstName: bridged.firstName,
      lastName: bridged.lastName,
      status: bridged.status,
      assignedDate: bridged.assignedDate
    )
  }

  private static func fields(from bridged: RPReminderFields) -> PrivateReminderFields {
    var earlyReminder: EarlyReminder?
    var unreadable = false
    if let data = bridged.dueDateDeltaAlertsData {
      do {
        earlyReminder = try EarlyReminder.parse(data)
      } catch {
        unreadable = true
      }
    }
    return PrivateReminderFields(
      flagged: bridged.flagged,
      urgent: bridged.urgent,
      earlyReminder: earlyReminder,
      tags: bridged.tags,
      parentID: bridged.parentID,
      assignee: ReminderAssignee.newest(of: bridged.assignments.map(Self.assignment(from:))),
      earlyReminderUnreadable: unreadable,
      links: bridged.links
    )
  }
}

struct ReminderKitFieldsWriter: PrivateFieldsWriter {
  func unavailableReason(for change: PrivateFieldsChange) -> String? {
    RPWriteUnavailableReason(Self.bridged(change))
  }

  func write(_ change: PrivateFieldsChange, id: String) -> PrivateFieldsWriteResult {
    let result = RPWriteReminderFields(id, Self.bridged(change), 10)
    guard let reason = result.failureReason else { return .saved }
    return result.outcomeUnknown ? .unknown(reason: reason) : .failed(reason: reason)
  }

  static func bridged(_ change: PrivateFieldsChange) -> RPReminderChange {
    RPReminderChange(
      flagged: change.flagged.map { NSNumber(value: $0) },
      urgent: change.urgent.map { NSNumber(value: $0) },
      earlyReminder: change.earlyReminder.map(bridged),
      tagsToAdd: change.tags?.add ?? [],
      tagsToRemove: change.tags?.remove ?? [],
      linksToAdd: urls(change.links?.add),
      linksToRemove: urls(change.links?.remove)
    )
  }

  private static func urls(_ links: [String]?) -> [URL] {
    (links ?? []).compactMap { URL(string: $0) }
  }

  private static func bridged(_ change: EarlyReminderChange) -> RPEarlyReminderChange {
    switch change {
    case .set(let early):
      RPEarlyReminderChange(unit: early.stored.unit, count: early.stored.count)
    case .remove:
      RPEarlyReminderChange.removal()
    }
  }
}

enum PrivateFieldsSupport {
  static func attach(
    to reminders: [ReminderItem],
    scope: ReminderFetchScope,
    runtime: RuntimeOptions,
    reader: any PrivateFieldsReader = ReminderKitFieldsReader(),
    warn: (String) -> Void = Console.printError
  ) -> [ReminderItem] {
    let shown = runtime.outputFormat == .standard || runtime.outputFormat == .json
    let attachment = PrivateFields.attach(
      to: reminders,
      scope: scope,
      reader: shown && !runtime.noPrivate ? reader : nil
    )
    if let reason = attachment.unavailableReason {
      warn(
        "remindctl: private fields unavailable: \(shortReason(reason)); run `remindctl doctor` for details"
      )
    }
    warnUnreadableEarlyReminders(attachment, warn: warn)
    return attachment.reminders
  }

  static func warnUnreadableEarlyReminders(_ attachment: PrivateFieldsAttachment, warn: (String) -> Void) {
    let unreadable = attachment.unreadableEarlyReminders
    if unreadable > 0 {
      warn("remindctl: \(unreadable) Early Reminder\(unreadable == 1 ? "" : "s") could not be read")
    }
  }

  static func attachWritten(
    _ reminders: [ReminderItem],
    privateChange: PrivateFieldsChange?,
    runtime: RuntimeOptions,
    reader: any PrivateFieldsReader = ReminderKitFieldsReader(),
    warn: (String) -> Void = Console.printError
  ) -> [ReminderItem] {
    guard privateChange == nil else { return reminders }
    return attach(to: reminders, scope: .everything, runtime: runtime, reader: reader, warn: warn)
  }

  static func save(
    _ change: PrivateFieldsChange?,
    outcome: PublicSaveOutcome,
    writer: any PrivateFieldsWriter = ReminderKitFieldsWriter(),
    reader: any PrivateFieldsReader = ReminderKitFieldsReader(),
    publicSave: () async throws -> ReminderItem
  ) async throws -> ReminderItem {
    guard let change else {
      return try await publicSave()
    }
    return try await PrivateFields.save(
      change,
      writer: writer,
      reader: reader,
      outcome: outcome,
      publicSave: publicSave
    )
  }

  static func removeEarlyReminder(
    from reminder: ReminderItem,
    runtime: RuntimeOptions,
    writer: any PrivateFieldsWriter = ReminderKitFieldsWriter(),
    reader: any PrivateFieldsReader = ReminderKitFieldsReader()
  ) -> (reminder: ReminderItem, note: String?) {
    func finish(_ fields: PrivateReminderFields?, _ note: String?) -> (reminder: ReminderItem, note: String?) {
      var shown = fields.map(reminder.applying) ?? reminder
      if fields == nil {
        shown.earlyReminder = nil
      }
      return (shown, note.map { "remindctl: due date cleared, but \($0)" })
    }
    func read() -> Result<PrivateReminderFields, UnreadFields> {
      if let reason = reader.unavailableReason() {
        return .failure(UnreadFields(reason: reason))
      }
      return switch reader.read(ids: [reminder.id], scope: .everything) {
      case .unavailable(let reason):
        .failure(UnreadFields(reason: reason))
      case .fields(let byID):
        byID[reminder.id].map { .success($0) }
          ?? .failure(UnreadFields(reason: "the reminder was not found in ReminderKit"))
      }
    }

    if runtime.noPrivate {
      return finish(nil, "any Early Reminder was left: turned off by --no-private")
    }
    let before: PrivateReminderFields
    switch read() {
    case .failure(let unread):
      return finish(nil, "any Early Reminder was left: \(shortReason(unread.reason))")
    case .success(let fields):
      before = fields
    }
    guard before.earlyReminder != nil || before.earlyReminderUnreadable else {
      return finish(before, nil)
    }
    let removal = PrivateFieldsChange(earlyReminder: .remove)
    if let reason = writer.unavailableReason(for: removal) {
      return finish(before, "the Early Reminder was left: \(shortReason(reason))")
    }
    let written = writer.write(removal, id: reminder.id)
    switch read() {
    case .failure(let unread):
      let note =
        switch written {
        case .saved: "the Early Reminder removal was not read back: \(shortReason(unread.reason))"
        case .failed(let reason): "the Early Reminder was left: \(shortReason(reason))"
        case .unknown(let reason): "the Early Reminder may or may not have been removed: \(shortReason(reason))"
        }
      return finish(nil, note)
    case .success(let after):
      let left =
        after.earlyReminder.map { "Early Reminder \($0.displayString)" }
        ?? (after.earlyReminderUnreadable ? "an unreadable Early Reminder" : nil)
      guard let left else {
        return finish(after, nil)
      }
      let why =
        switch written {
        case .saved: "read back as \(left)"
        case .failed(let reason), .unknown(let reason): shortReason(reason)
        }
      return finish(after, "the Early Reminder was left: \(why)")
    }
  }

  private struct UnreadFields: Error {
    let reason: String
  }

  static func shortReason(_ reason: String, limit: Int = 100) -> String {
    let separators = [" (", ":", "\n"]
    let end = separators.compactMap { reason.range(of: $0)?.lowerBound }.min() ?? reason.endIndex
    let clause = reason[..<end].trimmingCharacters(in: .whitespaces)
    if clause.isEmpty {
      return "unknown reason"
    }
    return clause.count > limit ? String(clause.prefix(limit - 1)) + "…" : clause
  }
}

struct PrivateWritesDiagnostics: Codable, Sendable, Equatable {
  let available: Bool
  let reason: String?

  init(unavailableReason: String?) {
    available = unavailableReason == nil
    reason = unavailableReason
  }

  private enum CodingKeys: String, CodingKey {
    case available, reason
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(available, forKey: .available)
    try container.encode(reason, forKey: .reason)
  }
}

struct PrivateFieldsDiagnostics: Codable, Sendable, Equatable {
  let available: Bool
  let reason: String?
  let macOSVersion: String
  let writes: PrivateWritesDiagnostics

  init(read: PrivateFieldsRead, writes: PrivateWritesDiagnostics, macOSVersion: String) {
    switch read {
    case .fields:
      available = true
      reason = nil
    case .unavailable(let unavailableReason):
      available = false
      reason = unavailableReason
    }
    self.writes = writes
    self.macOSVersion = macOSVersion
  }

  static func collect(
    runtime: RuntimeOptions,
    authorized: Bool,
    reader: any PrivateFieldsReader = ReminderKitFieldsReader(),
    writeUnavailableReason: () -> String? = { RPWriteTableUnavailableReason() }
  ) -> PrivateFieldsDiagnostics {
    let version = ProcessInfo.processInfo.operatingSystemVersion
    let blocked: String? =
      if runtime.noPrivate {
        "turned off by --no-private"
      } else if !authorized {
        "Reminders access not granted"
      } else {
        nil
      }
    let readUnavailable = blocked == nil ? reader.unavailableReason() : nil
    let read: PrivateFieldsRead =
      if let blocked {
        .unavailable(reason: blocked)
      } else if let readUnavailable {
        .unavailable(reason: readUnavailable)
      } else {
        reader.read(ids: [], scope: .openOnly)
      }
    // A write checks its own methods, then the read-side ones (PrivateFields.save), so report both.
    let writes = blocked ?? writeUnavailableReason() ?? readUnavailable
    return PrivateFieldsDiagnostics(
      read: read,
      writes: PrivateWritesDiagnostics(unavailableReason: writes),
      macOSVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    )
  }

  var summaryLine: String {
    "Flag and Urgent (ReminderKit): " + (reason.map { "unavailable (\($0))" } ?? "available")
  }

  var writesSummaryLine: String {
    "Private writes (ReminderKit): " + (writes.reason.map { "unavailable (\($0))" } ?? "available")
  }

  private enum CodingKeys: String, CodingKey {
    case available, reason, macOSVersion, writes
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(available, forKey: .available)
    try container.encode(reason, forKey: .reason)
    try container.encode(macOSVersion, forKey: .macOSVersion)
    try container.encode(writes, forKey: .writes)
  }
}
