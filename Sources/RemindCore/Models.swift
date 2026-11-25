import Foundation

public enum ReminderPriority: String, Codable, CaseIterable, Sendable {
  case none
  case low
  case medium
  case high

  public init(eventKitValue: Int) {
    switch eventKitValue {
    case 1...4:
      self = .high
    case 5:
      self = .medium
    case 6...9:
      self = .low
    default:
      self = .none
    }
  }

  public var eventKitValue: Int {
    switch self {
    case .none:
      return 0
    case .high:
      return 1
    case .medium:
      return 5
    case .low:
      return 9
    }
  }
}

public enum RecurrenceFrequency: String, Codable, CaseIterable, Sendable {
  case daily
  case weekly
  case monthly
  case yearly
}

public struct RecurrenceRule: Codable, Sendable, Equatable {
  public let frequency: RecurrenceFrequency
  public let interval: Int
  public let daysOfWeek: [RecurrenceDay]
  public let daysOfMonth: [Int]
  public let monthsOfYear: [Int]
  public let setPositions: [Int]
  public let end: RecurrenceEnd?

  public init(
    frequency: RecurrenceFrequency,
    interval: Int = 1,
    daysOfWeek: [RecurrenceDay] = [],
    daysOfMonth: [Int] = [],
    monthsOfYear: [Int] = [],
    setPositions: [Int] = [],
    end: RecurrenceEnd? = nil
  ) {
    self.frequency = frequency
    self.interval = interval
    self.daysOfWeek = daysOfWeek
    self.daysOfMonth = daysOfMonth
    self.monthsOfYear = monthsOfYear
    self.setPositions = setPositions
    self.end = end
  }

  private enum CodingKeys: String, CodingKey {
    case frequency, interval, daysOfWeek, daysOfMonth, monthsOfYear, setPositions, end
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    frequency = try container.decode(RecurrenceFrequency.self, forKey: .frequency)
    interval = try container.decode(Int.self, forKey: .interval)
    daysOfWeek = try container.decodeIfPresent([RecurrenceDay].self, forKey: .daysOfWeek) ?? []
    daysOfMonth = try container.decodeIfPresent([Int].self, forKey: .daysOfMonth) ?? []
    monthsOfYear = try container.decodeIfPresent([Int].self, forKey: .monthsOfYear) ?? []
    setPositions = try container.decodeIfPresent([Int].self, forKey: .setPositions) ?? []
    end = try container.decodeIfPresent(RecurrenceEnd.self, forKey: .end)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(frequency, forKey: .frequency)
    try container.encode(interval, forKey: .interval)
    if !daysOfWeek.isEmpty { try container.encode(daysOfWeek, forKey: .daysOfWeek) }
    if !daysOfMonth.isEmpty { try container.encode(daysOfMonth, forKey: .daysOfMonth) }
    if !monthsOfYear.isEmpty { try container.encode(monthsOfYear, forKey: .monthsOfYear) }
    if !setPositions.isEmpty { try container.encode(setPositions, forKey: .setPositions) }
    try container.encodeIfPresent(end, forKey: .end)
  }

  public var displayString: String {
    let words = [
      RecurrenceWords.interval(frequency: frequency, interval: interval),
      RecurrenceWords.daysOfWeek(daysOfWeek),
      RecurrenceWords.daysOfMonth(daysOfMonth),
      RecurrenceWords.monthsOfYear(monthsOfYear),
      RecurrenceWords.setPositions(setPositions),
    ].compactMap { $0 }
    return words.joined(separator: " ") + RecurrenceWords.end(end)
  }
}

public struct ReminderList: Identifiable, Codable, Sendable, Equatable {
  public let id: String
  public let title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

public enum ReminderListTarget: Sendable, Equatable {
  case name(String)
  case id(String)
}

public enum LocationProximity: String, Codable, CaseIterable, Sendable {
  case arriving
  case leaving
}

public struct LocationTrigger: Codable, Sendable, Equatable {
  public let address: String
  public let latitude: Double?
  public let longitude: Double?
  public let radius: Double
  public let proximity: LocationProximity

  public init(
    address: String,
    latitude: Double? = nil,
    longitude: Double? = nil,
    radius: Double = 100,
    proximity: LocationProximity = .arriving
  ) {
    self.address = address
    self.latitude = latitude
    self.longitude = longitude
    self.radius = radius
    self.proximity = proximity
  }
}

public struct ReminderAssignee: Codable, Sendable, Equatable {
  public let id: String
  public let name: String?
  public let status: Int

