import Commander
import Foundation
import RemindCore

enum CompleteCommand {
  static var spec: CommandSpec {
    CommandSpec(
      name: "complete",
      abstract: "Mark reminders complete",
      discussion: "Use indexes or ID prefixes from show output.",
      signature: CommandSignatures.withRuntimeFlags(
        CommandSignature(
          arguments: [
            .make(label: "ids", help: "Indexes or ID prefixes", isOptional: true, parsing: .remaining)
          ],
          flags: [
            .make(label: "dryRun", names: [.short("n"), .long("dry-run")], help: "Preview without changes")
          ]
        )
      ),
      usageExamples: [
        "remindctl complete 1",
        "remindctl complete 1 2 3",
        "remindctl complete 4A83",
      ]
    ) { values, runtime in
      let shown = try await run(values, runtime: runtime)
      OutputRenderer.printReminders(shown, format: runtime.outputFormat)
    }
  }

  static func run(
    _ values: ParsedValues,
    runtime: RuntimeOptions,
    makeStore: () -> any ReminderCommandStore = { RemindersStore() },
    reader: any PrivateFieldsReader = ReminderKitFieldsReader()
  ) async throws -> [ReminderItem] {
    let inputs = values.positional
    guard !inputs.isEmpty else {
      throw ParsedValuesError.missingArgument("ids")
    }

    let store = makeStore()
    try await store.requestAccess()
    let resolved = try await CommandHelpers.resolveShowIdentifiers(inputs, in: store)

    let reminders = values.flag("dryRun") ? resolved : try await store.completeReminders(ids: resolved.map { $0.id })
    return PrivateFieldsSupport.attachWritten(reminders, privateChange: nil, runtime: runtime, reader: reader)
  }
}
