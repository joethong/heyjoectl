import Commander
import Foundation
import RemindCore
import Testing

@testable import remindctl

extension TagsWriteSupportTests {
  @Test(
    "When the tags already on the reminder cannot be read, nothing is written through ReminderKit",
    arguments: [
      (
        [PrivateFieldsRead.unavailable(reason: "ReminderKit did not answer within 10 seconds")],
        "reminder updated (id R1); tag home not added: ReminderKit did not answer within 10 seconds"
      ),
      (
        [.fields([:])],
        "reminder updated (id R1); tag home not added: the tags already on the reminder could not be read"
      ),
      (
        [.fields(["R1": PrivateReminderFields(flagged: false, urgent: false)])],
        "reminder updated (id R1); tag home not added: the tags already on the reminder could not be read"
      ),
    ]
  )
  func unreadableTagsBeforeWrite(answers: [PrivateFieldsRead], expected: String) async throws {
    let store = TagStore()
    let writer = TagWriter()

    let message = await Self.message {
      _ = try await PrivateFieldsSupport.save(
        PrivateFieldsChange(tags: TagsChange(add: ["home"])),
        outcome: .updated,
        writer: writer,
        reader: TagReader(answers: answers),
        publicSave: store.save
      )
    }

    #expect(message == expected)
    #expect(store.saves == 1)
    #expect(writer.writes.isEmpty)
  }

  @Test("A flag-only write is not checked or read back for tags")
  func flagOnlyIgnoresTags() async throws {
    let writer = TagWriter()
    let reader = TagReader(nil, flagged: true)

    let reminder = try await PrivateFieldsSupport.save(
      PrivateFieldsChange(flagged: true),
      outcome: .created,
      writer: writer,
      reader: reader,
      publicSave: TagStore().save
    )

    #expect(reader.reads == 1)
    #expect(writer.checks == [PrivateFieldsChange(flagged: true)])
    #expect(writer.checks.first?.tags == nil)
    #expect(reminder.flagged == true)
  }

  @Test("The bridged change carries the names to add and remove")
  func bridgedChange() {
    let bridged = ReminderKitFieldsWriter.bridged(
      PrivateFieldsChange(flagged: true, tags: TagsChange(add: ["home", "errand"], remove: ["work"]))
    )

    #expect(bridged.flagged == true)
    #expect(bridged.tagsToAdd == ["home", "errand"])
    #expect(bridged.tagsToRemove == ["work"])
    #expect(ReminderKitFieldsWriter.bridged(PrivateFieldsChange(urgent: true)).tagsToAdd.isEmpty)
  }
}