  public init(id: String, name: String? = nil, status: Int) {
    self.id = id
    self.name = name
    self.status = status
  }
}

public struct PlaceAlarm: Sendable, Equatable {
  public let title: String
  public let latitude: Double?
  public let longitude: Double?
  public let radius: Double
  public let proximity: LocationProximity?

  public init(
    title: String,
    latitude: Double? = nil,
    longitude: Double? = nil,
    radius: Double = 100,
    proximity: LocationProximity?
  ) {
    self.title = title
    self.latitude = latitude
    self.longitude = longitude
    self.radius = radius
    self.proximity = proximity
  }

  public init(_ trigger: LocationTrigger) {
    self.init(
      title: trigger.address,
      latitude: trigger.latitude,
      longitude: trigger.longitude,
      radius: trigger.radius,
      proximity: trigger.proximity
    )
  }
}

public enum ReminderAlarm: Codable, Sendable, Equatable {
  case date(Date)
  case beforeDue(seconds: Int)
  case afterDue(seconds: Int)
  case place(PlaceAlarm)

  private enum Kind: String, Codable {
    case date, beforeDue, afterDue, place
  }

  private enum CodingKeys: String, CodingKey {
    case kind, date, seconds, title, latitude, longitude, radius, proximity
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(Kind.self, forKey: .kind) {
    case .date:
      self = .date(try container.decode(Date.self, forKey: .date))
    case .beforeDue:
      self = .beforeDue(seconds: try container.decode(Int.self, forKey: .seconds))
    case .afterDue:
      self = .afterDue(seconds: try container.decode(Int.self, forKey: .seconds))
    case .place:
      self = .place(
        PlaceAlarm(
          title: try container.decode(String.self, forKey: .title),
          latitude: try container.decodeIfPresent(Double.self, forKey: .latitude),
          longitude: try container.decodeIfPresent(Double.self, forKey: .longitude),
          radius: try container.decode(Double.self, forKey: .radius),
          proximity: try container.decodeIfPresent(LocationProximity.self, forKey: .proximity)
        ))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .date(let date):
      try container.encode(Kind.date, forKey: .kind)
      try container.encode(date, forKey: .date)
    case .beforeDue(let seconds):
      try container.encode(Kind.beforeDue, forKey: .kind)
      try container.encode(seconds, forKey: .seconds)
    case .afterDue(let seconds):
      try container.encode(Kind.afterDue, forKey: .kind)
      try container.encode(seconds, forKey: .seconds)
    case .place(let place):
      try container.encode(Kind.place, forKey: .kind)
      try container.encode(place.title, forKey: .title)
      try container.encodeIfPresent(place.latitude, forKey: .latitude)
      try container.encodeIfPresent(place.longitude, forKey: .longitude)
      try container.encode(place.radius, forKey: .radius)
      try container.encodeIfPresent(place.proximity, forKey: .proximity)
    }
  }
}

public enum RelativeAlarmChange: Sendable, Equatable {
  case set(beforeDueSeconds: Int)
  case remove
}

public struct ReminderItem: Identifiable, Codable, Sendable, Equatable {
  public let id: String
  public let title: String
  public let notes: String?
  public let url: URL?
  public let isCompleted: Bool
  public let completionDate: Date?
  public let creationDate: Date?
  public let lastModifiedDate: Date?
  public let priority: ReminderPriority
  public let dueDate: Date?
  public let dueDateIsAllDay: Bool
  public let startDate: Date?
  public let startDateIsAllDay: Bool?
  public let timeZone: String?
  public let externalID: String?
  public let alarmDate: Date?
  public let recurrenceRule: RecurrenceRule?
  public let locationTrigger: LocationTrigger?
  public let alarms: [ReminderAlarm]?
  public let listID: String
  public let listName: String
  public var flagged: Bool?
  public var urgent: Bool?
  public var earlyReminder: EarlyReminder?
  public var tags: [String]?
  public var parentID: String?
  public var assignee: ReminderAssignee?
  public var links: [String]?

