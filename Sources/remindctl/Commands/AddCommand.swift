import Commander
import Foundation
import RemindCore

enum AddCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "add",
      abstract: "Add a reminder",
      discussion: """
        Provide a title as an argument or via --title.
        --alarm schedules a notification; it does not enable the native Urgent toggle in Reminders.app.
        --alarm-before sets a notification a set time before the due date (5m, 15m, 1h, 1d, 1w) and needs --due.
        --urgent and --not-urgent set that toggle through ReminderKit, as --flag and --unflag set the flag.
        --early sets the Early Reminder (15m, 1h, 2d, 1w, 1mo) through ReminderKit.
        --tag adds a tag through ReminderKit; repeat it for more than one.
        --link adds a link Reminders.app shows, through ReminderKit; --url stays EventKit's URL.
        """,
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "title", help: "Reminder title", isOptional: true)
          ],
          options: [
            .make(label: "title", names: [.long("title")], help: "Reminder title", parsing: .singleValue),
            .make(label: "list", names: [.short("l"), .long("list")], help: "List name", parsing: .singleValue),
            .make(label: "listID", names: [.long("list-id")], help: "List ID or ID prefix", parsing: .singleValue),
            .make(label: "due", names: [.short("d"), .long("due")], help: "Due date", parsing: .singleValue),
            .make(label: "start", names: [.long("start")], help: "Start date", parsing: .singleValue),
            .make(
              label: "alarm",
              names: [.short("a"), .long("alarm")],
              help: "Notification date",
              parsing: .singleValue
            ),
            .make(
              label: "alarmBefore",
              names: [.long("alarm-before")],
              help: "Notify this long before the due date: a whole number with m, h, d or w (15m, 1h, 1d, 1w)",
              parsing: .singleValue
            ),
            .make(
              label: "early",
              names: [.long("early")],
              help: "Early Reminder before the due date: a whole number with m, h, d, w or mo (15m, 1h, 2d, 1w, 1mo), "
                + "up to a year: \(EarlyReminderUnit.yearLimits), or none (written through ReminderKit)",
              parsing: .singleValue
            ),
            .make(
              label: "tag",
              names: [.long("tag")],
              help: "Add a tag, named without # (repeat for more; written through ReminderKit)",
              parsing: .singleValue
            ),
            .make(
              label: "untag",
              names: [.long("untag")],
              help: "Remove a tag, named without # (repeat for more; written through ReminderKit)",
              parsing: .singleValue
            ),
            .make(
              label: "link",
              names: [.long("link")],
              help: "Add a link Reminders.app shows: an http, https or mailto URL (repeat for more; written through "
                + "ReminderKit)",
              parsing: .singleValue
            ),
            .make(
              label: "unlink",
              names: [.long("unlink")],
              help: "Remove a link Reminders.app shows, by its URL (repeat for more; written through ReminderKit)",
              parsing: .singleValue
            ),
            .make(
              label: "location",
              names: [.long("location")],
              help: "Location address for geofence trigger",
              parsing: .singleValue
            ),
            .make(
              label: "radius",
              names: [.long("radius")],
              help: "Geofence radius in meters (default: 100)",
              parsing: .singleValue
            ),
            .make(label: "notes", names: [.short("n"), .long("notes")], help: "Notes", parsing: .singleValue),
            .make(
              label: "url",
              names: [.long("url")],
              help: "URL (stored in EventKit and shown in Reminders notes)",
              parsing: .singleValue
            ),
            .make(
              label: "repeat",
              names: [.short("r"), .long("repeat")],
              help:
                "daily|weekly|biweekly|monthly|yearly|every N days/weeks/months/years, "
                + "optionally with on <days>: weekly on mon,fri | monthly on 1,15 | monthly on last fri "
                + "(on a yearly rule, last fri is the last Friday of the year)",
              parsing: .singleValue
            ),
            .make(
              label: "repeatUntil",
              names: [.long("repeat-until")],
              help: "Last day of the repeat, with --repeat (a date-only value includes that whole day)",
              parsing: .singleValue
            ),
            .make(
              label: "repeatCount",
              names: [.long("repeat-count")],
              help: "Number of times the repeat happens, with --repeat (a whole number of 1 or more)",
              parsing: .singleValue
            ),
            .make(
              label: "priority",
              names: [.short("p"), .long("priority")],
              help: "none|low|medium|high",
              parsing: .singleValue
            ),
          ],
          flags: [
            .make(label: "leaving", names: [.long("leaving")], help: "Trigger when leaving location"),
            .make(
              label: "clearStart",
              names: [.long("clear-start")],
              help: "Leave the start date empty (EventKit otherwise copies the due date)"
            ),
            .make(label: "flag", names: [.long("flag")], help: "Flag the reminder (written through ReminderKit)"),
            .make(label: "unflag", names: [.long("unflag")], help: "Remove the flag (written through ReminderKit)"),
            .make(label: "urgent", names: [.long("urgent")], help: "Mark Urgent (written through ReminderKit)"),
            .make(
              label: "notUrgent",
              names: [.long("not-urgent")],
              help: "Remove Urgent (written through ReminderKit)"
            ),
          ]
        )
      ),
      usageExamples: [
        "remindctl add \"Buy milk\"",
        "remindctl add --title \"Call mom\" --list Personal --due tomorrow",
        "remindctl add \"Plan trip\" --start 2026-01-01 --due 2026-01-03",
        "remindctl add \"Call mom\" --due \"2026-01-03 09:00\" --alarm \"2026-01-03 08:55\"",
        "remindctl add \"Call mom\" --due \"2026-01-03 09:00\" --alarm-before 15m",
        "remindctl add \"Check mailbox\" --location \"1 Apple Park Way, Cupertino, CA\"",
        "remindctl add \"Take vitamins\" --due tomorrow --repeat daily",
        "remindctl add \"Gym\" --due 2026-01-05 --repeat \"weekly on mon,fri\"",
        "remindctl add \"Pay rent\" --due 2026-12-25 --repeat \"monthly on last fri\"",
        "remindctl add \"Water plants\" --due tomorrow --repeat weekly --repeat-count 6",
        "remindctl add \"Summer course\" --due 2026-06-01 --repeat weekly --repeat-until 2026-08-31",
        "remindctl add \"Review docs\" --priority high",
        "remindctl add \"Pay invoice\" --flag",
        "remindctl add \"Renew passport\" --due \"2026-01-03 09:00\" --urgent",
        "remindctl add \"Renew passport\" --due \"2026-01-03 09:00\" --early 1w",
        "remindctl add \"Buy nails\" --tag errand --tag home",
        "remindctl add \"Buy headphones\" --url \"https://example.com/product\"",
      ]
    ) { values, runtime in
      let reminder = try await run(values, runtime: runtime)
      OutputRenderer.printReminder(reminder, format: runtime.outputFormat)
    }
  }

  static func run(
    _ values: ParsedValues,
    runtime: RuntimeOptions,
    makeStore: () -> any ReminderCommandStore = { RemindersStore() },
    writer: any PrivateFieldsWriter = ReminderKitFieldsWriter(),
    reader: any PrivateFieldsReader = ReminderKitFieldsReader()
  ) async throws -> ReminderItem {
    let titleOption = values.option("title")
    let titleArg = values.argument(0)
    if titleOption != nil && titleArg != nil {
      throw RemindCoreError.operationFailed("Provide title either as argument or via --title")
    }

    var title = titleOption ?? titleArg
    if title == nil {
      if runtime.noInput || !Console.isTTY {
        throw RemindCoreError.operationFailed("Missing title. Provide it as an argument or via --title.")
      }
      title = Console.readLine(prompt: "Title:")?.trimmingCharacters(in: .whitespacesAndNewlines)
      if title?.isEmpty == true { title = nil }
    }

    guard let title else {
      throw RemindCoreError.operationFailed("Missing title.")
    }

    let listName = values.option("list")
    let listID = values.option("listID")
    let notes = values.option("notes")
    let url = try values.option("url").map(CommandHelpers.parseURL)
    let dueValue = values.option("due")
    let alarmValue = values.option("alarm")
    let alarmBeforeValue = values.option("alarmBefore")
    let locationValue = values.option("location")
    let radiusValue = values.option("radius")
    let repeatValue = values.option("repeat")
    let priorityValue = values.option("priority")

    let dueDate = try dueValue.map(CommandHelpers.parseDueDate)
    let startDate = try parsedStartDate(startValue: values.option("start"), clearStart: values.flag("clearStart"))
    let alarmDate = try alarmValue.map(CommandHelpers.parseDueDate)
    let alarmBeforeDueSeconds = try alarmBeforeSeconds(value: alarmBeforeValue, hasDue: dueDate != nil)
    let locationTrigger = try makeLocationTrigger(
      location: locationValue,
      radius: radiusValue,
      leaving: values.flag("leaving")
    )
    let recurrenceRule = try recurrenceRule(
      repeatValue: repeatValue,
      until: values.option("repeatUntil"),
      count: values.option("repeatCount")
    )
    let priority = try priorityValue.map(CommandHelpers.parsePriority) ?? .none
    let privateChange = try CommandHelpers.privateChange(values, runtime: runtime)

    let store = makeStore()
    try await store.requestAccess()

    let targetList: ReminderListTarget?
    if let explicitTarget = try CommandHelpers.listTarget(name: listName, id: listID) {
      targetList = explicitTarget
    } else {
      targetList = await store.defaultList().map { .id($0.id) }
    }
    guard let targetList else {
      throw RemindCoreError.operationFailed("No default list found. Specify --list.")
    }

    let draft = ReminderDraft(
      title: title,
      notes: notes,
      url: url,
      dueDate: dueDate,
      startDate: startDate,
      alarmDate: alarmDate,
      alarmBeforeDueSeconds: alarmBeforeDueSeconds,
      recurrenceRule: recurrenceRule,
      locationTrigger: locationTrigger,
      priority: priority
    )
    let reminder = try await PrivateFieldsSupport.save(
      privateChange,
      outcome: .created,
      writer: writer,
      reader: reader
    ) {
      try await store.createReminder(draft, target: targetList)
    }
    return PrivateFieldsSupport.attachWritten(
      [reminder],
      privateChange: privateChange,
      runtime: runtime,
      reader: reader
    )[0]
  }
}
