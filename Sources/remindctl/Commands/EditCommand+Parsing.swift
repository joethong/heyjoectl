import Commander
import Foundation
import RemindCore

extension EditCommand {
  struct ParsedEdit {
    let title: String?
    let notes: String?
    let url: URL??
    let dates: DateUpdates
    let alarmBefore: RelativeAlarmChange?
    let recurrence: RecurrenceUpdate
    let priority: ReminderPriority?
    let isCompleted: Bool?
    let listTarget: ReminderListTarget?

    init(_ values: ParsedValues) throws {
      title = values.option("title")
      let listName = values.option("list")
      let listID = values.option("listID")
      notes = values.option("notes")
      let alarmValue = values.option("alarm")
      alarmBefore = try values.option("alarmBefore").map(CommandHelpers.parseAlarmBefore)
      let repeatValue = values.option("repeat")

      url = try EditCommand.parsedURLUpdate(urlValue: values.option("url"), clearURL: values.flag("clearUrl"))

      dates = try EditCommand.parsedDateUpdates(
        dueValue: values.option("due"),
        clearDue: values.flag("clearDue"),
        alarmValue: alarmValue,
        clearAlarm: values.flag("clearAlarm"),
        startValue: values.option("start"),
        clearStart: values.flag("clearStart")
      )

      recurrence = try EditCommand.parsedRecurrenceUpdate(
        repeatValue: repeatValue,
        noRepeat: values.flag("noRepeat"),
        until: values.option("repeatUntil"),
        count: values.option("repeatCount")
      )

      if let priorityValue = values.option("priority") {
        priority = try CommandHelpers.parsePriority(priorityValue)
      } else {
        priority = nil
      }

      let completeFlag = values.flag("complete")
      let incompleteFlag = values.flag("incomplete")
      if completeFlag && incompleteFlag {
        throw RemindCoreError.operationFailed("Use either --complete or --incomplete, not both")
      }
      isCompleted = completeFlag ? true : (incompleteFlag ? false : nil)

      listTarget = try CommandHelpers.listTarget(name: listName, id: listID)
    }

    var hasPublicChanges: Bool {
      title != nil || listTarget != nil || notes != nil || url != nil || dates.dueDate != nil
        || dates.startDate != nil || dates.alarmDate != nil || alarmBefore != nil || priority != nil
        || recurrence.rule != nil || recurrence.end != nil || isCompleted != nil
    }

    var update: ReminderUpdate {
      ReminderUpdate(
        title: title,
        notes: notes,
        url: url,
        dueDate: dates.dueDate,
        startDate: dates.startDate,
        alarmDate: dates.alarmDate,
        alarmBefore: alarmBefore,
        recurrenceRule: recurrence.rule,
        recurrenceEnd: recurrence.end,
        priority: priority,
        listTarget: listTarget,
        isCompleted: isCompleted
      )
    }
  }

  static func removesImpliedEarlyReminder(clearDue: Bool, privateChange: PrivateFieldsChange?) -> Bool {
    clearDue && privateChange?.earlyReminder == nil
  }

  static func saveOutcome(hasPublicChanges: Bool, privateChange: PrivateFieldsChange?) throws -> PublicSaveOutcome {
    if hasPublicChanges {
      return .updated
    }
    guard privateChange != nil else {
      throw RemindCoreError.operationFailed("No changes specified")
    }
    return .unchanged
  }

  static func parsedURLUpdate(urlValue: String?, clearURL: Bool) throws -> URL?? {
    if let urlValue {
      if clearURL {
        throw RemindCoreError.operationFailed("Use either --url or --clear-url, not both")
      }
      return try CommandHelpers.parseURL(urlValue)
    }
    return clearURL ? .some(nil) : nil
  }

  struct RecurrenceUpdate {
    let rule: RecurrenceRule??
    let end: RecurrenceEnd?
  }

  static func parsedRecurrenceUpdate(
    repeatValue: String?,
    noRepeat: Bool,
    until: String?,
    count: String?
  ) throws -> RecurrenceUpdate {
    let end = try CommandHelpers.parseRecurrenceEnd(until: until, count: count)
    var rule: RecurrenceRule??
    if let repeatValue {
      let parsed = try CommandHelpers.parseRecurrence(repeatValue)
      rule = end.map(parsed.ending) ?? parsed
    }
    if noRepeat {
      if rule != nil {
        throw RemindCoreError.operationFailed("Use either --repeat or --no-repeat, not both")
      }
      if end != nil {
        throw RemindCoreError.operationFailed("Use either --no-repeat or --repeat-until/--repeat-count, not both")
      }
      rule = .some(nil)
    }
    return RecurrenceUpdate(rule: rule, end: rule == nil ? end : nil)
  }

  struct DateUpdates {
    let dueDate: ParsedUserDate??
    let startDate: ParsedUserDate??
    let alarmDate: ParsedUserDate??
  }

  static func parsedDateUpdates(
    dueValue: String?,
    clearDue: Bool,
    alarmValue: String?,
    clearAlarm: Bool,
    startValue: String? = nil,
    clearStart: Bool = false
  ) throws -> DateUpdates {
    if dueValue != nil && clearDue {
      throw RemindCoreError.operationFailed("Use either --due or --clear-due, not both")
    }
    if startValue != nil && clearStart {
      throw RemindCoreError.operationFailed("Use either --start or --clear-start, not both")
    }
    if alarmValue != nil && clearAlarm {
      throw RemindCoreError.operationFailed("Use either --alarm or --clear-alarm, not both")
    }

    let dueDate: ParsedUserDate?? =
      if let dueValue {
        try CommandHelpers.parseDueDate(dueValue)
      } else if clearDue {
        .some(nil)
      } else {
        nil
      }
    let startDate: ParsedUserDate?? =
      if let startValue {
        try CommandHelpers.parseDueDate(startValue)
      } else if clearStart {
        .some(nil)
      } else {
        nil
      }
    let alarmDate: ParsedUserDate?? =
      if let alarmValue {
        try CommandHelpers.parseDueDate(alarmValue)
      } else if clearAlarm {
        .some(nil)
      } else {
        nil
      }
    return DateUpdates(dueDate: dueDate, startDate: startDate, alarmDate: alarmDate)
  }
}
