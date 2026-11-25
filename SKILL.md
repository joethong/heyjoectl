---
name: apple-reminders
description: "Use remindjoectl, an enhanced fork of remindctl, to read and change Apple Reminders on macOS, including flags, Urgent, Early Reminders, tags, links, full repeat rules, every kind of alarm, weekday dates and --tag filtering."
homepage: https://github.com/joethong/heyjoectl
---

# Apple Reminders

Use `remindjoectl` to read and change the reminders in Reminders.app. `remindctl` runs the fork only where it has been linked to `remindjoectl` (see Install). Where it has not, `remindctl` may be upstream's tool, which rejects the fork's options, so call `remindjoectl`. It does everything remindctl 0.3.8 does, with the same commands, flags, JSON keys and exit codes, and it adds the flag, Urgent, the Early Reminder, tags, links, full repeat rules and every kind of alarm. Changes sync through iCloud like any other edit.

Full option lists are in `docs/commands.md` in the repo.

## Use this skill when

- The user wants to read, add, change, complete or delete reminders from the terminal or a script.
- The user wants a flag, Urgent, an Early Reminder, tags, links, a repeat on set weekdays or a day of the month, or more than one alarm on a reminder.
- The user wants reminders that show up on an iPhone, iPad or Mac in Reminders.app.

## Do not use this skill when

- The user wants a calendar event, a cron job or a timed alert from a chatbot instead of a reminder.
- The user needs Reminders sections, Smart Lists or file and image attachments. Neither EventKit nor this fork supports them.
- The user needs to write sub-tasks or assignees. The fork reads them (`parentID`, `assignee`) and cannot write them.

## Install

The fork has no Homebrew formula yet, so build it from source. This needs macOS 14 or later and Swift 6.2 or later.

```bash
pnpm install
pnpm build
install -m 755 bin/remindctl /usr/local/bin/remindjoectl
ln -sf remindjoectl /usr/local/bin/remindctl
```

The last line is optional. With it, scripts that call `remindctl` use the fork. Check the install with `remindjoectl --version`. The terminal app that runs `remindjoectl` needs full Reminders access (see Permissions).

## Rules

1. Add `--json` and read stdout only. A warning can go to stderr, such as `remindctl: private fields unavailable: …`. Never mix stderr into the JSON.
2. Exit 0 means success. Exit 1 means failure, with the reason on stderr and nothing on stdout.
3. After exit 1 on a write, do not retry blindly. A private write (`--flag`, `--urgent`, `--early`, `--tag`, `--link`) runs after the reminder is saved. If it fails, the message says what was saved, for example `reminder created (id 4A83…); flag not set: …`. The reminder exists. If the message ends `nothing was changed`, nothing was saved.
4. Before you retry an `add`, look first: `remindjoectl search "Call Sam" --json`, or `remindjoectl info <id> --json` when the message gave an id.
5. Target a reminder by its full `id` from JSON (or a prefix of 4 or more characters). Do not use the numbers `1`, `2`, `3`. A number picks from today's view, and that view changes as reminders are added or completed.
6. `--no-private` skips ReminderKit. Reads then leave out `flagged`, `urgent`, `earlyReminder`, `tags`, `parentID`, `assignee` and `links`. Writes with `--flag`, `--urgent`, `--early`, `--tag`, `--untag`, `--link` or `--unlink` fail.
7. Check that the private fields work: `remindjoectl doctor --json`. Read `privateFields.available` for reads and `privateFields.writes.available` for writes. If one is `false`, its `reason` says why. Plain reads and writes still work.
8. Pass long values in quotes: titles, dates with a time, and `--repeat` rules.

## Permissions

Run `remindjoectl status --json` first when access matters. It never prompts. `remindjoectl authorize` asks macOS for access when the state is `notDetermined`. If access is denied, send the user to System Settings > Privacy & Security > Reminders. Over SSH, grant access on the Mac that runs `remindjoectl`. macOS grants access per program, so a new build may need it granted again.

## Dates

`--due`, `--start`, `--alarm` and `--repeat-until` accept only these:

