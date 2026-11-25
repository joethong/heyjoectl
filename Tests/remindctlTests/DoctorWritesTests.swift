import Foundation
import RemindCore
import RemindPrivate
import Testing

@testable import remindctl

private final class CountingWriteCheck {
  private let reason: String?
  private(set) var calls = 0

  init(_ reason: String?) {
    self.reason = reason
  }

  func callAsFunction() -> String? {
    calls += 1
    return reason
  }
}

private struct StandInReader: PrivateFieldsReader {
  let unavailable: String?

  func unavailableReason() -> String? { unavailable }

  func read(ids _: Set<String>, scope _: ReminderFetchScope) -> PrivateFieldsRead {
    unavailable.map { .unavailable(reason: $0) } ?? .fields([:])
  }
}

struct DoctorWritesTests {
  private static func runtime(_ arguments: [String]) throws -> RuntimeOptions {
    let invocation = try CommandRouter().program.resolve(arguments: ["remindjoectl"] + arguments)
    return RuntimeOptions(parsedValues: invocation.parsedValues)
  }

  private static func collect(
    _ arguments: [String] = ["doctor"],
    authorized: Bool = true,
    reader: StandInReader = StandInReader(unavailable: nil),
    writeCheck: () -> String?
  ) throws -> PrivateFieldsDiagnostics {
    PrivateFieldsDiagnostics.collect(
      runtime: try runtime(arguments),
      authorized: authorized,
      reader: reader,
      writeUnavailableReason: writeCheck
    )
  }

  private static func checkStandIns(_ names: [String: String]) -> () -> String? {
    { RPWriteTableUnavailableReasonWithClassesForTesting(names) }
  }

  @Test("Doctor reports writes as available when every write class and method is there")
  func writesAvailable() throws {
    let diagnostics = try Self.collect(writeCheck: Self.checkStandIns(writeTableStandIns()))

    #expect(diagnostics.available)
    #expect(diagnostics.writes.available)
    #expect(diagnostics.writes.reason == nil)
    #expect(diagnostics.writesSummaryLine == "Private writes (ReminderKit): available")
  }

  @Test("A missing write method makes writes unavailable, names it, and leaves reads available")
  func missingWriteMethod() throws {
    let names = writeTableStandIns(without: ("REMReminderAttachmentContextChangeItem", "removeAttachment:"))
    let reason = "\(names["REMReminderAttachmentContextChangeItem"]!) has no removeAttachment:"

    let diagnostics = try Self.collect(writeCheck: Self.checkStandIns(names))

    #expect(diagnostics.available)
    #expect(diagnostics.reason == nil)
    #expect(diagnostics.summaryLine == "Flag and Urgent (ReminderKit): available")
    #expect(!diagnostics.writes.available)
    #expect(diagnostics.writes.reason == reason)
    #expect(diagnostics.writesSummaryLine == "Private writes (ReminderKit): unavailable (\(reason))")
  }

  @Test("A missing read method makes writes unavailable too, as a real write checks the read side")
  func missingReadMethod() throws {
    let diagnostics = try Self.collect(
      reader: StandInReader(unavailable: "REMHashtag has no name"),
      writeCheck: Self.checkStandIns(writeTableStandIns())
    )

    #expect(!diagnostics.available)
    #expect(diagnostics.reason == "REMHashtag has no name")
    #expect(!diagnostics.writes.available)
    #expect(diagnostics.writes.reason == "REMHashtag has no name")
  }

  @Test("--no-private makes writes unavailable with the reason reads give, without checking ReminderKit")
  func noPrivate() throws {
    let check = CountingWriteCheck(nil)

    let diagnostics = try Self.collect(["doctor", "--no-private"], writeCheck: { check() })

    #expect(diagnostics.reason == "turned off by --no-private")
    #expect(!diagnostics.writes.available)
    #expect(diagnostics.writes.reason == diagnostics.reason)
    #expect(check.calls == 0)
  }

  @Test("Without Reminders access writes are unavailable with the reason reads give")
  func notAuthorized() throws {
    let check = CountingWriteCheck(nil)

    let diagnostics = try Self.collect(authorized: false, writeCheck: { check() })

    #expect(diagnostics.reason == "Reminders access not granted")
    #expect(diagnostics.writes.reason == "Reminders access not granted")
    #expect(check.calls == 0)
  }

  @Test("When ReminderKit does not load, reads and writes are unavailable with the same reason")
  func reminderKitNotLoaded() throws {
    let reason = "ReminderKit did not load"

    let diagnostics = try Self.collect(reader: StandInReader(unavailable: reason), writeCheck: { reason })

    #expect(!diagnostics.available)
    #expect(!diagnostics.writes.available)
    #expect(diagnostics.reason == reason)
    #expect(diagnostics.writes.reason == reason)
    #expect(diagnostics.writesSummaryLine == "Private writes (ReminderKit): unavailable (\(reason))")
  }

  @Test("doctor --json keeps its private-fields keys and adds only writes")
  func jsonShape() throws {
    let available = PrivateFieldsDiagnostics(
      read: .fields([:]),
      writes: PrivateWritesDiagnostics(unavailableReason: nil),
      macOSVersion: "27.0.1"
    )
    let unavailable = PrivateFieldsDiagnostics(
      read: .unavailable(reason: "ReminderKit did not load"),
      writes: PrivateWritesDiagnostics(unavailableReason: "ReminderKit did not load"),
      macOSVersion: "27.0.1"
    )

    #expect(
      try OutputRenderer.renderJSON(available) == """
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
    #expect(
      try OutputRenderer.renderJSON(unavailable) == """
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
