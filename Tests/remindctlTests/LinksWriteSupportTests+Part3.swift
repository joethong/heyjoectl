import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

extension LinksWriteSupportTests {
  @Test(
    "Links are left out when private fields are off or unavailable",
    arguments: [(["show", "--json", "--no-private"], false), (["show", "--json"], true)]
  )
  func linksLeftOut(arguments: [String], unavailable: Bool) throws {
    let (_, runtime) = try Self.runtime(arguments)
    let answer: PrivateFieldsRead =
      unavailable
      ? .unavailable(reason: "ReminderKit has no REMStore")
      : .fields(["R1": PrivateReminderFields(flagged: false, urgent: false, links: ["https://a.example"])])
    var warnings: [String] = []

    let shown = PrivateFieldsSupport.attach(
      to: [Self.reminder],
      scope: .everything,
      runtime: runtime,
      reader: LinkReader(answers: [answer]),
      warn: { warnings.append($0) }
    )

    #expect(shown[0].links == nil)
    #expect(try Self.json(shown[0])?.keys.contains("links") == false)
    #expect(warnings.isEmpty == !unavailable)
  }

  @Test("Plain output marks a reminder with links as [link]")
  func plainMarker() {
    var linked = Self.reminder
    linked.links = ["https://a.example", "https://b.example"]

    #expect(OutputRenderer.standardLine(for: linked).hasSuffix("— no due date [link]"))
    #expect(!OutputRenderer.standardLine(for: Self.reminder).contains("[link]"))
  }

  @Test("info prints one Link: line per link, in stored order, and none without links")
  func infoLinkLines() throws {
    var linked = Self.reminder
    linked.links = ["https://z.example/b", "mailto:j@x.example"]

    let lines = try Self.standardOutput { OutputRenderer.printReminderDetail(linked, format: .standard) }
    let plain = try Self.standardOutput { OutputRenderer.printReminderDetail(Self.reminder, format: .standard) }

    #expect(lines.filter { $0.hasPrefix("Link:") } == ["Link: https://z.example/b", "Link: mailto:j@x.example"])
    #expect(lines.contains("Title: Buy milk"))
    #expect(!plain.contains { $0.hasPrefix("Link:") })
    #expect(plain.contains("Title: Buy milk"))
  }

  static func standardOutput(_ body: () -> Void) throws -> [String] {
    let pipe = Pipe()
    fflush(stdout)
    let saved = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    body()
    fflush(stdout)
    dup2(saved, STDOUT_FILENO)
    close(saved)
    try pipe.fileHandleForWriting.close()
    let output = try pipe.fileHandleForReading.readToEnd() ?? Data()
    return (String(bytes: output, encoding: .utf8) ?? "").split(separator: "\n").map(String.init)
  }

  @Test("The bridged change carries the URLs to add and remove")
  func bridgedChange() {
    let bridged = ReminderKitFieldsWriter.bridged(
      PrivateFieldsChange(links: LinksChange(add: ["https://a.example/x?y=1"], remove: ["mailto:j@x.example"]))
    )

    #expect(bridged.linksToAdd.map(\.absoluteString) == ["https://a.example/x?y=1"])
    #expect(bridged.linksToRemove.map(\.absoluteString) == ["mailto:j@x.example"])
    #expect(ReminderKitFieldsWriter.bridged(PrivateFieldsChange(urgent: true)).linksToAdd.isEmpty)
  }
}