- `today`, `tomorrow`, `yesterday` (all day), and `now`
- A weekday, in any case: `friday` or `fri` (all day). It means the next one after today, and today's own weekday means a week from today. `next friday` is the same. `this friday` is this week's Friday: today counts, but a day that has passed fails (the week starts on the Mac's first day of the week).
- A time after `today`, `tomorrow` or any weekday: `"friday 9:00"`, `"friday 17:30"`, `"friday 9am"`, `"friday 5:30pm"`, `"tomorrow 9am"`, `"today 9:00"`. Without a time the result is all day. A bare hour needs `am` or `pm` (`9am`, not `9`). A time skipped by a clock change moves forward past the gap, on the same day, and a repeated time is the first one. If moving forward would leave that day (a gap that ends after midnight), the date is refused with `Invalid date`: pick another time.
- `2026-11-21` (all day)
- `"2026-11-21 09:00"` or `2026-11-21T09:00` (local time, 24 hours, optional `:ss` and fraction)
- `2026-11-21T09:00:00+08:00` or `…Z` (exact instant)
- `11/21/2026` or `"11/21/2026 09:00"` (month first)
- `21-11-2026` or `21-11-26` (day first)
- Variations that also parse: `/` or `.` in place of `-` in a year-first date (`2026/11/21`, `2026.11.21`), a one-digit month, day or hour (`2026-1-5`, `"2026-11-21 9:00"`), and extra spaces before the time.

These are not accepted: `next week`, `in 3 days`, `"yesterday 9:00"`, a bare hour such as `"friday 9"`, and `9:5` after a weekday. They fail with `Invalid date: "…".` and exit 1. Work out the calendar date yourself and pass `YYYY-MM-DD`.

If the user gives only a calendar date, pass a date-only value. Do not invent a time.

## Read reminders

Read reminders with `show <view>`. Add `--list` or `--list-id` to pick one list, `--tag` to filter by tag, and `--json` for output a program can read.

```bash
remindjoectl show today --json
remindjoectl show open --list Work --json
remindjoectl show all --tag errand --tag home --json
remindjoectl search "Call Sam" --json
```

The views are `today`, `tomorrow`, `week`, `overdue`, `upcoming`, `open`, `completed` and `all`, or a date such as `2026-11-21`. With no view, `show` gives `today`. `today` returns every incomplete reminder due today and every overdue one. For overdue only, use `show overdue`. `open` returns every incomplete reminder, including those with no due date. Repeat `--tag` to need every tag. `search` takes `--list`, `--tag` and `--completed` too. `--tag` fails with exit 1 under `--no-private` or when ReminderKit does not load, so a `[]` always means no match. The output is a JSON array, and `[]` is a valid empty answer.

## Add

Every `add` prints the new reminder as JSON, including its `id`.

```bash
remindjoectl add "Call Sam" --list Work --due "2026-11-21 09:00" --json
remindjoectl add "Take vitamins" --due 2026-11-21 --repeat daily --json
remindjoectl add "Gym" --due 2026-11-21 --repeat "weekly on mon,fri" --repeat-count 8 --json
remindjoectl add "Call Sam" --due "2026-11-21 09:00" --alarm "2026-11-21 08:55" --json
remindjoectl add "Call Sam" --due "2026-11-21 09:00" --alarm-before 15m --json
remindjoectl add "Pay invoice" --flag --json
remindjoectl add "Renew passport" --urgent --json
remindjoectl add "Renew passport" --due "2026-11-21 09:00" --early 1w --json
remindjoectl add "Buy nails" --tag errand --tag home --json
remindjoectl add "Read the brief" --link https://example.com/brief --json
```

- The title is a positional argument, or `--title`, not both.
- Without `--list`, the reminder goes to the default list of Reminders.app. Do not assume its name. If the Mac has no default list, give `--list`.
- `--repeat` takes `daily`, `weekly`, `biweekly`, `monthly`, `yearly`, `every N days|weeks|months|years`, or a form with `on`: `weekly on mon,fri`, `monthly on 1,15`, `monthly on last fri`. `yearly on last fri` is the last Friday of the year. End it with `--repeat-until 2026-12-31` or `--repeat-count 6`.
- A timed `--due` also adds an alarm at the due time. A date-only `--due` adds none.
- `--alarm-before` needs `--due`. Units are `m`, `h`, `d`, `w`, up to 366 days.
- `--early` takes a whole number with `m`, `h`, `d`, `w` or `mo`, up to a year. Urgent and Early Reminder work with no due date.
- Tags have no spaces. Give them without `#`; a leading `#` is dropped (`--tag "#home"` is `home`). A tag already there is not added twice.
- `--link` adds the link Reminders.app shows. It takes an absolute `http`, `https` or `mailto` URL; repeat it for more. `--url` is a different field (EventKit's URL, mirrored into the notes) and stays as it was.
- `--notes`, `--priority <none|low|medium|high>` and `--start` work as their names say. `--location <address>` makes an arriving geofence trigger, with `--leaving` and `--radius <meters>` as modifiers that need `--location`.

## Change or clear

Each command prints the updated reminder. Set `ID` to the reminder's `id`.

```bash
remindjoectl edit "$ID" --due 2026-11-22 --json
remindjoectl edit "$ID" --clear-due --json
remindjoectl edit "$ID" --repeat weekly --json
remindjoectl edit "$ID" --no-repeat --json
remindjoectl edit "$ID" --alarm "2026-11-21 08:45" --json
remindjoectl edit "$ID" --alarm-before none --json
remindjoectl edit "$ID" --clear-alarm --json
remindjoectl edit "$ID" --flag --urgent --early 2d --json
remindjoectl edit "$ID" --unflag --not-urgent --early none --json
remindjoectl edit "$ID" --tag errand --untag home --json
remindjoectl edit "$ID" --link https://example.com/new --unlink https://example.com/old --json
remindjoectl edit "$ID" --title "New title" --notes "Call before noon" --priority high --json
remindjoectl edit "$ID" --list Office --json
```

- `--list` or `--list-id` on `edit` moves the reminder to another list. Do not delete and recreate it to move it.
- `--clear-due` also removes before-due alarms, a start date that was only a copy of the due date, and the Early Reminder. If the Early Reminder can't be removed (ReminderKit unavailable, `--no-private`, or a failed write), the due date is still cleared, the exit is still 0, and one stderr note says the Early Reminder was left. Read the JSON's `earlyReminder` to see what's there.
- A fixed-time alarm at exactly the old due time follows the due date: a new timed `--due` moves it, a date-only `--due` or `--clear-due` removes it. `--alarm` or `--clear-alarm` in the same edit wins. Other alarms stay.
- `edit --due` to a date before a start date you set yourself is refused (exit 1, nothing changed): give an earlier `--start` too, or `--clear-start`.
- `--alarm` and `--clear-alarm` change fixed-time alarms only. `--alarm-before` changes before-due alarms only.
- `--early` replaces any Early Reminder already there. `--early none` removes it.
- `--untag` of a tag the reminder lacks is fine. So is `--unlink` of a link it lacks, and `--link` of a link it has adds nothing.
- A repeat needs a due date: `edit --repeat` on a reminder with none fails with `A repeating reminder must have a due date.` Add `--due` in the same command.
- `--repeat-until` or `--repeat-count` without `--repeat` changes only the end of the current repeat.
- `--complete` and `--incomplete` change the completed state. `--clear-start`, `--clear-url` and `--no-repeat` remove that field.
- Do not combine `--flag` with `--unflag`, `--urgent` with `--not-urgent`, `--tag X` with `--untag X`, or `--link X` with `--unlink X`. Each fails with exit 1 and changes nothing. The same goes for a `--clear-` option with the option that sets the same field.
- `edit` with no option fails with `No changes specified`.

## Complete and delete

```bash
remindjoectl complete "$ID" --json
remindjoectl delete "$ID" --force --json
```

`complete` prints an array of the completed reminders. `delete` prints `{"deleted": 1}`. With no terminal, `delete` runs without asking, with or without `--force`. Preview first with `--dry-run`: `remindjoectl delete "$ID" --dry-run --json`. `complete` takes `--dry-run` too.

## Look at one reminder

```bash
remindjoectl info "$ID" --json
```

Use it before an edit and after a failed write to see what was saved.

## Lists

Use `list` for the lists themselves: the list of lists, and creating, renaming and deleting a list.

```bash
remindjoectl list --json
remindjoectl list Projects --create
remindjoectl list Work --rename Office
remindjoectl list OldList --delete --force
```

`list --json` gives `{id, title, reminderCount, overdueCount}` per list. Create, rename and delete take one list name. `list <name>` is the remindctl form of a list read and also prints completed reminders. For the open reminders in a list, use `show open --list <name>`. A list name matches exactly, then ignoring case, then ignoring emoji and punctuation. If a name is ambiguous, use `--list-id`.

## JSON keys

A key with no value is left out. It is never `null`. Dates are ISO 8601 in UTC.

- `id`, `title`, `notes`, `url`, `listID`, `listName`: as named.
- `isCompleted`, `completionDate`, `creationDate`, `lastModifiedDate`.
- `priority`: `none`, `low`, `medium` or `high`.
- `dueDate`, `dueDateIsAllDay`: see below. `startDate`, `startDateIsAllDay`: the same for the start.
- `timeZone`: the reminder's zone name. `externalID`: the id that is the same on every device.
- `alarmDate`: the first fixed-time alarm. `alarms`: every alarm, each with a `kind` of `date`, `beforeDue`, `afterDue` or `place`. `beforeDue` has `seconds` (900 is 15 minutes).
- `recurrenceRule`: `frequency`, `interval`, and when set `daysOfWeek` (`{day, week}`, `week` -1 is last), `daysOfMonth`, `monthsOfYear`, `setPositions`, `end` (`{date}` or `{count}`).
- `locationTrigger`: `address`, `radius`, `proximity`, and `latitude` and `longitude` when known.
- `flagged`, `urgent`: `true` or `false`.
- `earlyReminder`: `{"count": 1, "unit": "days"}`. Left out when there is none.
- `tags`: names without `#`, sorted. `parentID`: set on a sub-task. `assignee`: `{id, name, status}`.
- `links`: the URLs of the links Reminders.app shows, in stored order. Left out when there are none. Not the same as `url`.
- `flagged` to `links` are all left out under `--no-private` or when ReminderKit is unavailable. `add`, `edit` and `complete` print them too, read back from ReminderKit after the save.

All-day due dates. If `dueDateIsAllDay` is `true`, the reminder is due on a local calendar day with no time. `dueDate` is midnight local time written in UTC. In Hong Kong, `2026-11-21` arrives as `2026-11-20T16:00:00Z`. Convert to local time and read the day. Do not take the date part of the UTC text. If `dueDateIsAllDay` is `false`, `dueDate` is an exact instant.