  public init(
    id: String,
    title: String,
    notes: String?,
    url: URL? = nil,
    isCompleted: Bool,
    completionDate: Date?,
    creationDate: Date? = nil,
    lastModifiedDate: Date? = nil,
    priority: ReminderPriority,
    dueDate: Date?,
    dueDateIsAllDay: Bool = false,
    startDate: Date? = nil,
    startDateIsAllDay: Bool? = nil,
    timeZone: String? = nil,
    externalID: String? = nil,
    alarmDate: Date? = nil,
    recurrenceRule: RecurrenceRule? = nil,
    locationTrigger: LocationTrigger? = nil,
    alarms: [ReminderAlarm]? = nil,
    listID: String,
    listName: String,
    flagged: Bool? = nil,
    urgent: Bool? = nil,
    earlyReminder: EarlyReminder? = nil,
    tags: [String]? = nil,
    parentID: String? = nil,
    assignee: ReminderAssignee? = nil,
    links: [String]? = nil
  ) {
    self.id = id
    self.title = title
    self.notes = notes
    self.url = url
    self.isCompleted = isCompleted
    self.completionDate = completionDate
    self.creationDate = creationDate
    self.lastModifiedDate = lastModifiedDate
    self.priority = priority
    self.dueDate = dueDate
    self.dueDateIsAllDay = dueDateIsAllDay
    self.startDate = startDate
    self.startDateIsAllDay = startDateIsAllDay
    self.timeZone = timeZone
    self.externalID = externalID
    self.alarmDate = alarmDate
    self.recurrenceRule = recurrenceRule
    self.locationTrigger = locationTrigger
    self.alarms = alarms
    self.listID = listID
    self.listName = listName
    self.flagged = flagged
    self.urgent = urgent
    self.earlyReminder = earlyReminder
    self.tags = tags
    self.parentID = parentID
    self.assignee = assignee
    self.links = links
  }
}

public struct ReminderDraft: Sendable {
  public let title: String
  public let notes: String?
  public let url: URL?
  public let dueDate: ParsedUserDate?
  // Double optional: nil = leave EventKit's default, .some(nil) = leave the start date empty, .some(date) = set.
  public let startDate: ParsedUserDate??
  public let alarmDate: ParsedUserDate?
  public let alarmBeforeDueSeconds: Int?
  public let recurrenceRule: RecurrenceRule?
  public let locationTrigger: LocationTrigger?
  public let priority: ReminderPriority

  public init(
    title: String,
    notes: String?,
    url: URL? = nil,
    dueDate: ParsedUserDate?,
    startDate: ParsedUserDate?? = nil,
    alarmDate: ParsedUserDate? = nil,
    alarmBeforeDueSeconds: Int? = nil,
    recurrenceRule: RecurrenceRule? = nil,
    locationTrigger: LocationTrigger? = nil,
    priority: ReminderPriority
  ) {
    self.title = title
    self.notes = notes
    self.url = url
    self.dueDate = dueDate
    self.startDate = startDate
    self.alarmDate = alarmDate
    self.alarmBeforeDueSeconds = alarmBeforeDueSeconds
    self.recurrenceRule = recurrenceRule
    self.locationTrigger = locationTrigger
    self.priority = priority
  }
}

public struct ReminderUpdate: Sendable {
  public let title: String?
  public let notes: String?
  // Double optional: nil = leave unchanged, .some(nil) = clear, .some(url) = set.
  public let url: URL??
  public let dueDate: ParsedUserDate??
  public let startDate: ParsedUserDate??
  public let alarmDate: ParsedUserDate??
  public let alarmBefore: RelativeAlarmChange?
  public let recurrenceRule: RecurrenceRule??
  // Sets the end on the reminder's repeat rule (the new one if recurrenceRule is also set); throws if it has none.
  public let recurrenceEnd: RecurrenceEnd?
  public let priority: ReminderPriority?
  public let listName: String?
  public let listTarget: ReminderListTarget?
  public let isCompleted: Bool?

  public init(
    title: String? = nil,
    notes: String? = nil,
    url: URL?? = nil,
    dueDate: ParsedUserDate?? = nil,
    startDate: ParsedUserDate?? = nil,
    alarmDate: ParsedUserDate?? = nil,
    alarmBefore: RelativeAlarmChange? = nil,
    recurrenceRule: RecurrenceRule?? = nil,
    recurrenceEnd: RecurrenceEnd? = nil,
    priority: ReminderPriority? = nil,
    listName: String? = nil,
    listTarget: ReminderListTarget? = nil,
    isCompleted: Bool? = nil
  ) {
    self.title = title
    self.notes = notes
    self.url = url
    self.dueDate = dueDate
    self.startDate = startDate
    self.alarmDate = alarmDate
    self.alarmBefore = alarmBefore
    self.recurrenceRule = recurrenceRule
    self.recurrenceEnd = recurrenceEnd
    self.priority = priority
    self.listName = listName
    self.listTarget = listTarget
    self.isCompleted = isCompleted
  }
}
