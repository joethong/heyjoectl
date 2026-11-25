import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

private final class RecordingReader: PrivateFieldsReader, @unchecked Sendable {
  private let lock = NSLock()
  private let answer: PrivateFieldsRead
  private var recordedScopes: [ReminderFetchScope] = []

  init(_ answer: PrivateFieldsRead) {
    self.answer = answer
  }

  var scopes: [ReminderFetchScope] {
    lock.withLock { recordedScopes }
  }

  func unavailableReason() -> String? { nil }

  func read(ids _: Set<String>, scope: ReminderFetchScope) -> PrivateFieldsRead {
    lock.withLock { recordedScopes.append(scope) }
    return answer
  }
}

@MainActor
struct PrivateFieldsSupportTests {
  private static let reminder = ReminderItem(
    id: "A1",
    title: "Call bank",
    notes: nil,
    isCompleted: false,
    completionDate: nil,
    priority: .none,
    dueDate: nil,
    listID: "L1",
    listName: "Inbox"
  )

  private static func runtime(_ arguments: [String]) throws -> RuntimeOptions {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    return RuntimeOptions(parsedValues: invocation.parsedValues)
  }

  @Test("--no-private parses on read commands and is off by default")
  func noPrivateFlagParses() throws {
    #expect(try Self.runtime(["show", "all", "--no-private"]).noPrivate)
    #expect(try Self.runtime(["search", "milk", "--json", "--no-private"]).noPrivate)
    #expect(try Self.runtime(["doctor", "--no-private"]).noPrivate)
    #expect(try Self.runtime(["list", "Work", "--no-private"]).noPrivate)
    #expect(try Self.runtime(["info", "1", "--no-private"]).noPrivate)
    #expect(try Self.runtime(["export", "--no-private"]).noPrivate)
    #expect(try Self.runtime(["open", "--no-private"]).noPrivate)
    #expect(try !Self.runtime(["show", "all"]).noPrivate)
  }

  @Test("Known values are attached and no note is printed")
  func attachesWithoutNote() throws {
    let reader = RecordingReader(.fields(["A1": PrivateReminderFields(flagged: true, urgent: false)]))
    var notes: [String] = []

    let attached = PrivateFieldsSupport.attach(
      to: [Self.reminder],
      scope: .openOnly,
      runtime: try Self.runtime(["show", "open"]),
      reader: reader
    ) { notes.append($0) }

    #expect(attached[0].flagged == true)
    #expect(attached[0].urgent == false)
    #expect(reader.scopes == [.openOnly])
    #expect(notes.isEmpty)
  }

