import EventKit
import Foundation
import Testing

@testable import RemindCore

@MainActor
struct ReminderFetchScopeTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
  }()

  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  private func item(id: String, completed: Bool, dueOffsetDays: Int?) -> ReminderItem {
    let today = calendar.startOfDay(for: now)
    let due = dueOffsetDays.flatMap { calendar.date(byAdding: .day, value: $0, to: today) }
    return ReminderItem(
      id: id,
      title: "Item \(id)",
      notes: nil,
      isCompleted: completed,
      completionDate: completed ? now : nil,
      priority: .none,
      dueDate: due,
      listID: "a",
      listName: "Home"
    )
  }

  private var mixedReminders: [ReminderItem] {
    var items: [ReminderItem] = []
    for (index, offset) in [-3, -1, 0, 1, 2, 5, 40, nil].enumerated() {
      items.append(item(id: "open-\(index)", completed: false, dueOffsetDays: offset))
      items.append(item(id: "done-\(index)", completed: true, dueOffsetDays: offset))
    }
    return items
  }

  private var openOnlyFilters: [ReminderFilter] {
    [.today, .tomorrow, .week, .overdue, .upcoming, .open, .date(calendar.startOfDay(for: now))]
  }

  @Test("Query plan per filter")
  func planPerFilter() {
    let expected: [(ReminderFilter, ReminderFetchScope)] = [
      (.today, .openOnly),
      (.tomorrow, .openOnly),
      (.week, .openOnly),
      (.overdue, .openOnly),
      (.upcoming, .openOnly),
      (.open, .openOnly),
      (.date(now), .openOnly),
      (.completed, .everything),
      (.all, .everything),
    ]
    for (filter, scope) in expected {
      #expect(ReminderFetchScope(filter: filter) == scope)
    }
  }

  @Test("Query plan for search")
  func planForSearch() {
    #expect(ReminderFetchScope(searchIncludesCompleted: false) == .openOnly)
    #expect(ReminderFetchScope(searchIncludesCompleted: true) == .everything)
  }

  @Test("Open-only filters give the same result on open reminders alone")
  func openOnlyFiltersIgnoreCompleted() {
    let all = mixedReminders
    let open = all.filter { !$0.isCompleted }
    #expect(open.count < all.count)
    for filter in openOnlyFilters {
      #expect(ReminderFetchScope(filter: filter) == .openOnly)
      let fromAll = ReminderFiltering.apply(all, filter: filter, now: now, calendar: calendar)
      let fromOpen = ReminderFiltering.apply(open, filter: filter, now: now, calendar: calendar)
      #expect(fromAll == fromOpen, "filter \(filter)")
    }
  }

  @Test("Filters that need done reminders fetch everything")
  func everythingFiltersNeedCompleted() {
    let all = mixedReminders
    let open = all.filter { !$0.isCompleted }
    for filter in [ReminderFilter.completed, .all] {
      #expect(ReminderFetchScope(filter: filter) == .everything)
      let fromAll = ReminderFiltering.apply(all, filter: filter, now: now, calendar: calendar)
      let fromOpen = ReminderFiltering.apply(open, filter: filter, now: now, calendar: calendar)
      #expect(fromAll != fromOpen)
    }
  }

  @Test("Store builds the incomplete-reminders predicate for openOnly and the all-reminders predicate otherwise")
  func storePredicatePerScope() {
    let store = EKEventStore()
    let incomplete = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
    let everything = store.predicateForReminders(in: nil)
    #expect(type(of: incomplete) != type(of: everything))

    let openOnly = RemindersStore.predicate(for: .openOnly, in: store, calendars: [])
    let all = RemindersStore.predicate(for: .everything, in: store, calendars: [])
    #expect(type(of: openOnly) == type(of: incomplete))
    #expect(type(of: all) == type(of: everything))
  }
}
