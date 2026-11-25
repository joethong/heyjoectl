import RemindCore
import Testing

@testable import remindctl

@MainActor
struct HelpPrinterTests {
  @Test("Root help includes commands")
  func rootHelp() {
    let specs = [
      ShowCommand.spec,
      ListCommand.spec,
      SearchCommand.spec,
      InfoCommand.spec,
      AddCommand.spec,
      StatusCommand.spec,
      AuthorizeCommand.spec,
      DoctorCommand.spec,
      ExportCommand.spec,
      LinkCommand.spec,
      OpenCommand.spec,
      CompletionCommand.spec,
    ]
    let lines = HelpPrinter.renderRoot(version: "0.0.0", rootName: "remindjoectl", commands: specs)
    let joined = lines.joined(separator: "\n")
    #expect(joined.contains("show"))
    #expect(joined.contains("list"))
    #expect(joined.contains("search"))
    #expect(joined.contains("info"))
    #expect(joined.contains("add"))
    #expect(joined.contains("status"))
    #expect(joined.contains("authorize"))
    #expect(joined.contains("doctor"))
    #expect(joined.contains("export"))
    #expect(joined.contains("completion"))
  }

  @Test("Add and edit help include alarm, location, repeat, and URL options")
  func alarmLocationRepeatAndURLHelp() {
    let addHelp = HelpPrinter.renderCommand(rootName: "remindjoectl", spec: AddCommand.spec).joined(separator: "\n")
    let editHelp = HelpPrinter.renderCommand(rootName: "remindjoectl", spec: EditCommand.spec).joined(separator: "\n")

    #expect(addHelp.contains("--alarm"))
    #expect(addHelp.contains("--location"))
    #expect(addHelp.contains("--leaving"))
    #expect(addHelp.contains("--url"))
    #expect(addHelp.contains("--repeat"))
    #expect(editHelp.contains("--alarm"))
    #expect(editHelp.contains("--clear-alarm"))
    #expect(editHelp.contains("--url"))
    #expect(editHelp.contains("--clear-url"))
    #expect(editHelp.contains("--repeat"))
    #expect(editHelp.contains("--no-repeat"))
  }

  @Test("Add and edit help describe --alarm-before and show an example")
  func alarmBeforeHelp() {
    let addHelp = HelpPrinter.renderCommand(rootName: "remindjoectl", spec: AddCommand.spec).joined(separator: "\n")
    let editHelp = HelpPrinter.renderCommand(rootName: "remindjoectl", spec: EditCommand.spec).joined(separator: "\n")

    #expect(addHelp.contains("--alarm-before"))
    #expect(addHelp.contains("--alarm-before 15m"))
    #expect(editHelp.contains("--alarm-before"))
    #expect(editHelp.contains("--alarm-before 15m"))
    #expect(editHelp.contains("--alarm-before none"))
  }

  @Test("Add and edit help give the --early limit, built from countInOneYear")
  func earlyHelpGivesLimit() {
    let limits = EarlyReminderUnit.allCases.map { "\($0.countInOneYear)\($0.suffix)" }
    let limit = "up to a year: " + limits.dropLast().joined(separator: ", ") + " or " + (limits.last ?? "")
    #expect(limit == "up to a year: 525600m, 8760h, 366d, 52w or 12mo")
    for spec in [AddCommand.spec, EditCommand.spec] {
      #expect(HelpPrinter.renderCommand(rootName: "remindjoectl", spec: spec).joined(separator: "\n").contains(limit))
    }
  }

  @Test("The --early error gives the same limit as the help")
  func earlyErrorGivesLimit() {
    let error = #expect(throws: RemindCoreError.self) { try CommandHelpers.parseEarlyReminder("366w") }

    #expect(error?.localizedDescription.contains("up to a year: \(EarlyReminderUnit.yearLimits),") == true)
  }

  @Test("Add and edit help explain a yearly ordinal weekday")
  func yearlyOrdinalWeekdayHelp() {
    for spec in [AddCommand.spec, EditCommand.spec] {
      let help = HelpPrinter.renderCommand(rootName: "remindjoectl", spec: spec).joined(separator: "\n")
      #expect(help.contains("on a yearly rule, last fri is the last Friday of the year"))
    }
  }

  @Test("Common help includes exact list targeting and table output")
  func listIDAndFormatHelp() {
    let showHelp = HelpPrinter.renderCommand(rootName: "remindjoectl", spec: ShowCommand.spec).joined(separator: "\n")
    let addHelp = HelpPrinter.renderCommand(rootName: "remindjoectl", spec: AddCommand.spec).joined(separator: "\n")

    #expect(showHelp.contains("--list-id"))
    #expect(showHelp.contains("--format"))
    #expect(addHelp.contains("--list-id"))
  }
}
