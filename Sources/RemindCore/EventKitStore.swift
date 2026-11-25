import EventKit
import Foundation

public actor RemindersStore {
  static let externalOperationTimeout: Duration = .seconds(30)

  private let eventStore = EKEventStore()
  private let calendar: Calendar

  public init(calendar: Calendar = .current) {
    self.calendar = calendar
  }

  public func requestAccess() async throws {
    let status = Self.authorizationStatus()
    switch status {
    case .notDetermined:
      let updated = try await requestAuthorization()
      if updated != .fullAccess {
        throw RemindCoreError.accessDenied
      }
    case .denied, .restricted:
      throw RemindCoreError.accessDenied
    case .writeOnly:
      throw RemindCoreError.writeOnlyAccess
    case .fullAccess:
      break
    }
  }

  public static func authorizationStatus() -> RemindersAuthorizationStatus {
    RemindersAuthorizationStatus(eventKitStatus: EKEventStore.authorizationStatus(for: .reminder))
  }

  public func requestAuthorization() async throws -> RemindersAuthorizationStatus {
    let status = Self.authorizationStatus()
    switch status {
    case .notDetermined:
      let granted = try await requestFullAccess()
      return granted ? .fullAccess : .denied
    default:
      return status
    }
  }

  public func lists() async -> [ReminderList] {
    eventStore.calendars(for: .reminder).map { calendar in
      ReminderList(id: calendar.calendarIdentifier, title: calendar.title)
    }
  }

  public func resolveList(_ target: ReminderListTarget) async throws -> ReminderList {
    try resolvedList(matching: target, in: await lists())
  }

  public func defaultListName() -> String? { defaultList()?.title }

  public func defaultList() -> ReminderList? {
    guard let calendar = eventStore.defaultCalendarForNewReminders() else {
      return nil
    }
    return ReminderList(id: calendar.calendarIdentifier, title: calendar.title)
  }

  public func reminders(in listName: String? = nil) async throws -> [ReminderItem] {
    try await reminders(matching: listName.map(ReminderListTarget.name))
  }

  public func reminders(
    matching target: ReminderListTarget?,
    scope: ReminderFetchScope = .everything
  ) async throws -> [ReminderItem] {
    try await fetchReminders(in: try calendars(matching: target), scope: scope)
  }

  public func reminderItem(withID id: String) -> ReminderItem? {
    (eventStore.calendarItem(withIdentifier: id) as? EKReminder)
      .flatMap(Self.reminderData(from:))?
      .item(calendar: calendar)
  }

  public func createList(name: String) async throws -> ReminderList {
    let list = EKCalendar(for: .reminder, eventStore: eventStore)
    list.title = name
    guard let source = eventStore.defaultCalendarForNewReminders()?.source else {
      throw RemindCoreError.operationFailed("Unable to determine default reminder source")
    }
    list.source = source
    try eventStore.saveCalendar(list, commit: true)
    return ReminderList(id: list.calendarIdentifier, title: list.title)
  }

  public func renameList(oldName: String, newName: String) async throws {
    try await renameList(target: .name(oldName), newName: newName)
  }

  public func renameList(target: ReminderListTarget, newName: String) async throws {
    let calendar = try calendar(matching: target)
    guard calendar.allowsContentModifications else {
      throw RemindCoreError.operationFailed("Cannot modify system list")
    }
    calendar.title = newName
    try eventStore.saveCalendar(calendar, commit: true)
  }

  public func deleteList(name: String) async throws {
    try await deleteList(target: .name(name))
  }

  public func deleteList(target: ReminderListTarget) async throws {
    let calendar = try calendar(matching: target)
    guard calendar.allowsContentModifications else {
      throw RemindCoreError.operationFailed("Cannot delete system list")
    }
    try eventStore.removeCalendar(calendar, commit: true)
  }

  public func createReminder(_ draft: ReminderDraft, target: ReminderListTarget) async throws -> ReminderItem {
    let calendar = try calendar(matching: target)
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = draft.title
    reminder.url = draft.url
    // Reminders.app does not surface EventKit's URL field, so also keep one managed notes link.
    reminder.notes = ReminderURLNoteMirror.apply(notes: draft.notes, showing: draft.url)
    reminder.calendar = calendar
    reminder.priority = draft.priority.eventKitValue
    if let dueDate = draft.dueDate {
      reminder.dueDateComponents = calendarComponents(from: dueDate)
    }
    Self.applyStartDate(draft.startDate, to: reminder, calendar: self.calendar)
    if let alarmDate = draft.alarmDate {
      reminder.addAlarm(EKAlarm(absoluteDate: alarmDate.date))
    } else if let dueDate = draft.dueDate, !dueDate.isDateOnly {
      reminder.addAlarm(EKAlarm(absoluteDate: dueDate.date))
    }
    if let seconds = draft.alarmBeforeDueSeconds {
      try ReminderAlarmMutation.replaceRelativeAlarms(on: reminder, with: .set(beforeDueSeconds: seconds))
    }
    if let recurrenceRule = draft.recurrenceRule {
      Self.replaceRecurrence(on: reminder, with: recurrenceRule)
    }
    if let locationTrigger = draft.locationTrigger {
      reminder.addAlarm(try await locationAlarm(from: locationTrigger))
    }
    try eventStore.save(reminder, commit: true)
    return try item(from: reminder)
  }

  public func updateReminder(id: String, update: ReminderUpdate) async throws -> ReminderItem {
    let reminder = try reminder(withID: id)
    let originalCalendarID = reminder.calendar?.calendarIdentifier

    if let title = update.title {
      reminder.title = title
    }
    if update.notes != nil || update.url != nil {
      let merged = ReminderURLNoteMirror.applyingUpdates(
        currentNotes: reminder.notes,
        currentURL: reminder.url,
        notesUpdate: update.notes,
        urlUpdate: update.url
      )
      (reminder.notes, reminder.url) = (merged.notes, merged.url)
    }
    try Self.applyDateChanges(update, to: reminder, calendar: calendar)
    if let recurrenceUpdate = update.recurrenceRule {
      Self.replaceRecurrence(on: reminder, with: recurrenceUpdate)
    }
    if let recurrenceEnd = update.recurrenceEnd {
      try Self.replaceRecurrenceEnd(on: reminder, with: recurrenceEnd)
    }
    if let priority = update.priority {
      reminder.priority = priority.eventKitValue
    }
    if let listTarget = update.listTarget {
      reminder.calendar = try calendar(matching: listTarget)
    } else if let listName = update.listName {
      reminder.calendar = try calendar(matching: .name(listName))
    }
    if let isCompleted = update.isCompleted {
      reminder.isCompleted = isCompleted
    }

    try ReminderUpdateSave.save(isMoving: reminder.calendar?.calendarIdentifier != originalCalendarID) {
      try eventStore.save(reminder, commit: true)
    }

    return try item(from: reminder)
  }

  public func completeReminders(ids: [String]) async throws -> [ReminderItem] {
    var updated: [ReminderItem] = []
    for id in ids {
      let reminder = try reminder(withID: id)
      reminder.isCompleted = true
      try eventStore.save(reminder, commit: true)
      updated.append(try item(from: reminder))
    }
    return updated
  }

  public func deleteReminders(ids: [String]) async throws -> Int {
    var deleted = 0
    for id in ids {
      let reminder = try reminder(withID: id)
      try eventStore.remove(reminder, commit: true)
      deleted += 1
    }
    return deleted
  }
}

