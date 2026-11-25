import Foundation
import RemindCore

struct TagFilter: Equatable {
  let names: [String]

  static func parse(_ values: [String], runtime: RuntimeOptions) throws -> TagFilter? {
    let names = try CommandHelpers.tagNames(values, option: "--tag")
    guard !names.isEmpty else { return nil }
    if runtime.noPrivate {
      throw RemindCoreError.operationFailed("--tag filters on tags read through ReminderKit; remove --no-private")
    }
    return TagFilter(names: names)
  }

  func matches(_ reminder: ReminderItem) -> Bool {
    let tags = reminder.tags ?? []
    return names.allSatisfy { name in tags.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
  }
}

extension PrivateFieldsSupport {
  static func attach(
    to reminders: [ReminderItem],
    scope: ReminderFetchScope,
    runtime: RuntimeOptions,
    tagFilter: TagFilter?,
    reader: any PrivateFieldsReader = ReminderKitFieldsReader(),
    warn: (String) -> Void = Console.printError
  ) throws -> [ReminderItem] {
    guard let tagFilter else {
      return attach(to: reminders, scope: scope, runtime: runtime, reader: reader, warn: warn)
    }
    let attachment = PrivateFields.attach(to: reminders, scope: scope, reader: reader)
    if let reason = attachment.unavailableReason {
      throw RemindCoreError.operationFailed(
        "--tag filters on tags read through ReminderKit, which is unavailable: \(shortReason(reason)); "
          + "run `remindctl doctor` for details")
    }
    warnUnreadableEarlyReminders(attachment, warn: warn)
    return attachment.reminders.filter(tagFilter.matches)
  }
}
