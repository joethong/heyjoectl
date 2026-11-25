import Commander
import Foundation
import RemindCore

enum SearchCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "search",
      abstract: "Search reminder titles, notes, and URLs",
      discussion: "By default searches incomplete reminders. Use --completed to include completed reminders.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "query", help: "Search text", isOptional: false)
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
              help: "Match only reminders with this tag, named without # (repeat to need every tag)",
              parsing: .singleValue
            ),
          ],
          flags: [
            .make(label: "completed", names: [.long("completed")], help: "Include completed reminders")
          ]
        )
      ),
      usageExamples: [
        "remindctl search milk",
        "remindctl search \"project notes\" --list Work",
        "remindctl search invoice --completed --json",
        "remindctl search milk --tag errand --tag home",
      ]
    ) { values, runtime in
      guard let query = values.argument(0)?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
        throw ParsedValuesError.missingArgument("query")
      }

      let tagFilter = try TagFilter.parse(values.options["tag"] ?? [], runtime: runtime)
      let store = RemindersStore()
      try await store.requestAccess()
      let listTarget = try CommandHelpers.listTarget(name: values.option("list"), id: values.option("listID"))
      let includeCompleted = values.flag("completed")
      let scope = ReminderFetchScope(searchIncludesCompleted: includeCompleted)
      let reminders = try await store.reminders(matching: listTarget, scope: scope)
      OutputRenderer.printSearchResults(
        try found(
          reminders, query: query, includeCompleted: includeCompleted, runtime: runtime, tagFilter: tagFilter),
        format: runtime.outputFormat
      )
    }
  }

  static func found(
    _ reminders: [ReminderItem],
    query: String,
    includeCompleted: Bool,
    runtime: RuntimeOptions,
    tagFilter: TagFilter?,
    reader: any PrivateFieldsReader = ReminderKitFieldsReader(),
    warn: (String) -> Void = Console.printError
  ) throws -> [ReminderItem] {
    let matches = reminders.filter { reminder in
      (includeCompleted || !reminder.isCompleted)
        && CommandHelpers.reminder(reminder, matchesSearch: query)
    }
    return try PrivateFieldsSupport.attach(
      to: matches,
      scope: ReminderFetchScope(searchIncludesCompleted: includeCompleted),
      runtime: runtime,
      tagFilter: tagFilter,
      reader: reader,
      warn: warn
    )
  }
}
