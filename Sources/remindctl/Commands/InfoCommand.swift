import Commander
import Foundation
import RemindCore

enum InfoCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "info",
      abstract: "Show reminder details",
      discussion: "Use an index from the default show view or an ID prefix.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "id", help: "Index or ID prefix", isOptional: false)
          ]
        )
      ),
      usageExamples: [
        "remindctl info 1",
        "remindctl info 4A83",
        "remindctl info 4A83 --json",
      ]
    ) { values, runtime in
      let reminder = try await run(values, runtime: runtime)
      OutputRenderer.printReminderDetail(reminder, format: runtime.outputFormat)
    }
  }

  static func run(
    _ values: ParsedValues,
    runtime: RuntimeOptions,
    makeStore: () -> any ReminderCommandStore = { RemindersStore() },
    reader: any PrivateFieldsReader = ReminderKitFieldsReader()
  ) async throws -> ReminderItem {
    guard let input = values.argument(0) else {
      throw ParsedValuesError.missingArgument("id")
    }

    let store = makeStore()
    try await store.requestAccess()
    let resolved = try await CommandHelpers.resolveShowIdentifiers([input], in: store)
    guard let reminder = resolved.first else {
      throw RemindCoreError.reminderNotFound(input)
    }

    return PrivateFieldsSupport.attach(to: [reminder], scope: .everything, runtime: runtime, reader: reader)[0]
  }
}
