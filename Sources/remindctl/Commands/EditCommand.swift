import Commander
import Foundation
import RemindCore

enum EditCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "edit",
      abstract: "Edit a reminder",
      discussion: """
        Use an index or ID prefix from the show output.
        --alarm schedules a notification; it does not enable the native Urgent toggle in Reminders.app.
        --alarm-before sets a notification a set time before the due date (5m, 15m, 1h, 1d, 1w). It replaces only
        the before-due alarms, and needs a due date (the reminder's or a new --due). --alarm-before none removes them.
        --urgent and --not-urgent set that toggle through ReminderKit, as --flag and --unflag set the flag.
        --early sets the Early Reminder (15m, 1h, 2d, 1w, 1mo) through ReminderKit; --early none removes it.
        --tag and --untag add and remove tags through ReminderKit; repeat them for more than one.
        --link and --unlink add and remove links Reminders.app shows, through ReminderKit; --url stays EventKit's URL.
        """,
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "id", help: "Index or ID prefix", isOptional: false)
          ],
          options: [
            .make(label: "title", names: [.short("t"), .long("title")], help: "New title", parsing: .singleValue),
            .make(label: "list", names: [.short("l"), .long("list")], help: "Move to list", parsing: .singleValue),
            .make(
              label: "listID",
              names: [.long("list-id")],
              help: "Move to list by ID or ID prefix",
              parsing: .singleValue
            ),
            .make(label: "due", names: [.short("d"), .long("due")], help: "Set due date", parsing: .singleValue),
            .make(label: "start", names: [.long("start")], help: "Set start date", parsing: .singleValue),
            .make(
              label: "alarm",
              names: [.short("a"), .long("alarm")],
              help: "Set notification date",
              parsing: .singleValue
            ),
            .make(
              label: "alarmBefore",
              names: [.long("alarm-before")],
              help:
                "Notify this long before the due date: a whole number with m, h, d or w (15m, 1h, 1d, 1w), "
                + "or none to remove",
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
            .make(label: "notes", names: [.short("n"), .long("notes")], help: "Set notes", parsing: .singleValue),
            .make(
              label: "url",
              names: [.long("url")],
              help: "Set URL (stored in EventKit and shown in Reminders notes)",
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
              help:
                "Last day of the repeat (a date-only value includes that whole day); "
                + "alone it changes only the end of the current repeat",
              parsing: .singleValue
            ),
            .make(
              label: "repeatCount",
              names: [.long("repeat-count")],
              help:
                "Number of times the repeat happens (a whole number of 1 or more); "
                + "alone it changes only the end of the current repeat",
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
            .make(label: "clearDue", names: [.long("clear-due")], help: "Clear due date"),
            .make(label: "clearStart", names: [.long("clear-start")], help: "Clear start date"),
            .make(label: "clearAlarm", names: [.long("clear-alarm")], help: "Clear alarm"),
            .make(label: "clearUrl", names: [.long("clear-url")], help: "Clear URL"),
            .make(label: "noRepeat", names: [.long("no-repeat")], help: "Remove recurrence"),
            .make(label: "complete", names: [.long("complete")], help: "Mark completed"),
            .make(label: "incomplete", names: [.long("incomplete")], help: "Mark incomplete"),
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
        "remindctl edit 1 --title \"New title\"",
        "remindctl edit 4A83 --due tomorrow",
        "remindctl edit 4A83 --start 2026-01-01",
        "remindctl edit 4A83 --clear-start",
        "remindctl edit 4A83 --alarm \"2026-01-03 08:55\"",
        "remindctl edit 4A83 --alarm-before 15m",
        "remindctl edit 4A83 --repeat weekly",
        "remindctl edit 4A83 --repeat \"weekly on mon,fri\"",
        "remindctl edit 4A83 --repeat \"monthly on last fri\"",
        "remindctl edit 4A83 --repeat-until 2026-12-31",
        "remindctl edit 4A83 --repeat weekly --repeat-count 8",
        "remindctl edit 2 --priority high --notes \"Call before noon\"",
        "remindctl edit 3 --clear-due --clear-alarm --no-repeat",
        "remindctl edit 4A83 --url \"https://example.com/product\"",
        "remindctl edit 4A83 --clear-url",
        "remindctl edit 4A83 --flag",
        "remindctl edit 4A83 --unflag",
        "remindctl edit 4A83 --urgent",
        "remindctl edit 4A83 --not-urgent",
        "remindctl edit 4A83 --early 1d",
        "remindctl edit 4A83 --early none",
        "remindctl edit 4A83 --tag errand --untag home",
        "remindctl edit 4A83 --link https://example.com --unlink https://example.com/old",
      ]
    ) { values, runtime in
      let result = try await run(values, runtime: runtime)
      OutputRenderer.printReminder(result.reminder, format: runtime.outputFormat)
      result.note.map(Console.printError)
    }
  }

  static func run(
    _ values: ParsedValues,
    runtime: RuntimeOptions,
    makeStore: () -> any ReminderCommandStore = { RemindersStore() },
    writer: any PrivateFieldsWriter = ReminderKitFieldsWriter(),
    reader: any PrivateFieldsReader = ReminderKitFieldsReader()
  ) async throws -> (reminder: ReminderItem, note: String?) {
    guard let input = values.argument(0) else {
      throw ParsedValuesError.missingArgument("id")
    }
    let privateChange = try CommandHelpers.privateChange(values, runtime: runtime)

    let store = makeStore()
    try await store.requestAccess()
    let resolved = try await CommandHelpers.resolveShowIdentifiers([input], in: store)
    guard let reminder = resolved.first else {
      throw RemindCoreError.reminderNotFound(input)
    }

    let edit = try ParsedEdit(values)
    let outcome = try saveOutcome(hasPublicChanges: edit.hasPublicChanges, privateChange: privateChange)
    let update = edit.update

    let updated = try await PrivateFieldsSupport.save(
      privateChange,
      outcome: outcome,
      writer: writer,
      reader: reader
    ) {
      edit.hasPublicChanges ? try await store.updateReminder(id: reminder.id, update: update) : reminder
    }
    if removesImpliedEarlyReminder(clearDue: values.flag("clearDue"), privateChange: privateChange) {
      return PrivateFieldsSupport.removeEarlyReminder(
        from: updated,
        runtime: runtime,
        writer: writer,
        reader: reader
      )
    }
    let shown = PrivateFieldsSupport.attachWritten(
      [updated],
      privateChange: privateChange,
      runtime: runtime,
      reader: reader
    )[0]
    return (shown, nil)
  }
}
