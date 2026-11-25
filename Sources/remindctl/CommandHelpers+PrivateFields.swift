import Commander
import Foundation
import RemindCore

extension CommandHelpers {
  static func privateChange(_ values: ParsedValues, runtime: RuntimeOptions) throws -> PrivateFieldsChange? {
    let flagged = try onOff(values, on: ("flag", "--flag"), off: ("unflag", "--unflag"))
    let urgent = try onOff(values, on: ("urgent", "--urgent"), off: ("notUrgent", "--not-urgent"))
    let earlyReminder = try values.option("early").map(parseEarlyReminder)
    let tags = try parseTags(add: values.options["tag"] ?? [], remove: values.options["untag"] ?? [])
    let links = try parseLinks(add: values.options["link"] ?? [], remove: values.options["unlink"] ?? [])
    let change = PrivateFieldsChange(
      flagged: flagged,
      urgent: urgent,
      earlyReminder: earlyReminder,
      tags: tags,
      links: links
    )
    guard change != PrivateFieldsChange() else { return nil }
    if runtime.noPrivate {
      throw RemindCoreError.operationFailed(
        "\(firstOption(of: change)) writes through ReminderKit; remove --no-private"
      )
    }
    return change
  }

  private static func firstOption(of change: PrivateFieldsChange) -> String {
    if let flagged = change.flagged {
      return flagged ? "--flag" : "--unflag"
    }
    if let urgent = change.urgent {
      return urgent ? "--urgent" : "--not-urgent"
    }
    if change.earlyReminder != nil {
      return "--early"
    }
    if let tags = change.tags {
      return tags.add.isEmpty ? "--untag" : "--tag"
    }
    return change.links?.add.isEmpty == false ? "--link" : "--unlink"
  }

  private static func parseLinks(add: [String], remove: [String]) throws -> LinksChange? {
    let adding = try links(
      add,
      option: "--link",
      hint: "use an absolute http, https or mailto URL, such as https://example.com",
      accepts: isWebOrMail
    )
    let removing = try links(
      remove,
      option: "--unlink",
      hint: "use a link as `info` prints it, such as https://example.com",
      accepts: { _ in true }
    )
    if let both = adding.first(where: { link in removing.contains { LinksChange.sameLink($0, link) } }) {
      throw RemindCoreError.operationFailed("Use either --link \(both) or --unlink \(both), not both")
    }
    return adding.isEmpty && removing.isEmpty ? nil : LinksChange(add: adding, remove: removing)
  }

  private static func isWebOrMail(_ url: URL) -> Bool {
    guard let scheme = url.scheme?.lowercased() else { return false }
    return scheme == "mailto"
      ? (url as NSURL).resourceSpecifier?.isEmpty == false
      : ["http", "https"].contains(scheme) && url.host?.isEmpty == false
  }

  private static func links(
    _ values: [String],
    option: String,
    hint: String,
    accepts: (URL) -> Bool
  ) throws -> [String] {
    var links: [String] = []
    for value in values {
      guard !value.isEmpty, let url = URL(string: value, encodingInvalidCharacters: false), accepts(url) else {
        throw RemindCoreError.operationFailed("Invalid \(option): \"\(value)\" (\(hint))")
      }
      if !links.contains(where: { LinksChange.sameLink($0, url.absoluteString) }) {
        links.append(url.absoluteString)
      }
    }
    return links
  }

  private static func parseTags(add: [String], remove: [String]) throws -> TagsChange? {
    let adding = try tagNames(add, option: "--tag")
    let removing = try tagNames(remove, option: "--untag")
    let both = adding.first { name in removing.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }
    if let both {
      throw RemindCoreError.operationFailed("Use either --tag \(both) or --untag \(both), not both")
    }
    return adding.isEmpty && removing.isEmpty ? nil : TagsChange(add: adding, remove: removing)
  }

  static func tagNames(_ values: [String], option: String) throws -> [String] {
    var names: [String] = []
    for value in values {
      let name = String(value.drop { $0 == "#" })
      if name.contains(",") {
        throw RemindCoreError.operationFailed(
          "Invalid \(option): \"\(value)\" (one tag name with no commas; repeat \(option) for more)"
        )
      }
      if name.isEmpty || name.contains(where: \.isWhitespace) {
        throw RemindCoreError.operationFailed(
          "Invalid \(option): \"\(value)\" (use a tag name with no spaces, such as home or errand)"
        )
      }
      if !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
        names.append(name)
      }
    }
    return names
  }

  static func parseEarlyReminder(_ value: String) throws -> EarlyReminderChange {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = trimmed.lowercased()
    if normalized == "none" {
      return .remove
    }
    if trimmed.last == "M", trimmed.dropLast().allSatisfy({ $0.isASCII && $0.isNumber }) {
      throw RemindCoreError.operationFailed(
        "Invalid --early: \"\(value)\" (M could mean minutes or months; use m for minutes or mo for months)"
      )
    }
    let units: [String: EarlyReminderUnit] = [
      "m": .minutes, "min": .minutes, "h": .hours, "d": .days, "w": .weeks, "mo": .months,
    ]
    let digits = normalized.prefix { $0.isASCII && $0.isNumber }
    guard let unit = units[String(normalized.dropFirst(digits.count))], let count = Int(digits),
      (1...unit.countInOneYear).contains(count)
    else {
      throw RemindCoreError.operationFailed(
        "Invalid --early: \"\(value)\" "
          + "(use a whole number above 0 with m, min, h, d, w or mo, up to a year: \(EarlyReminderUnit.yearLimits), "
          + "such as 15m, 1h, 2d, 1w or 1mo, or none)"
      )
    }
    return .set(EarlyReminder(count: count, unit: unit))
  }

  private static func onOff(
    _ values: ParsedValues,
    on: (label: String, option: String),
    off: (label: String, option: String)
  ) throws -> Bool? {
    let isOn = values.flag(on.label)
    let isOff = values.flag(off.label)
    if isOn && isOff {
      throw RemindCoreError.operationFailed("Use either \(on.option) or \(off.option), not both")
    }
    return isOn ? true : (isOff ? false : nil)
  }
}