  @Test("Unavailable prints one stderr note and keeps the reminders unchanged")
  func unavailablePrintsNote() throws {
    let reader = RecordingReader(.unavailable(reason: "ReminderKit has no REMStore"))
    var notes: [String] = []

    let attached = PrivateFieldsSupport.attach(
      to: [Self.reminder],
      scope: .everything,
      runtime: try Self.runtime(["show", "all"]),
      reader: reader
    ) { notes.append($0) }

    #expect(attached == [Self.reminder])
    #expect(
      notes == [
        "remindctl: private fields unavailable: ReminderKit has no REMStore; run `remindctl doctor` for details"
      ]
    )
  }

  private static let dlopenReason =
    "ReminderKit did not load (dlopen(/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit, 0x0002): "
    + "tried: '/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit' (no such file), "
    + "'/System/Volumes/Preboot/Cryptexes/OS/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit' "
    + "(no such file), '/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit' (no such file))"

  @Test("The note keeps only the first clause of a long reason and points to doctor")
  func noteIsOneShortLine() throws {
    let reader = RecordingReader(.unavailable(reason: Self.dlopenReason))
    var notes: [String] = []

    _ = PrivateFieldsSupport.attach(
      to: [Self.reminder],
      scope: .everything,
      runtime: try Self.runtime(["show", "all"]),
      reader: reader
    ) { notes.append($0) }

    #expect(
      notes == ["remindctl: private fields unavailable: ReminderKit did not load; run `remindctl doctor` for details"]
    )
    #expect(notes.allSatisfy { !$0.contains("\n") && !$0.contains("/System") })
  }

  @Test(
    "The short reason stops at the first ' (', ':' or line break and is capped near 100 characters",
    arguments: [
      ("ReminderKit did not load (dlopen(/x): tried)", "ReminderKit did not load"),
      ("ReminderKit raised NSRangeException: index 4 beyond bounds", "ReminderKit raised NSRangeException"),
      ("Store is busy\nTry again later", "Store is busy"),
      ("ReminderKit has no REMStore", "ReminderKit has no REMStore"),
      (String(repeating: "a", count: 300), String(repeating: "a", count: 99) + "…"),
      ("", "unknown reason"),
      (": nothing before the colon", "unknown reason"),
    ]
  )
  func shortReason(reason: String, expected: String) {
    #expect(PrivateFieldsSupport.shortReason(reason) == expected)
  }

  @Test("--no-private skips the reader and prints no note")
  func noPrivateSkipsReader() throws {
    let reader = RecordingReader(.unavailable(reason: "should not be asked"))
    var notes: [String] = []

    let runtime = try Self.runtime(["show", "all", "--no-private"])

    let attached = PrivateFieldsSupport.attach(
      to: [Self.reminder],
      scope: .everything,
      runtime: runtime,
      reader: reader
    ) { notes.append($0) }

    #expect(attached == [Self.reminder])
    #expect(reader.scopes.isEmpty)
    #expect(notes.isEmpty)
  }

  @Test("Formats that never show the fields skip the reader and print no note")
  func hiddenFormatsSkipReader() throws {
    let reader = RecordingReader(.unavailable(reason: "should not be asked"))
    var notes: [String] = []

    for arguments in [["show", "all", "--plain"], ["show", "all", "--quiet"], ["show", "all", "--format", "table"]] {
      let attached = PrivateFieldsSupport.attach(
        to: [Self.reminder],
        scope: .everything,
        runtime: try Self.runtime(arguments),
        reader: reader
      ) { notes.append($0) }
      #expect(attached == [Self.reminder])
    }

    #expect(reader.scopes.isEmpty)
    #expect(notes.isEmpty)
  }

  @Test("JSON includes flagged and urgent when known and leaves them out when not")
  func reminderJSONKeys() throws {
    var known = Self.reminder
    known.flagged = true
    known.urgent = false

    let knownJSON = try OutputRenderer.renderJSON(known)
    let unknownJSON = try OutputRenderer.renderJSON(Self.reminder)

    #expect(knownJSON.contains("\"flagged\" : true"))
    #expect(knownJSON.contains("\"urgent\" : false"))
    #expect(!unknownJSON.contains("flagged"))
    #expect(!unknownJSON.contains("urgent"))
  }

  @Test("Standard lines mark flagged and Urgent reminders only")
  func standardMarks() {
    var both = Self.reminder
    both.flagged = true
    both.urgent = true
    var neither = Self.reminder
    neither.flagged = false
    neither.urgent = false

    #expect(OutputRenderer.standardLine(for: both) == "[ ] Call bank [Inbox] — no due date [flagged] [urgent]")
    #expect(OutputRenderer.standardLine(for: neither) == "[ ] Call bank [Inbox] — no due date")
    #expect(OutputRenderer.standardLine(for: Self.reminder) == "[ ] Call bank [Inbox] — no due date")
  }

  @Test("Doctor reports private fields as available")
  func doctorAvailable() throws {
    let reader = RecordingReader(.fields([:]))

    let diagnostics = PrivateFieldsDiagnostics.collect(
      runtime: try Self.runtime(["doctor"]),
      authorized: true,
      reader: reader
    )

    #expect(diagnostics.available)
    #expect(diagnostics.reason == nil)
    #expect(diagnostics.summaryLine == "Flag and Urgent (ReminderKit): available")
    let json = try OutputRenderer.renderJSON(
      PrivateFieldsDiagnostics(
        read: .fields([:]),
        writes: PrivateWritesDiagnostics(unavailableReason: nil),
        macOSVersion: "27.0.1"
      )
    )
    #expect(
      json == """
        {
          "available" : true,
          "macOSVersion" : "27.0.1",
          "reason" : null,
          "writes" : {
            "available" : true,
            "reason" : null
          }
        }
        """
    )
  }

  @Test("Doctor reports a missing read method even when the store read itself works")
  func doctorChecksReadMethods() throws {
    let diagnostics = PrivateFieldsDiagnostics.collect(
      runtime: try Self.runtime(["doctor"]),
      authorized: true,
      reader: MissingMethodReader(reason: "REMHashtag has no name")
    )

    #expect(!diagnostics.available)
    #expect(diagnostics.reason == "REMHashtag has no name")
  }

  @Test("Doctor keeps the full reason in the summary line and in JSON")
  func doctorKeepsFullReason() throws {
    let reader = RecordingReader(.unavailable(reason: Self.dlopenReason))

    let diagnostics = PrivateFieldsDiagnostics.collect(
      runtime: try Self.runtime(["doctor"]),
      authorized: true,
      reader: reader
    )

    #expect(diagnostics.reason == Self.dlopenReason)
    #expect(diagnostics.summaryLine.contains(Self.dlopenReason))
    let rendered = try OutputRenderer.renderJSON(diagnostics)
    let json = try JSONSerialization.jsonObject(with: Data(rendered.utf8)) as? [String: Any]
    #expect(json?["reason"] as? String == Self.dlopenReason)
  }

  @Test("Doctor reports private fields as unavailable with the reason")
  func doctorUnavailable() throws {
    let reader = RecordingReader(.unavailable(reason: "ReminderKit did not load"))

    let diagnostics = PrivateFieldsDiagnostics.collect(
      runtime: try Self.runtime(["doctor"]),
      authorized: true,
      reader: reader
    )
    let skipped = PrivateFieldsDiagnostics.collect(
      runtime: try Self.runtime(["doctor", "--no-private"]),
      authorized: true,
      reader: reader
    )
    let denied = PrivateFieldsDiagnostics.collect(
      runtime: try Self.runtime(["doctor"]),
      authorized: false,
      reader: reader
    )

    #expect(!diagnostics.available)
    #expect(diagnostics.reason == "ReminderKit did not load")
    #expect(diagnostics.summaryLine == "Flag and Urgent (ReminderKit): unavailable (ReminderKit did not load)")
    #expect(skipped.reason == "turned off by --no-private")
    #expect(denied.reason == "Reminders access not granted")
    #expect(reader.scopes == [.openOnly])
    let json = try OutputRenderer.renderJSON(
      PrivateFieldsDiagnostics(
        read: .unavailable(reason: "ReminderKit did not load"),
        writes: PrivateWritesDiagnostics(unavailableReason: "ReminderKit did not load"),
        macOSVersion: "27.0.1"
      )
    )
    #expect(
      json == """
        {
          "available" : false,
          "macOSVersion" : "27.0.1",
          "reason" : "ReminderKit did not load",
          "writes" : {
            "available" : false,
            "reason" : "ReminderKit did not load"
          }
        }
        """
    )
  }
}

private struct MissingMethodReader: PrivateFieldsReader {
  let reason: String

  func unavailableReason() -> String? { reason }

  func read(ids _: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead { .fields([:]) }
}
