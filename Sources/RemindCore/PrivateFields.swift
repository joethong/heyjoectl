import Foundation

public struct PrivateReminderFields: Sendable, Equatable {
  public let flagged: Bool?
  public let urgent: Bool?
  public let earlyReminder: EarlyReminder?
  public let tags: [String]?
  public let parentID: String?
  public let assignee: ReminderAssignee?
  public let earlyReminderUnreadable: Bool
  public let links: [String]?

  public init(
    flagged: Bool? = nil,
    urgent: Bool? = nil,
    earlyReminder: EarlyReminder? = nil,
    tags: [String]? = nil,
    parentID: String? = nil,
    assignee: ReminderAssignee? = nil,
    earlyReminderUnreadable: Bool = false,
    links: [String]? = nil
  ) {
    self.flagged = flagged
    self.urgent = urgent
    self.earlyReminder = earlyReminder
    self.tags = tags
    self.parentID = parentID
    self.assignee = assignee
    self.earlyReminderUnreadable = earlyReminderUnreadable
    self.links = links
  }
}

public enum PrivateFieldsRead: Sendable, Equatable {
  case fields([String: PrivateReminderFields])
  case unavailable(reason: String)
}

public protocol PrivateFieldsReader: Sendable {
  func unavailableReason() -> String?
  func read(ids: Set<String>, scope: ReminderFetchScope) -> PrivateFieldsRead
}

public struct PrivateFieldsAttachment: Sendable, Equatable {
  public let reminders: [ReminderItem]
  public let unavailableReason: String?
  public let unreadableEarlyReminders: Int

  public init(reminders: [ReminderItem], unavailableReason: String?, unreadableEarlyReminders: Int = 0) {
    self.reminders = reminders
    self.unavailableReason = unavailableReason
    self.unreadableEarlyReminders = unreadableEarlyReminders
  }
}

public enum PrivateFields {
  public static func attach(
    to reminders: [ReminderItem],
    scope: ReminderFetchScope,
    reader: (any PrivateFieldsReader)?
  ) -> PrivateFieldsAttachment {
    guard let reader, !reminders.isEmpty else {
      return PrivateFieldsAttachment(reminders: reminders, unavailableReason: nil)
    }
    switch reader.read(ids: Set(reminders.map(\.id)), scope: scope) {
    case .unavailable(let reason):
      return PrivateFieldsAttachment(reminders: reminders, unavailableReason: reason)
    case .fields(let byID):
      let attached = reminders.map { reminder in
        byID[reminder.id].map(reminder.applying) ?? reminder
      }
      let unreadable = reminders.filter { byID[$0.id]?.earlyReminderUnreadable == true }.count
      return PrivateFieldsAttachment(
        reminders: attached, unavailableReason: nil, unreadableEarlyReminders: unreadable)
    }
  }
}

extension ReminderItem {
  public func applying(_ fields: PrivateReminderFields) -> ReminderItem {
    var copy = self
    copy.flagged = fields.flagged
    copy.urgent = fields.urgent
    copy.earlyReminder = fields.earlyReminder
    copy.tags = fields.tags?.sorted()
    copy.parentID = fields.parentID
    copy.assignee = fields.assignee
    copy.links = fields.links?.isEmpty == false ? fields.links : nil
    return copy
  }
}

public struct ReminderAssignment: Sendable, Equatable {
  public let id: String
  public let displayName: String?
  public let firstName: String?
  public let lastName: String?
  public let status: Int
  public let assignedDate: Date?

  public init(
    id: String, displayName: String?, firstName: String?, lastName: String?, status: Int, assignedDate: Date?
  ) {
    self.id = id
    self.displayName = displayName
    self.firstName = firstName
    self.lastName = lastName
    self.status = status
    self.assignedDate = assignedDate
  }

  public var assignee: ReminderAssignee {
    ReminderAssignee(id: id, name: name, status: status)
  }

  private var name: String? {
    if let displayName = Self.present(displayName) {
      return displayName
    }
    let parts = [Self.present(firstName), Self.present(lastName)].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " ")
  }

  private static func present(_ text: String?) -> String? {
    guard let text, !text.isEmpty else { return nil }
    return text
  }
}

extension ReminderAssignee {
  public static func newest(of assignments: [ReminderAssignment]) -> ReminderAssignee? {
    assignments.max {
      ($0.assignedDate ?? .distantPast, $0.id) < ($1.assignedDate ?? .distantPast, $1.id)
    }?.assignee
  }
}
