import Foundation
import RemindCore

protocol ReminderCommandStore: Sendable {
  func requestAccess() async throws
  func defaultList() async -> ReminderList?
  func reminderItem(withID id: String) async -> ReminderItem?
  func reminders(in listName: String?) async throws -> [ReminderItem]
  func resolveList(_ target: ReminderListTarget) async throws -> ReminderList
  func createReminder(_ draft: ReminderDraft, target: ReminderListTarget) async throws -> ReminderItem
  func updateReminder(id: String, update: ReminderUpdate) async throws -> ReminderItem
  func completeReminders(ids: [String]) async throws -> [ReminderItem]
  func deleteReminders(ids: [String]) async throws -> Int
}

extension RemindersStore: ReminderCommandStore {}
