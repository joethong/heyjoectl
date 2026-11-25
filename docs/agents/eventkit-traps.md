# EventKit and ReminderKit traps

Read this before you write any code that saves to Reminders. Each one cost a fix round. Add a new one the day it is found, with where it was found.

## EventKit (public)
- **Setting a due date copies it into the start date.** Changing or clearing the due date later leaves that copy behind unless you move or clear it too (#33, #41).
- **A date-only due date's start copy is a timed midnight** (`startDateIsAllDay` false, no time zone), not a date-only value. Compare by year, month and day (#41).
- **Clearing the due date can shift a start date** by the time-zone offset (+8 h at UTC+8), because the start becomes floating. Save the start's components first and put them back (#41).
- **Editing only a repeat's end does nothing** on a rule a saved reminder already holds. Build a new `EKRecurrenceRule` (copy every part, including `firstDayOfTheWeek` through `setValue`) and replace the old one (#35).
- **Weekdays on a daily repeat are silently ignored.** Refuse them (#7).
- **`firstDayOfTheWeek` is read-only in the header** but has a working setter; a new rule defaults to 2 (Monday) on this Mac (#35).
- **A start date stays after a new, earlier due date.** EventKit neither moves nor refuses it (in memory, macOS 27). Refuse before the save (#51).
- **Clearing the due date leaves the Early Reminder** (ReminderKit's `dueDateDeltaAlertsData`). `--clear-due` removes it through its own private write after the EventKit save, when one is there (#51).
- **A daylight-saving gap can move a computed date to the next day.** `Calendar.date(bySettingHour:minute:second:of:matchingPolicy:)` searches forward for the next matching time, so 02:15 on a day where 02:00 to 02:30 doesn't exist gives the next day's 02:15 (Lord Howe), or the top of the next hour (New York). Build the date from the day's year, month and day plus the hour and minute and call `Calendar.date(from:)`: it takes the first of a repeated hour and moves a gap time forward, but a gap at the end of the day (Nuuk, 23:30 on 2026-03-28) pushes it to the next day, so compare the result's year, month and day with the requested day and refuse if they differ. Likewise build an all-day date from year, month and day, not by adding days to a week start: in Havana the week start is 01:00 after the midnight change, and adding days keeps 01:00. The absolute-date path (`DateFormatter`, not lenient) differs: it refuses a time in the gap and picks the second of a repeated hour (#49).
- **In-memory reminders don't behave like saved ones.** Test with in-memory objects, but expect the live check to find differences (#35, #41).

## ReminderKit (private)
- **Every check of a private write runs before the EventKit save:** the write's classes, selectors and types, and the read side's too (the read of current values and the read-back after the write). A missing method must give "…; nothing was changed", never a created reminder and exit 1 (#43, #47).
- **An implied private change on a 0.3.8 command must be best-effort,** so it never changes that command's exit code. `edit --clear-due` exited 0 in 0.3.8; its implied Early Reminder removal reports any failure in one stderr note and still exits 0, and the printed reminder shows the read-back value or no `earlyReminder` key. It runs after the EventKit save, so the rule above about checks before the save does not apply to it. An explicit `--early` stays strict (#51).
- **"Remove all" calls may remove nothing.** `removeAllFetchedDueDateDeltaAlerts` removed no existing Early Reminder, because they aren't "fetched" into the change item. Remove by id (`removeDueDateDeltaAlertsWithIdentifiers:`, ids from the stored `dueDateDeltaAlertsData` JSON) or one object at a time (`removeHashtag:`). Always prove it with a read-back of the whole expected value (#43, #47).
- **The bridge's read fetches the whole store.** `RPReadReminderFields` checks only the reminders in `ids`, and skips any reminder with no `objectID.uuid` (#51; before that, one malformed reminder anywhere failed every write). Ask for the one id you write. A read with empty `ids`, as `doctor` does, checks no reminder's fields, so `doctor` also runs the read-side method check (#37, #51).
- **Read back the whole expected value,** not only the part you changed (all tags, exactly one Early Reminder: more than one stored alert is unreadable, not the first) (#47, #51).
- **A huge or unexpected stored number must be skipped or refused, not crash** (`0.subtractingReportingOverflow`, a one-year cap on `--early`) (#12, #43).
- **The join key:** ReminderKit's `objectID.uuid.UUIDString` equals EventKit's `calendarItemIdentifier` (436 of 436).
- **Early Reminder counts are stored negative** for "before" (unit 0 min, 1 h, 2 d, 3 w, 4 mo).
- **Tags are added with type 1** (`addHashtagWithType:1 name:`).
- **Links are URL attachments.** Read them from `storage.attachments`, keeping only objects of class `REMURLAttachment`; don't pick them by "answers `url`". `REMReminderStorage` has no `urlAttachments` on macOS 27 (only the change item and `REMReminderAttachmentContext` do). Match links with the scheme and host lowercased and the rest as written (#60). Write through `attachmentContext`: `addURLAttachmentWithURL:`, and remove one at a time with `removeAttachment:` on the objects from `urlAttachments` and the stored list, not `removeURLAttachments` or `removeAllAttachments` (#55, untested live).
- **Urgent and Early Reminder need no due date** (live, macOS 27).

## Where to look in Apple's database (read-only, test reminders only)
`~/Library/Group Containers/group.com.apple.reminders/Container_v1/Stores/Data-*.sqlite`, table `ZREMCDREMINDER` (match `ZCKIDENTIFIER` or `ZDACALENDARITEMUNIQUEIDENTIFIER` to the id): `ZFLAGGED`, `ZISURGENTSTATEENABLEDFORCURRENTUSER`, `ZDUEDATEDELTAALERTSDATA` (JSON). Tags: `ZREMCDOBJECT` rows with `Z_ENT` = REMCDHashtag (32 here), name in `ZNAME1`, linked to the reminder's `Z_PK` through one of the `ZREMINDER*` columns. Links (the field Reminders.app shows, #55): `ZREMCDOBJECT` rows with `Z_ENT` = REMCDURLAttachment (a subentity of REMCDAttachment), with `url` and `metadata` attributes, linked the same way.
