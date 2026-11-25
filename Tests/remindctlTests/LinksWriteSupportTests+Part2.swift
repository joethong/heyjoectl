import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

extension LinksWriteSupportTests {
  @Test(
    "When writing or reading links is not possible, nothing is saved and the message names the links",
    arguments: [
      (
        LinksChange(add: ["https://a.example"]), String?("ReminderKit has no REMSaveRequest"), String?.none,
        "link https://a.example not added: ReminderKit has no REMSaveRequest; nothing was changed"
      ),
      (
        LinksChange(add: ["https://a.example", "https://b.example"], remove: ["mailto:j@x.example"]),
        "RPStandIn has no addURLAttachmentWithURL:", nil,
        "links https://a.example, https://b.example not added and link mailto:j@x.example not removed: "
          + "RPStandIn has no addURLAttachmentWithURL:; nothing was changed"
      ),
      (
        LinksChange(remove: ["https://a.example"]), nil, "REMReminderStorage has no attachments",
        "link https://a.example not removed: REMReminderStorage has no attachments; nothing was changed"
      ),
    ]
  )
  func unavailableChangesNothing(
    links: LinksChange,
    writeSide: String?,
    readSide: String?,
    expected: String
  ) async throws {
    let store = LinkStore()
    let writer = LinkWriter(unavailable: writeSide)
    let reader = LinkReader(answers: [.fields([:])], unavailable: readSide)

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        PrivateFieldsChange(links: links),
        outcome: .created,
        writer: writer,
        reader: reader,
        publicSave: store.save
      )
    }

    #expect(message == expected)
    #expect(store.saves == 0)
    #expect(writer.writes.isEmpty)
    #expect(reader.reads == 0)
  }

  @Test(
    "A failed or unknown link write after the public save names what was saved and what was not",
    arguments: [
      (
        PrivateFieldsChange(links: LinksChange(add: ["https://a.example"])),
        PrivateFieldsWriteResult.failed(reason: "the store is locked"),
        "reminder created (id R1); link https://a.example not added: the store is locked"
      ),
      (
        PrivateFieldsChange(flagged: true, links: LinksChange(remove: ["https://a.example"])),
        .failed(reason: "the store is locked"),
        "reminder created (id R1); flag not set and link https://a.example not removed: the store is locked"
      ),
      (
        PrivateFieldsChange(links: LinksChange(add: ["https://b.example"], remove: ["https://a.example"])),
        .unknown(reason: "ReminderKit did not answer within 10 seconds"),
        "reminder created (id R1); link https://b.example may or may not be added and link https://a.example "
          + "may or may not be removed: ReminderKit did not answer within 10 seconds"
      ),
    ]
  )
  func failedWriteNamesWhatWasSaved(
    change: PrivateFieldsChange,
    answer: PrivateFieldsWriteResult,
    expected: String
  ) async throws {
    let store = LinkStore()

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        change,
        outcome: .created,
        writer: LinkWriter(answer: answer),
        reader: LinkReader([], []),
        publicSave: store.save
      )
    }

    #expect(message == expected)
    #expect(store.saves == 1)
  }

  @Test(
    "Links that read back differently exit with what was saved and the whole set that was read",
    arguments: [
      (
        LinksChange(add: ["https://a.example"]), [String](), [String](),
        "link https://a.example added but read back as no links"
      ),
      (
        LinksChange(add: ["https://a.example"]), [], ["https://a.example", "https://a.example"],
        "link https://a.example added but read back as links https://a.example, https://a.example"
      ),
      (
        LinksChange(remove: ["https://a.example"]), ["https://a.example", "https://b.example"],
        ["https://a.example", "https://b.example"],
        "link https://a.example removed but read back as links https://a.example, https://b.example"
      ),
      (
        LinksChange(add: ["https://b.example"]), ["https://a.example"], ["https://b.example"],
        "link https://b.example added but read back as links https://b.example"
      ),
      (
        LinksChange(add: ["https://a.example/X"]), [], ["https://a.example/x"],
        "link https://a.example/X added but read back as links https://a.example/x"
      ),
    ]
  )
  func readBackMismatch(links: LinksChange, before: [String], readBack: [String], expected: String) async throws {
    let message = await Self.message {
      _ = try await Self.save(links, before: before, readBack: readBack)
    }

    #expect(message == "reminder updated (id R1); \(expected)")
  }

  @Test("Links missing from the read-back exit with what was saved")
  func noLinksValue() async throws {
    let message = await Self.message {
      _ = try await Self.save(LinksChange(remove: ["https://a.example"]), readBack: nil)
    }

    #expect(message == "reminder updated (id R1); link https://a.example removed but read back as no links value")
  }

  @Test(
    "When the links already on the reminder cannot be read, nothing is written through ReminderKit",
    arguments: [
      (
        [PrivateFieldsRead.unavailable(reason: "ReminderKit did not answer within 10 seconds")],
        "reminder updated (id R1); link https://a.example not added: ReminderKit did not answer within 10 seconds"
      ),
      (
        [.fields([:])],
        "reminder updated (id R1); link https://a.example not added: "
          + "the links already on the reminder could not be read"
      ),
      (
        [.fields(["R1": PrivateReminderFields(flagged: false, urgent: false, tags: [])])],
        "reminder updated (id R1); link https://a.example not added: "
          + "the links already on the reminder could not be read"
      ),
    ]
  )
  func unreadableLinksBeforeWrite(answers: [PrivateFieldsRead], expected: String) async throws {
    let store = LinkStore()
    let writer = LinkWriter()

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        PrivateFieldsChange(links: LinksChange(add: ["https://a.example"])),
        outcome: .updated,
        writer: writer,
        reader: LinkReader(answers: answers),
        publicSave: store.save
      )
    }

    #expect(message == expected)
    #expect(store.saves == 1)
    #expect(writer.writes.isEmpty)
  }

  @Test("Tags and links read once before the write and are both checked in the read-back")
  func tagsAndLinksTogether() async throws {
    let reader = LinkReader(answers: [
      .fields(["R1": PrivateReminderFields(flagged: false, urgent: false, tags: [], links: [])]),
      .fields(["R1": PrivateReminderFields(flagged: false, urgent: false, tags: ["home"], links: [])]),
    ])

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        PrivateFieldsChange(tags: TagsChange(add: ["home"]), links: LinksChange(add: ["https://a.example"])),
        outcome: .updated,
        writer: LinkWriter(),
        reader: reader,
        publicSave: LinkStore().save
      )
    }

    #expect(reader.reads == 2)
    #expect(
      message
        == "reminder updated (id R1); tag home added and link https://a.example added but read back as no links"
    )
  }

  @Test("A flag-only write is not read or checked for links")
  func flagOnlyIgnoresLinks() async throws {
    let reader = LinkReader(answers: [.fields(["R1": PrivateReminderFields(flagged: true, urgent: false)])])

    let reminder = try await PrivateFieldsSupport.save(
      PrivateFieldsChange(flagged: true),
      outcome: .created,
      writer: LinkWriter(),
      reader: reader,
      publicSave: LinkStore().save
    )

    #expect(reader.reads == 1)
    #expect(reminder.flagged == true)
    #expect(reminder.links == nil)
  }

  @Test("Links read through ReminderKit are attached in stored order; none leaves the key out")
  func linksRead() throws {
    let (_, runtime) = try Self.runtime(["show", "--json"])
    let reader = LinkReader(answers: [
      .fields([
        "R1": PrivateReminderFields(flagged: false, urgent: false, links: ["https://z.example", "https://a.example"]),
        "R2": PrivateReminderFields(flagged: false, urgent: false, links: []),
      ])
    ])
    let second = ReminderItem(
      id: "R2",
      title: "Other",
      notes: nil,
      isCompleted: false,
      completionDate: nil,
      priority: .none,
      dueDate: nil,
      listID: "L1",
      listName: "Inbox"
    )

    let shown = PrivateFieldsSupport.attach(
      to: [Self.reminder, second],
      scope: .everything,
      runtime: runtime,
      reader: reader,
      warn: { _ in }
    )

    #expect(shown[0].links == ["https://z.example", "https://a.example"])
    #expect(try Self.json(shown[0])?["links"] as? [String] == ["https://z.example", "https://a.example"])
    #expect(shown[1].links == nil)
    #expect(try Self.json(shown[1])?.keys.contains("links") == false)
  }
}
