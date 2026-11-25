public enum ReminderFetchScope: Equatable, Sendable {
  case openOnly
  case everything

  public init(filter: ReminderFilter) {
    switch filter {
    case .today, .tomorrow, .week, .overdue, .upcoming, .open, .date:
      self = .openOnly
    case .completed, .all:
      self = .everything
    }
  }

  public init(searchIncludesCompleted: Bool) {
    self = searchIncludesCompleted ? .everything : .openOnly
  }
}