extension RemindersStore {
  private func requestFullAccess() async throws -> Bool {
    try await withCheckedThrowingContinuation { continuation in
      eventStore.requestFullAccessToReminders { granted, error in
        if let error {
          continuation.resume(throwing: error)
          return
        }
        continuation.resume(returning: granted)
      }
    }
  }

  static func predicate(
    for scope: ReminderFetchScope,
    in eventStore: EKEventStore,
    calendars: [EKCalendar]
  ) -> NSPredicate {
    switch scope {
    case .openOnly:
      return eventStore.predicateForIncompleteReminders(
        withDueDateStarting: nil,
        ending: nil,
        calendars: calendars
      )
    case .everything:
      return eventStore.predicateForReminders(in: calendars)
    }
  }

  private func fetchReminders(in calendars: [EKCalendar], scope: ReminderFetchScope) async throws -> [ReminderItem] {
    let context = EventKitFetchContext(eventStore: eventStore, calendars: calendars)
    let reminderData: [ReminderData] = try await AsyncTimeout.withTimeout(
      after: Self.externalOperationTimeout,
      timeoutError: .operationFailed("Timed out waiting for EventKit reminders after 30 seconds")
    ) { completion in
      let predicate = Self.predicate(for: scope, in: context.eventStore, calendars: context.calendars)
      let identifier = context.eventStore.fetchReminders(matching: predicate) { reminders in
        guard let claim = completion.claim() else { return }
        claim.resume(returning: (reminders ?? []).compactMap(Self.reminderData(from:)))
      }
      let request = EventKitFetchCancellation(eventStore: context.eventStore, identifier: identifier)
      return { request.cancel() }
    }

    return reminderData.map { $0.item(calendar: calendar) }
  }

