import Commander
import Foundation
import RemindCore

enum ShowCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "show",
      abstract: "Show reminders",
      discussion: "Filters: today, tomorrow, week, overdue, upcoming, open, completed, all, or a date string.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(
              label: "filter",
              help: "today|tomorrow|week|overdue|upcoming|open|completed|all|<date>",
              isOptional: true
            )
          ],
          options: [
            .make(
              label: "list",
              names: [.short("l"), .long("list")],
              help: "Limit to a specific list",
              parsing: .singleValue
            ),
            .make(
              label: "listID",
              names: [.long("list-id")],
              help: "Limit to a list by ID or ID prefix",
              parsing: .singleValue
            ),
            .make(
              label: "tag",
              names: [.long("tag")],
              help: "Show only reminders with this tag, named without # (repeat to need every tag)",
              parsing: .singleValue
            ),
          ]
        )
      ),
      usageExamples: [
        "remindctl",
        "remindctl today",
        "remindctl show overdue",
        "remindctl show 2026-01-04",
        "remindctl show --list Work",
        "remindctl show all --tag errand --tag home",
      ]
    ) { values, runtime in
      let listTarget = try CommandHelpers.listTarget(name: values.option("list"), id: values.option("listID"))
      let tagFilter = try TagFilter.parse(values.options["tag"] ?? [], runtime: runtime)
      let filterToken = values.argument(0)

      let filter: ReminderFilter
      if let token = filterToken {
        guard let parsed = ReminderFiltering.parse(token) else {
          throw RemindCoreError.operationFailed("Unknown filter: \"\(token)\"")
        }
        filter = parsed
      } else {
        filter = .today
      }

      let store = RemindersStore()
      try await store.requestAccess()
      let scope = ReminderFetchScope(filter: filter)
      let reminders = try await store.reminders(matching: listTarget, scope: scope)
      OutputRenderer.printReminders(
        try shown(reminders, filter: filter, runtime: runtime, tagFilter: tagFilter),
        format: runtime.outputFormat
      )
    }
  }

  static func shown(
    _ reminders: [ReminderItem],
    filter: ReminderFilter,
    runtime: RuntimeOptions,
    tagFilter: TagFilter?,
    reader: any PrivateFieldsReader = ReminderKitFieldsReader(),
    warn: (String) -> Void = Console.printError
  ) throws -> [ReminderItem] {
    try PrivateFieldsSupport.attach(
      to: ReminderFiltering.apply(reminders, filter: filter),
      scope: ReminderFetchScope(filter: filter),
      runtime: runtime,
      tagFilter: tagFilter,
      reader: reader,
      warn: warn
    )
  }
}
