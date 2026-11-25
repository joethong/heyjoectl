---
title: Commands
description: "Common remindctl commands and options."
---

# Commands

## Show reminders

Read reminders with `show <view>`. Add `--list` or `--list-id` to pick a list, `--tag` to filter by tag, and `--json` for output a program can read. The view name alone, such as `remindctl today`, is a shortcut for `show today`. `open` shows every incomplete reminder, including those with no due date. Use `list` for the lists themselves (see [Lists](#lists)).

```bash
remindctl today
remindctl tomorrow
remindctl week
remindctl overdue
remindctl upcoming
remindctl open
remindctl completed
remindctl all
remindctl 2026-01-03
```

`week` and `show week` include incomplete reminders due within the current calendar week, including its start but excluding the opening midnight of the next week.

Limit a view to one list:

```bash
remindctl show overdue --list Work
remindctl show open --list Work --json
remindctl show overdue --list-id 7A12
```

Limit a view to reminders with a tag. Repeat `--tag` to need every tag given. The match ignores case and a leading `#`, and the name follows the same rules as `--tag` on `add`. `search` takes `--tag` too.

```bash
remindctl show all --tag errand --tag home
remindctl search "milk" --tag errand
```

`--tag` reads tags through ReminderKit. With `--no-private` it exits 1 with nothing on stdout: `--tag filters on tags read through ReminderKit; remove --no-private`. When ReminderKit does not load, it exits 1 the same way and names the reason. No match prints `[]` in JSON.

## Create reminders

```bash
remindctl add "Review notes"
remindctl add "Call Sam" --list Work --due tomorrow
remindctl add "Call Sam" --list-id 7A12 --due tomorrow
remindctl add "Take vitamins" --due tomorrow --repeat daily
remindctl add "Check mailbox" --location "1 Apple Park Way, Cupertino, CA"
remindctl add "Plan trip" --start 2026-11-01 --due 2026-11-21
remindctl add "Call Sam" --due "2026-11-21 09:00" --alarm-before 15m
remindctl add "Gym" --due tomorrow --repeat "weekly on mon,fri" --repeat-count 8
remindctl add "Renew passport" --due "2026-11-21 09:00" --flag --urgent --early 1w
remindctl add "Buy nails" --tag errand --tag home
```

Useful `add` options:

- `--list <name>` chooses the target list.
- `--list-id <id-prefix>` chooses the target list exactly.
- `--title <text>` gives the title as an option instead of an argument. Use one or the other, not both.
- `--due <date>` sets a due date. See [Dates](#dates).
- `--start <date>` sets a start date. `--clear-start` leaves it empty instead. EventKit otherwise copies the due date into the start date. Use one or the other, not both.
- `--alarm <date>` sets a notification alarm at a fixed time. A timed `--due` with no `--alarm` also adds an alarm at the due time. A date-only `--due` adds none.
- `--alarm-before <duration>` sets a notification a set time before the due date: a whole number with `m`, `h`, `d` or `w`, up to 366 days (`15m`, `1h`, `1d`, `1w`). It needs `--due`.
- `--notes <text>` adds notes.
- `--repeat <rule>` sets recurrence. See [Repeat rules](#repeat-rules).
- `--repeat-until <date>` and `--repeat-count <n>` end the repeat. They need `--repeat`, and you can use only one of them.
- `--priority <none|low|medium|high>` sets priority.
- `--url <url>` stores the EventKit URL and mirrors it into notes as `remindctl URL (managed): ...` so Reminders.app shows the link.
- `--location <address>` creates an arriving geofence trigger.
- `--leaving` changes a location trigger to leaving.
- `--radius <meters>` adjusts the geofence radius.
- `--flag` flags the reminder. `--unflag` is accepted on `add` and changes nothing worth having on a new reminder.
- `--urgent` turns on the native Urgent toggle. `--not-urgent` turns it off.
- `--early <duration>` sets the Early Reminder. See [Flag, Urgent, Early Reminder and tags](#flag-urgent-early-reminder-and-tags).
- `--tag <name>` adds a tag. Repeat it for more than one.
- `--untag <name>` is accepted on `add`, and a new reminder has no tags to remove.
- `--link <url>` adds the link Reminders.app shows. Repeat it for more. See [Links](#links).

Short names: `-l` for `--list`, `-d` for `--due`, `-a` for `--alarm`, `-n` for `--notes`, `-r` for `--repeat`, `-p` for `--priority`.

`--flag`, `--urgent`, `--early`, `--tag` and `--link` write through Apple's private ReminderKit framework. If the command cannot write them, it exits 1 and says what was saved. See [Flag, Urgent, Early Reminder and tags](#flag-urgent-early-reminder-and-tags).

## Dates

`--due`, `--start`, `--alarm`, `--repeat-until` and the `show <date>` filter all use one parser. It accepts the forms in this table, with the variations listed after it. Nothing else parses:

| Form | Example | Kind |
| --- | --- | --- |
| `today`, `tomorrow`, `yesterday` | `tomorrow` | date only |
| `now` | `now` | timed (this moment) |
| `monday`…`sunday` or `mon`…`sun`, in any case; `next` in front is the same | `friday`, `next fri` | date only. The next one after today; today's own weekday means a week from today |
| `this` and a weekday | `this friday` | date only. This week's day. Today counts. A day that has passed fails |
| `today`, `tomorrow` or a weekday (with `next` or `this`), then a time | `"friday 5:30pm"`, `"tomorrow 9am"` | timed, local time |
| `YYYY-MM-DD` | `2026-11-21` | date only |
| `YYYY-MM-DD HH:mm` or `HH:mm:ss` | `"2026-11-21 09:00"` | timed, local time |
| `YYYY-MM-DDTHH:mm`, with optional `:ss` and fraction | `2026-11-21T09:00` | timed, local time |
| ISO 8601 with `Z` or an offset | `2026-11-21T09:00:00+08:00` | timed, exact instant |
| `MM/dd/yyyy`, with optional `HH:mm` | `"11/21/2026 09:00"` | date only, or timed |
| `dd-MM-yy` or `dd-MM-yyyy` | `21-11-2026` | date only |

A time after a day name is `H:mm` or `HH:mm` (24 hours), or `h`, `h:mm` with `am` or `pm` (`9am`, `5:30pm`, `12am` is midnight). A bare hour needs `am` or `pm`, so `"friday 9"` fails, and so does `9:5`. Cases are ignored. The other forms take a 24-hour time only. A time still needs a date or a day name in front of it.

For `today`, `tomorrow` and a weekday with a time, a time that does not exist on the day (the hour skipped when the clocks go forward) moves forward past the gap, within the same day: `"sunday 2:30"` on the spring-forward Sunday in New York is 3:30. If it can't stay on that day (the clocks jump at 23:00 and there is no 23:30), the date is refused with `Invalid date: "saturday 23:30" (that time doesn't exist on 2026-03-28 because the clocks change; pick another time).` A time that happens twice (the hour repeated when the clocks go back) is the first one. An absolute date such as `"2026-03-08 02:30"` keeps its older rules: a time in the gap fails with `Invalid date`, and a repeated time is the second one.

`this <weekday>` uses the calendar's week, which starts on the Mac's first day of the week (Monday on the Mac this was written on). Where weeks start on Sunday, `this sunday` on a Thursday has already passed and fails. `next <weekday>` and a bare weekday do not depend on the week start.

`next week`, `in 3 days` and `yesterday 9:00` fail with `Invalid date: "…".` and exit 1. Work out the date and pass it as `YYYY-MM-DD`.

Impossible dates, invalid offsets, and trailing text fail instead of being normalized to another date. Unpadded month/day/time fields, extra spaces before a time, and year-first `/` or `.` separators remain accepted. Legacy slash dates use `MM/dd/yyyy`; day-first hyphen dates use `dd-MM-yy` or `dd-MM-yyyy`.

A date-only value is an all-day reminder: `dueDateIsAllDay` is `true` in JSON. A timed value sets a time of day.

## Repeat rules

`--repeat` takes one of these forms. Words are not case-sensitive.

- `daily`, `weekly`, `biweekly`, `monthly`, `yearly` (or `annually`)
- `every N days`, `every N weeks`, `every N months`, `every N years` (singular also works)
- `weekly on mon,fri` repeats on those weekdays. Use `mon tue wed thu fri sat sun` or the full names.
- `monthly on 1,15` repeats on those days of the month. `-1` is the last day. Days run from 1 to 31 or -1 to -31.
- `monthly on last fri` and `monthly on 2nd tue` repeat on that weekday of the month. Positions are `1st 2nd 3rd 4th 5th last`.
- `yearly on` takes the same day lists. `yearly on last fri` means the last Friday of the year, not of each month.

A daily repeat refuses weekdays, because EventKit ignores them. Other bad values fail with the list of valid forms.

```bash
remindctl add "Pay rent" --due 2026-12-25 --repeat "monthly on last fri"
remindctl add "Water plants" --due tomorrow --repeat weekly --repeat-count 6
remindctl add "Summer course" --due 2026-06-01 --repeat weekly --repeat-until 2026-08-31
```

`--repeat-until` with a date-only value includes that whole day. `--repeat-count` takes a whole number of 1 or more. `--no-repeat` (on `edit`) removes the repeat.

## Flag, Urgent, Early Reminder and tags

EventKit cannot read or write these. `remindjoectl` reaches them through Apple's private ReminderKit framework.

- `--flag` and `--unflag` set the flag.
- `--urgent` and `--not-urgent` set the native **Urgent** toggle. This replaces the old advice to set Urgent in Reminders.app. Urgent works with no due date.
- `--early <duration>` sets the Early Reminder: a whole number with `m` (or `min`), `h`, `d`, `w` or `mo`, up to a year (`525600m`, `8760h`, `366d`, `52w`, `12mo`). `--early none` removes it. A new `--early` replaces any Early Reminder already there, so a reminder never ends up with two. It also works with no due date.
- `--tag <name>` adds a tag and `--untag <name>` removes one. Name the tag without `#` (a leading `#` is accepted). No spaces. Repeat the option for more tags. A tag is never added twice (the match ignores case), and removing a tag the reminder does not have is not an error. Using `--tag X` and `--untag X` together fails.
- `--link <url>` and `--unlink <url>`: see [Links](#links).

```bash
remindctl add "Pay invoice" --flag
remindctl edit 4A83 --not-urgent
remindctl edit 4A83 --early 1d
remindctl edit 4A83 --early none
remindctl edit 4A83 --tag errand --untag home
```

Giving both `--flag` and `--unflag`, or both `--urgent` and `--not-urgent`, fails before anything changes.

If a private write fails, the command exits 1, prints nothing to stdout, and the message says what was saved. For example: `reminder created (id …); flag not set: …`. When it cannot even start the private write, the message ends `nothing was changed` and no reminder is created. **Do not retry an `add` blindly.** The reminder may already exist. Check with `info <id> --json` or `search`.

`--no-private` skips ReminderKit. On a read, the private keys are left out of the JSON. A write that uses `--flag`, `--unflag`, `--urgent`, `--not-urgent`, `--early`, `--tag`, `--untag`, `--link` or `--unlink` fails: `--flag writes through ReminderKit; remove --no-private`. A write that uses only public fields works as usual. Run `doctor --json` and read `privateFields.available` to see whether the private fields work on this Mac.

## Links

Reminders.app shows a link field under the notes. `remindjoectl` reads and writes it through ReminderKit, where each link is a URL attachment.

- `--link <url>` adds a link and `--unlink <url>` removes one, on `add` and `edit`. Repeat either for more links.
- The `--link` URL must be absolute and start with `http`, `https` or `mailto`. Anything else fails before anything changes. `--unlink` takes any link the reminder has, as `info` prints it, so it also removes a `tel:` or app link that Reminders.app stored.
- A link already there is not added again. Removing a link the reminder does not have is not an error. Links match with the scheme and host in any case, and the rest as written: `HTTPS://Example.com` matches `https://example.com`, but `https://example.com/A` and `https://example.com/a` are different links, and so are `https://example.com` and `https://example.com/`. Using `--link X` and `--unlink X` together fails.
- The JSON key `links` lists the URLs in stored order. It is left out when there are none, under `--no-private`, and when ReminderKit is unavailable. Plain output marks a reminder that has links with `[link]`; `info` prints each as `Link: …`.
- `--url` and the `url` key are a different field: EventKit's URL, which Reminders.app does not show. They work as in 0.3.8.

```bash
remindctl add "Read the brief" --link https://example.com/brief
remindctl edit 4A83 --link mailto:joe@example.com --unlink https://example.com/brief
```

A failed link write follows the same rules as the other private fields: the message says what was saved, and ends `nothing was changed` when the write could not start.

## Edit reminders

```bash
remindctl edit 1 --title "New title"
remindctl edit 4A83 --due "2026-01-04 09:00"
remindctl edit 4A83 --clear-due
remindctl edit 4A83 --list Office
remindctl edit 4A83 --list-id 7A12
remindctl edit 4A83 --no-repeat
remindctl edit 4A83 --alarm-before 15m
remindctl edit 4A83 --alarm-before none
remindctl edit 4A83 --start 2026-11-01
remindctl edit 4A83 --clear-start
remindctl edit 4A83 --repeat-until 2026-12-31
remindctl edit 4A83 --flag --urgent --early 2d
remindctl edit 4A83 --tag errand --untag home
remindctl edit 4A83 --link https://example.com --unlink https://example.com/old
```

Useful `edit` options, beyond the ones `add` shares (`--title`, `--notes`, `--priority`, `--url`, `--repeat`, `--list`):

- `--clear-due`, `--clear-start`, `--clear-alarm`, `--clear-url` and `--no-repeat` remove that field. Each conflicts with the option that sets the same field.
- `--alarm <date>` replaces the fixed-time alarms. `--clear-alarm` removes them. Neither touches before-due or location alarms.
- `--alarm-before <duration>` replaces only the before-due alarms. `--alarm-before none` removes them. It needs a due date, either the reminder's own or a new `--due` in the same command.
- `--repeat-until` and `--repeat-count` with no `--repeat` change only the end of the repeat the reminder already has. It fails if the reminder does not repeat. `--no-repeat` cannot be combined with them.
- `--complete` and `--incomplete` change the completed state.
- `--flag`, `--unflag`, `--urgent`, `--not-urgent`, `--early <duration|none>`, `--tag` and `--untag` work as described in [Flag, Urgent, Early Reminder and tags](#flag-urgent-early-reminder-and-tags). `--link` and `--unlink` work as described in [Links](#links). If an `edit` has only these options and the private write fails, the message starts `reminder not changed`.
- `edit` with no option at all fails with `No changes specified`.

Moving a reminder with `--list` or `--list-id` can fail when the source or destination list is shared. If EventKit rejects the move with `com.apple.reminderkit error -3002`, move the reminder in Reminders.app, then retry any other edits. The command does not fall back to copying and deleting the reminder, since public EventKit cannot preserve all Reminders.app metadata.

Commands that target reminders accept indexes from the current default listing or ID prefixes.
An in-range numeric value always selects that index. An out-of-range numeric value falls back to ID-prefix matching and returns an error when no reminder ID matches.
`complete` and `delete` process each reminder once, even when repeated indexes, IDs, or prefixes identify the same reminder. Previews and delete confirmation counts use these unique targets in first-input order; every input must still be valid and unambiguous.
Reminders sort by due date, then title, then stable ID so equal dates and titles do not make numeric targets depend on EventKit's fetch order. Use IDs when reminders may be added, removed, or edited between commands.

If `add`, `edit`, or `complete` reports `Reminder is missing a calendar`, EventKit saved the reminder but returned it without its list. Check Reminders.app before retrying; this error does not roll back the saved change.

A fixed-time alarm at exactly the old due time belongs to the due date. A new timed `--due` moves it to the new due time. A date-only `--due` or `--clear-due` removes it. `--alarm` or `--clear-alarm` in the same command wins over the move. Every other alarm stays, and a date-only old due date moves nothing. `--clear-due` also removes the before-due alarms, which mean nothing without a due date.
`--clear-due` also removes the Early Reminder through ReminderKit, since it means nothing without a due date. That removal is best-effort: if it can't run or fails, the due date is still cleared, the command still exits 0, and one stderr note says the Early Reminder was left ("remindctl: due date cleared, but the Early Reminder was left: <reason>"). Give `--early none` with `--clear-due` to make the removal strict (exit 1 if it fails).
EventKit copies a new due date into the start date. `--clear-due` clears a start date that was only that copy, and `--due` moves such a copy to the new due date. A start date you set yourself with `--start` stays where it is.
Explicit alarm edits preserve relative and location-based alarms while replacing or clearing absolute alarms.
`edit --alarm` schedules a notification. It does not set Urgent. Use `--urgent` for that.

## Lists

```bash
remindctl list
remindctl list Projects --create
remindctl list Work --rename Office
remindctl list OldList --delete --force
remindctl list --list-id 7A12 --rename Archive
```

`list` with no name is the list of lists. Create, rename and delete accept one list name.
`list <name...>` is the remindctl form of a list read: it prints the reminders in one or more lists and also prints completed ones. For the open reminders in a list, use `show open --list <name>`.
Choose only one of `--create`, `--delete`, or `--rename`, and provide its target; conflicting or missing mutation targets fail before accessing Reminders.
`list <name> --create` creates a missing list or reuses a unique matching list. Repeating it preserves the list and its reminders; `--json` reports the current incomplete and overdue counts. An ambiguous name fails instead of creating another list.
List names resolve by exact match, case-insensitive match, then a normalized match that ignores emoji and punctuation.
If a name is ambiguous, use `--list-id`.

## Search and inspect

```bash
remindctl search "invoice" --list Work
remindctl search "project" --completed --json
remindctl search "milk" --tag errand --tag home
remindctl info 1
remindctl info 4A83 --json
```

## Export, links, and app handoff

```bash
remindctl export --json
remindctl export --list Work --export-format csv
remindctl link 1
remindctl link --list-id 7A12
remindctl open 1
remindctl open --list Work
remindctl open --list Work --app
remindctl completion zsh
```

`open --list Work` keeps the historical open-reminders filter. Add `--app` to open that list in Reminders.app.

CSV export quotes multiline fields, including Windows-style CRLF text, and neutralizes formula prefixes after leading whitespace or newlines. Managed URL-note replacement and `--clear-url` also recognize CRLF lines while preserving authored text and its newline style.

## Diagnostics

```bash
remindctl status
remindctl doctor --for-agent
remindctl doctor --json
```

`doctor --json` has a `privateFields` object: `available` (true or false), `reason` (null, or why ReminderKit is not usable) and `macOSVersion`. Read it to learn whether the private fields work before you rely on them. `--no-private` makes it report `available: false` with the reason `turned off by --no-private`.

`privateFields.writes` is `{available, reason}` for the write side: it checks every class and method any private write needs (flag, Urgent, Early Reminder, tags, links), whatever a given command uses. It also fails when the read side is missing a method, because every write checks that first. When it is `false`, `reason` names what is missing, and `privateFields.available` can still be `true` when only a write method is missing. `--no-private` and a ReminderKit that does not load give the same reasons as for reads. Plain output has one more line: `Private writes (ReminderKit): available`, or `unavailable (reason)`.

When ReminderKit does not load, a read still works. The private keys are left out and one line goes to stderr: ``remindctl: private fields unavailable: ReminderKit did not load; run `remindctl doctor` for details``. A line `remindctl: N Early Reminder(s) could not be read` also goes to stderr when a stored Early Reminder cannot be parsed. Read `--json` from stdout only.

## Output

```bash
remindctl all --json
remindctl list --json
remindctl today --plain
remindctl today --format table
remindctl status --json
```

Global output flags:

- `--json` emits machine-readable JSON.
- `--plain` emits stable tab-separated lines.
- `--format table` emits tabular output.
- `--quiet` emits minimal output.
- `--no-color` disables colored output.
- `--no-input` disables interactive prompts.
- `--no-private` skips ReminderKit. See [Flag, Urgent, Early Reminder and tags](#flag-urgent-early-reminder-and-tags).
- `--format <standard|table|plain|json|quiet>` picks the format by name.

Use `--` before positional text that starts with a hyphen, including literal help or version flags:

```bash
remindctl add -- "--help"
```

Help and version flags after `--` are passed to the command as text.

## JSON fields

`--json` prints one reminder object, or an array of them. Keys are sorted. Dates are ISO 8601 in UTC. A key with no value is left out, not printed as `null`.

Keys from remindctl 0.3.8 are unchanged: `id`, `title`, `notes`, `url`, `isCompleted`, `completionDate`, `creationDate`, `lastModifiedDate`, `priority` (`none`, `low`, `medium`, `high`), `dueDate`, `dueDateIsAllDay`, `alarmDate`, `recurrenceRule` (with `frequency` and `interval`), `locationTrigger`, `listID` and `listName`.

The fork adds these keys. Each is new; nothing was renamed or removed.

| Key | Meaning |
| --- | --- |
| `startDate`, `startDateIsAllDay` | The start date. `startDateIsAllDay` appears with it. |
| `timeZone` | The reminder's time zone name, such as `Asia/Hong_Kong`. |
| `externalID` | The id that stays the same across devices. Left out when empty. |
| `alarms` | Every alarm, in a list. Left out when there are none. See below. |
| `recurrenceRule.daysOfWeek` | List of `{day, week}`. `day` is `mon` to `sun`. `week` is 1 to 5, or -1 for last; it is left out for "every week". |
| `recurrenceRule.daysOfMonth` | List of day numbers. -1 is the last day. |
| `recurrenceRule.monthsOfYear` | List of month numbers, 1 to 12. |
| `recurrenceRule.setPositions` | List of positions, such as -1 for last. |
| `recurrenceRule.end` | `{"date": "…"}` or `{"count": n}`. Left out when the repeat never ends. |
| `flagged` | `true` or `false`. ReminderKit. |
| `urgent` | `true` or `false`. ReminderKit. |
| `earlyReminder` | `{"count": 1, "unit": "days"}`. `unit` is `minutes`, `hours`, `days`, `weeks` or `months`. Left out when there is none. Only the first Early Reminder is shown. |
| `tags` | List of tag names without `#`, sorted. `[]` when there are none. |
| `parentID` | The parent reminder's id, when this is a sub-task. |
| `assignee` | `{id, name, status}` for the newest assignment. `name` may be left out. |
| `links` | List of the URLs of the links Reminders.app shows, in stored order. Left out when there are none. Not the same as `url`. |

`alarms` entries have a `kind`:

- `{"kind": "date", "date": "…"}` is a fixed-time alarm.
- `{"kind": "beforeDue", "seconds": 900}` fires that many seconds before the due date. `afterDue` fires after it.
- `{"kind": "place", "title": "…", "radius": 100, "proximity": "arriving"}` is a place alarm. `latitude` and `longitude` appear when known. `proximity` is `arriving` or `leaving`.

`flagged`, `urgent`, `earlyReminder`, `tags`, `parentID`, `assignee` and `links` come from ReminderKit. They appear in `show`, `list <name>`, `search`, `info`, `open` and `export --json` output when the format is `json` or `standard`. With `--no-private`, or when ReminderKit does not load, they are all left out. `add`, `edit` and `complete` print them too, read back from ReminderKit after the save.

**Reading an all-day due date.** When `dueDateIsAllDay` is `true`, the reminder is due on a local calendar day, with no time. `dueDate` is midnight of that day in the local time zone, written in UTC. In Hong Kong, `2026-11-21` shows as `2026-11-20T16:00:00Z`. Read the day in the local time zone. Do not take the date part of the UTC string. `startDateIsAllDay` works the same way for `startDate`.

Other JSON shapes: `list --json` gives `{id, title, reminderCount, overdueCount}` per list. `delete --json` gives `{"deleted": n}`. `status --json` gives `{status, authorized}`. `doctor --json` gives `authorization`, `executable`, `shell`, `richRead`, `privateFields` and `agentNotes`.