  private func reminder(withID id: String) throws -> EKReminder {
    guard let item = eventStore.calendarItem(withIdentifier: id) as? EKReminder else {
      throw RemindCoreError.reminderNotFound(id)
    }
    return item
  }

  private func calendar(matching target: ReminderListTarget) throws -> EKCalendar {
    let resolved = try resolvedList(matching: target)
    let calendars = eventStore.calendars(for: .reminder)
    guard let calendar = calendars.first(where: { $0.calendarIdentifier == resolved.id }) else {
      throw RemindCoreError.listNotFound(resolved.id)
    }
    return calendar
  }

  private func calendars(matching target: ReminderListTarget?) throws -> [EKCalendar] {
    let calendars = eventStore.calendars(for: .reminder)
    guard let target else {
      return calendars
    }

    let lists = calendars.map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
    switch target {
    case .name(let name):
      let resolved = try ListResolver.resolveForRead(name, in: lists)
      let ids = Set(resolved.map(\.id))
      return calendars.filter { ids.contains($0.calendarIdentifier) }
    case .id:
      let resolved = try resolvedList(matching: target, in: lists)
      return calendars.filter { $0.calendarIdentifier == resolved.id }
    }
  }

  private func resolvedList(matching target: ReminderListTarget) throws -> ReminderList {
    let lists = eventStore.calendars(for: .reminder).map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
    return try resolvedList(matching: target, in: lists)
  }

  private func resolvedList(matching target: ReminderListTarget, in lists: [ReminderList]) throws -> ReminderList {
    switch target {
    case .name(let name):
      return try ListResolver.resolve(name, in: lists)
    case .id(let id):
      return try ListResolver.resolveID(id, in: lists)
    }
  }

  static func applyDateChanges(_ update: ReminderUpdate, to reminder: EKReminder, calendar: Calendar) throws {
    try applyDueDate(update.dueDate, startUpdate: update.startDate, to: reminder, calendar: calendar)
    applyStartDate(update.startDate, to: reminder, calendar: calendar)
    if let alarmDateUpdate = update.alarmDate {
      ReminderAlarmMutation.replaceDateAlarms(on: reminder, with: alarmDateUpdate?.date)
    }
    if let alarmBefore = update.alarmBefore {
      try ReminderAlarmMutation.replaceRelativeAlarms(on: reminder, with: alarmBefore)
    }
  }

  static func applyDueDate(
    _ update: ParsedUserDate??,
    startUpdate: ParsedUserDate??,
    to reminder: EKReminder,
    calendar: Calendar
  ) throws {
    guard let update else { return }
    let oldStart = reminder.startDateComponents
    let startIsCopy = startUpdate == nil && isCopy(oldStart, of: reminder.dueDateComponents)
    let newDue = update.map { calendarComponents(from: $0, calendar: calendar) }
    if startUpdate == nil, !startIsCopy, let oldStart, let newDue, isAfter(oldStart, newDue, calendar: calendar) {
      throw RemindCoreError.operationFailed(
        "The start date would be after the new due date; give an earlier --start, or --clear-start"
      )
    }
    if let oldDueAt = timedInstant(reminder.dueDateComponents, calendar: calendar) {
      ReminderAlarmMutation.moveDueAlarms(
        on: reminder,
        from: oldDueAt,
        to: timedInstant(newDue, calendar: calendar)
      )
    }
    reminder.dueDateComponents = nil
    if let newDue {
      reminder.dueDateComponents = newDue
    } else {
      try ReminderAlarmMutation.replaceRelativeAlarms(on: reminder, with: .remove)
    }
    // Changing the due date makes EventKit rewrite an existing start date, so write the wanted one back.
    if let oldStart {
      reminder.startDateComponents = nil
      reminder.startDateComponents = startIsCopy ? newDue : oldStart
    }
  }

  private static func timedInstant(_ components: DateComponents?, calendar: Calendar) -> Date? {
    guard let components, !isAllDay(components) else { return nil }
    return calendar.date(from: components)
  }

