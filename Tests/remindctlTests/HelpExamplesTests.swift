import Foundation
import RemindCore
import Testing

@testable import remindctl

@MainActor
struct HelpExamplesTests {
  private static func words(_ example: String) -> [String] {
    var words: [String] = []
    var current = ""
    var quoted = false
    var started = false
    for character in example {
      if character == "\"" {
        quoted.toggle()
        started = true
      } else if character == " " && !quoted {
        if started { words.append(current) }
        current = ""
        started = false
      } else {
        current.append(character)
        started = true
      }
    }
    if started { words.append(current) }
    return words
  }

  @Test("The word splitter keeps a quoted value together")
  func splitsQuotedValues() {
    #expect(
      Self.words("remindctl add \"Call mom\" --due \"2026-01-03 09:00\" --early 1w") == [
        "remindctl", "add", "Call mom", "--due", "2026-01-03 09:00", "--early", "1w",
      ])
  }

  @Test("Every add and edit help example resolves, and its dates, repeat and early values parse")
  func examplesParse() throws {
    let examples = CommandRouter.commandSpecs.filter { ["add", "edit"].contains($0.name) }.flatMap(\.usageExamples)
    #expect(examples.count > 30)
    for example in examples {
      let arguments = Array(Self.words(example).dropFirst())
      let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
      let values = invocation.parsedValues

      for label in ["due", "start", "alarm"] {
        if let value = values.option(label) {
          #expect(DateParsing.parseUserDateWithMetadata(value) != nil, "--\(label) \(value) in: \(example)")
        }
      }
      if let value = values.option("repeat") {
        _ = try CommandHelpers.parseRecurrence(value)
      }
      if let value = values.option("early") {
        _ = try CommandHelpers.parseEarlyReminder(value)
      }
    }
  }
}
