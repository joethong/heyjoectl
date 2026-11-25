import Testing

@testable import remindctl

@MainActor
struct ForkIdentityTests {
  @Test("The fork prints its own release version")
  func forkVersion() {
    #expect(RemindctlVersion.current == "0.3.9-joe.5")
  }

  @Test("Root help names the program remindjoectl")
  func rootHelpNamesFork() {
    let router = CommandRouter()
    let lines = HelpPrinter.renderRoot(
      version: RemindctlVersion.current,
      rootName: router.rootName,
      commands: router.specs
    )
    #expect(lines.first == "remindjoectl 0.3.9-joe.5")
    #expect(lines.contains("  remindjoectl [command] [options]"))
    #expect(lines.last == "Run 'remindjoectl <command> --help' for details.")
  }
}