  private static func isCopy(_ start: DateComponents?, of due: DateComponents?) -> Bool {
    guard let start, let due else { return false }
    let day: [Calendar.Component] = [.year, .month, .day]
    let time: [Calendar.Component] = [.hour, .minute, .second]
    guard day.allSatisfy({ start.value(for: $0) == due.value(for: $0) }) else { return false }
    if due.hour == nil {
      return time.allSatisfy { (start.value(for: $0) ?? 0) == 0 }
    }
    return time.allSatisfy { start.value(for: $0) == due.value(for: $0) } && start.timeZone == due.timeZone
  }

  private static func isAfter(_ start: DateComponents, _ due: DateComponents, calendar: Calendar) -> Bool {
    if start.hour == nil || due.hour == nil {
      let day = { (date: DateComponents) in [date.year ?? 0, date.month ?? 0, date.day ?? 0] }
      return day(due).lexicographicallyPrecedes(day(start))
    }
    guard let startDate = calendar.date(from: start), let dueDate = calendar.date(from: due) else { return false }
    return startDate > dueDate
  }

  static func applyStartDate(_ update: ParsedUserDate??, to reminder: EKReminder, calendar: Calendar) {
    guard let update else { return }
    reminder.startDateComponents = nil
    if let startDate = update {
      reminder.startDateComponents = calendarComponents(from: startDate, calendar: calendar)
    }
  }

  private func calendarComponents(from parsed: ParsedUserDate) -> DateComponents {
    Self.calendarComponents(from: parsed, calendar: calendar)
  }

  private static func calendarComponents(from parsed: ParsedUserDate, calendar: Calendar) -> DateComponents {
    let components: Set<Calendar.Component> =
      parsed.isDateOnly
      ? [.year, .month, .day]
      : [.year, .month, .day, .hour, .minute, .second]
    var result = calendar.dateComponents(components, from: parsed.date)
    result.calendar = calendar
    result.timeZone = calendar.timeZone
    return result
  }

  private func item(from reminder: EKReminder) throws -> ReminderItem {
    try Self.reminderItem(from: reminder, calendar: calendar)
  }

  static func replaceRecurrence(on reminder: EKReminder, with rule: RecurrenceRule?) {
    for existing in reminder.recurrenceRules ?? [] {
      reminder.removeRecurrenceRule(existing)
    }
    guard let rule else { return }
    reminder.addRecurrenceRule(rule.eventKitRule)
  }

  static func replaceRecurrenceEnd(on reminder: EKReminder, with end: RecurrenceEnd) throws {
    let existingRules = reminder.recurrenceRules ?? []
    guard !existingRules.isEmpty else {
      throw RemindCoreError.operationFailed("Reminder has no repeat to end")
    }
    // EventKit ignores a changed end on a rule a saved reminder already holds, so build a new rule.
    let rebuilt = try existingRules.map { existing in
      let rule = EKRecurrenceRule(
        recurrenceWith: existing.frequency,
        interval: existing.interval,
        daysOfTheWeek: existing.daysOfTheWeek,
        daysOfTheMonth: existing.daysOfTheMonth,
        monthsOfTheYear: existing.monthsOfTheYear,
        weeksOfTheYear: existing.weeksOfTheYear,
        daysOfTheYear: existing.daysOfTheYear,
        setPositions: existing.setPositions,
        end: end.eventKitEnd
      )
      if rule.firstDayOfTheWeek != existing.firstDayOfTheWeek {
        guard rule.responds(to: NSSelectorFromString("setFirstDayOfTheWeek:")) else {
          throw RemindCoreError.operationFailed(
            "This repeat starts its weeks on another day, which can't be kept when only the end changes; "
              + "give --repeat again with the end"
          )
        }
        rule.setValue(existing.firstDayOfTheWeek, forKey: "firstDayOfTheWeek")
      }
      return rule
    }
    for existing in existingRules {
      reminder.removeRecurrenceRule(existing)
    }
    for rule in rebuilt {
      reminder.addRecurrenceRule(rule)
    }
  }
}

extension RecurrenceFrequency {
  init?(eventKitFrequency: EKRecurrenceFrequency) {
    switch eventKitFrequency {
    case .daily:
      self = .daily
    case .weekly:
      self = .weekly
    case .monthly:
      self = .monthly
    case .yearly:
      self = .yearly
    @unknown default:
      return nil
    }
  }

  var eventKitFrequency: EKRecurrenceFrequency {
    switch self {
    case .daily:
      return .daily
    case .weekly:
      return .weekly
    case .monthly:
      return .monthly
    case .yearly:
      return .yearly
    }
  }
}
