import Foundation

public struct TagsChange: Sendable, Equatable {
  public let add: [String]
  public let remove: [String]

  public init(add: [String] = [], remove: [String] = []) {
    self.add = add
    self.remove = remove
  }

  fileprivate var fields: [(name: String, verb: String)] {
    [(add, "added"), (remove, "removed")].filter { !$0.0.isEmpty }.map { names, verb in
      ((names.count == 1 ? "tag " : "tags ") + names.joined(separator: ", "), verb)
    }
  }

  fileprivate func applied(to tags: [String]) -> [String] {
    func named(_ name: String) -> (String) -> Bool {
      { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
    var result = tags.filter { tag in !remove.contains(where: named(tag)) }
    result += add.filter { !result.contains(where: named($0)) }
    return result
  }

  fileprivate static func sameTags(_ left: [String], _ right: [String]) -> Bool {
    left.map { $0.lowercased() }.sorted() == right.map { $0.lowercased() }.sorted()
  }
}

public struct LinksChange: Sendable, Equatable {
  public let add: [String]
  public let remove: [String]

  public init(add: [String] = [], remove: [String] = []) {
    self.add = add
    self.remove = remove
  }

  fileprivate var fields: [(name: String, verb: String)] {
    [(add, "added"), (remove, "removed")].filter { !$0.0.isEmpty }.map { links, verb in
      ((links.count == 1 ? "link " : "links ") + links.joined(separator: ", "), verb)
    }
  }

  fileprivate func applied(to links: [String]) -> [String] {
    let kept = links.filter { link in !remove.contains { Self.sameLink($0, link) } }
    return kept + add.filter { link in !kept.contains { Self.sameLink($0, link) } }
  }

  public static func sameLink(_ left: String, _ right: String) -> Bool {
    key(left) == key(right)
  }

  fileprivate static func sameLinks(_ left: [String], _ right: [String]) -> Bool {
    left.map(key).sorted() == right.map(key).sorted()
  }

  private static func key(_ link: String) -> String {
    guard var parts = URLComponents(string: link) else { return link }
    parts.scheme = parts.scheme?.lowercased()
    parts.percentEncodedHost = parts.percentEncodedHost?.lowercased()
    return parts.string ?? link
  }
}

public struct PrivateFieldsChange: Sendable, Equatable {
  public let flagged: Bool?
  public let urgent: Bool?
  public let earlyReminder: EarlyReminderChange?
  public let tags: TagsChange?
  public let links: LinksChange?

  public init(
    flagged: Bool? = nil,
    urgent: Bool? = nil,
    earlyReminder: EarlyReminderChange? = nil,
    tags: TagsChange? = nil,
    links: LinksChange? = nil
  ) {
    self.flagged = flagged
    self.urgent = urgent
    self.earlyReminder = earlyReminder
    self.tags = tags
    self.links = links
  }

  private var fields: [(name: String, verb: String)] {
    let early = earlyReminder.map { $0 == .remove ? "removed" : "set" }
    return [("flag", flagged.map(Self.verb)), ("Urgent", urgent.map(Self.verb)), ("Early Reminder", early)]
      .compactMap { name, verb in verb.map { (name, $0) } } + (tags?.fields ?? []) + (links?.fields ?? [])
  }

  private static func verb(_ on: Bool) -> String {
    on ? "set" : "removed"
  }

  func describe(_ state: (String) -> String) -> String {
    fields.map { "\($0.name) \(state($0.verb))" }.joined(separator: " and ")
  }

  func mismatch(
    in reminder: ReminderItem,
    readBack fields: PrivateReminderFields?,
    expectedTags: [String]?,
    expectedLinks: [String]?
  ) -> String? {
    var shown: [String] = []
    if flagged != nil && reminder.flagged != flagged {
      shown.append(reminder.flagged.map { "flagged \($0)" } ?? "no flag value")
    }
    if urgent != nil && reminder.urgent != urgent {
      shown.append(reminder.urgent.map { "urgent \($0)" } ?? "no Urgent value")
    }
    if let earlyReminder {
      let wanted: EarlyReminder? = if case .set(let value) = earlyReminder { value } else { nil }
      if fields == nil {
        shown.append("no Early Reminder value")
      } else if fields?.earlyReminderUnreadable == true {
        shown.append("an unreadable Early Reminder")
      } else if reminder.earlyReminder != wanted {
        shown.append(reminder.earlyReminder.map { "Early Reminder \($0.displayString)" } ?? "no Early Reminder")
      }
    }
    if let expectedTags, !(reminder.tags.map { TagsChange.sameTags($0, expectedTags) } ?? false) {
      shown.append(
        reminder.tags.map { $0.isEmpty ? "no tags" : "tags \($0.joined(separator: ", "))" } ?? "no tags value"
      )
    }
    if let expectedLinks, !(fields?.links.map { LinksChange.sameLinks($0, expectedLinks) } ?? false) {
      shown.append(
        fields?.links.map { $0.isEmpty ? "no links" : "links \($0.joined(separator: ", "))" } ?? "no links value"
      )
    }
    return shown.isEmpty ? nil : shown.joined(separator: ", ")
  }
}

public enum PrivateFieldsWriteResult: Sendable, Equatable {
  case saved
  case failed(reason: String)
  case unknown(reason: String)
}

public protocol PrivateFieldsWriter: Sendable {
  func unavailableReason(for change: PrivateFieldsChange) -> String?
  func write(_ change: PrivateFieldsChange, id: String) -> PrivateFieldsWriteResult
}

public enum PublicSaveOutcome: String, Sendable {
  case created = "reminder created"
  case updated = "reminder updated"
  case unchanged = "reminder not changed"
}

extension PrivateFields {
  public static func save(
    _ change: PrivateFieldsChange,
    writer: any PrivateFieldsWriter,
    reader: any PrivateFieldsReader,
    outcome: PublicSaveOutcome,
    publicSave: () async throws -> ReminderItem
  ) async throws -> ReminderItem {
    if let reason = writer.unavailableReason(for: change) ?? reader.unavailableReason() {
      throw RemindCoreError.operationFailed("\(change.describe { "not \($0)" }): \(reason); nothing was changed")
    }
    let saved = try await publicSave()
    let prefix = "\(outcome.rawValue) (id \(saved.id));"
    var expectedTags: [String]?
    var expectedLinks: [String]?
    if change.tags != nil || change.links != nil {
      let before: PrivateReminderFields?
      switch reader.read(ids: [saved.id], scope: .everything) {
      case .unavailable(let reason):
        throw RemindCoreError.operationFailed("\(prefix) \(change.describe { "not \($0)" }): \(reason)")
      case .fields(let byID):
        before = byID[saved.id]
      }
      func unread(_ what: String) -> RemindCoreError {
        .operationFailed(
          "\(prefix) \(change.describe { "not \($0)" }): the \(what) already on the reminder could not be read"
        )
      }
      if let tags = change.tags {
        guard let stored = before?.tags else { throw unread("tags") }
        expectedTags = tags.applied(to: stored)
      }
      if let links = change.links {
        guard let stored = before?.links else { throw unread("links") }
        expectedLinks = links.applied(to: stored)
      }
    }
    switch writer.write(change, id: saved.id) {
    case .saved:
      break
    case .failed(let reason):
      throw RemindCoreError.operationFailed("\(prefix) \(change.describe { "not \($0)" }): \(reason)")
    case .unknown(let reason):
      throw RemindCoreError.operationFailed("\(prefix) \(change.describe { "may or may not be \($0)" }): \(reason)")
    }
    let written = "\(prefix) \(change.describe { $0 })"
    let fields: PrivateReminderFields?
    switch reader.read(ids: [saved.id], scope: .everything) {
    case .unavailable(let reason):
      throw RemindCoreError.operationFailed("\(written) but not read back: \(reason)")
    case .fields(let byID):
      fields = byID[saved.id]
    }
    let reminder = fields.map(saved.applying) ?? saved
    if let shown = change.mismatch(
      in: reminder,
      readBack: fields,
      expectedTags: expectedTags,
      expectedLinks: expectedLinks
    ) {
      throw RemindCoreError.operationFailed("\(written) but read back as \(shown)")
    }
    return reminder
  }
}
