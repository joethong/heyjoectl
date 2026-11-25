import Foundation
import RemindPrivate
import Testing

private final class StandInStore: NSObject {
  @objc(listWithError:)
  func list(_ error: NSErrorPointer) -> NSArray? {
    ["inbox", "work"]
  }

  @objc(echo:error:)
  func echo(_ items: NSArray, _ error: NSErrorPointer) -> NSArray? {
    items
  }

  @objc(lockedWithError:)
  func locked(_ error: NSErrorPointer) -> NSArray? {
    error?.pointee = NSError(
      domain: "StandIn", code: 7, userInfo: [NSLocalizedDescriptionKey: "the store is locked"])
    return nil
  }

  @objc(emptyWithError:)
  func empty(_ error: NSErrorPointer) -> NSArray? {
    nil
  }

  @objc(countWithError:)
  func count(_ error: NSErrorPointer) -> Int {
    3
  }

  @objc(noErrorSlot)
  func noErrorSlot() -> NSArray? {
    []
  }

  @objc(lastIsNotAnErrorSlot:)
  func lastIsNotAnErrorSlot(_ text: NSString) -> NSArray? {
    []
  }

  @objc(numberArgument:error:)
  func numberArgument(_ number: Int, _ error: NSErrorPointer) -> NSArray? {
    []
  }
}

struct RemindPrivateBridgeTests {
  private static func emptyRead() -> RPReadResult {
    RPReadResult(fields: [:], unavailableReason: nil)
  }

  private static func invoke(
    _ selector: String, arguments: [Any] = []
  ) -> (result: Any?, reason: String?) {
    var reason: NSString?
    let result = RPInvokeForTesting(StandInStore(), selector, arguments, &reason)
    return (result, reason as String?)
  }

  @Test("A slow read comes back unavailable with the time-out reason, within the limit")
  func slowReadTimesOut() {
    let started = Date()

    let result = RPReadWithTimeout(0.2) {
      Thread.sleep(forTimeInterval: 1.5)
      return Self.emptyRead()
    }

    #expect(result.unavailableReason == "ReminderKit did not answer within 0.2 seconds")
    #expect(result.fields.isEmpty)
    #expect(Date().timeIntervalSince(started) < 1.0)
  }

  @Test("A read that finishes in time is returned as it is")
  func fastReadIsReturned() {
    let answer = RPReadResult(fields: [:], unavailableReason: "marker")

    let result = RPReadWithTimeout(5) { answer }

    #expect(result === answer)
    #expect(result.unavailableReason == "marker")
  }

  @Test("A read that raises an Objective-C exception comes back unavailable")
  func exceptionIsReported() {
    let result = RPReadWithTimeout(5) {
      NSException(name: NSExceptionName("StandInException"), reason: "the store fell over").raise()
      return Self.emptyRead()
    }

    #expect(result.unavailableReason == "ReminderKit raised StandInException: the store fell over")
  }

  @Test("A selector the store lacks is reported by name")
  func missingSelector() {
    let outcome = Self.invoke("fetchSomethingElseWithError:")

    #expect(outcome.result == nil)
    #expect(outcome.reason == "REMStore has no fetchSomethingElseWithError:")
  }

  @Test(
    "A selector with the wrong shape is refused before it is called",
    arguments: [
      "countWithError:",
      "noErrorSlot",
      "lastIsNotAnErrorSlot:",
    ])
  func wrongSignature(selector: String) {
    let outcome = Self.invoke(selector)

    #expect(outcome.result == nil)
    #expect(outcome.reason == "REMStore \(selector) has an unexpected signature")
  }

  @Test("An argument slot that is not an object is refused")
  func nonObjectArgument() {
    let outcome = Self.invoke("numberArgument:error:", arguments: [NSNull()])

    #expect(outcome.result == nil)
    #expect(outcome.reason == "REMStore numberArgument:error: has an unexpected signature")
  }

  @Test("A selector with the expected shape is called and its arguments passed through")
  func matchingSelector() {
    let plain = Self.invoke("listWithError:")
    let echoed = Self.invoke("echo:error:", arguments: [["a", "b"] as NSArray])

    #expect(plain.result as? [String] == ["inbox", "work"])
    #expect(plain.reason == nil)
    #expect(echoed.result as? [String] == ["a", "b"])
  }

  @Test("The store's error text becomes the reason")
  func storeError() {
    let outcome = Self.invoke("lockedWithError:")

    #expect(outcome.result == nil)
    #expect(outcome.reason == "the store is locked")
  }

  @Test("An empty answer without an error is reported")
  func nothingReturned() {
    let outcome = Self.invoke("emptyWithError:")

    #expect(outcome.result == nil)
    #expect(outcome.reason == "REMStore emptyWithError: returned nothing")
  }
}
