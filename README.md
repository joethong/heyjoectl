# remindjoectl

![remindctl banner](docs/assets/readme-banner.jpg)

An enhanced fork of [remindctl](https://github.com/openclaw/remindctl), Peter Steinberger's command line for Apple Reminders on macOS.

Use it from scripts, agents or the terminal to read and change the reminders you see in Reminders.app. It does everything remindctl 0.3.8 does, with the same commands, flags, JSON keys and exit codes. On top of that it reads and writes the Reminders.app features remindctl leaves out: flags, Urgent, Early Reminders, tags, links, full repeat rules and every kind of alarm.

The installed command is `remindjoectl`. Link `remindctl` to it and scripts written for remindctl use the fork unchanged.

## What this fork adds

### Repeats

- Repeats on set weekdays (`weekly on mon,fri`), on days of the month (`monthly on 1,15`, `-1` for the last day), and on a position (`monthly on last fri`, `monthly on 2nd tue`).
- An end date (`--repeat-until`) or a number of times (`--repeat-count`). On `edit`, either one alone changes only the end of the current repeat.
- The whole rule in JSON, including repeats made in Reminders.app on an iPhone. The plain output says the repeat in words.

### Alarms

- Every alarm in JSON, each marked as a fixed time, before the due date, after the due date, or a place.
- `--alarm-before 15m` adds an alarm that moves with the due date. `--alarm-before none` removes only those.

### Dates

- Weekday names and times: `--due friday`, `"friday 9am"`, `"tomorrow 17:30"`, `next friday`, `this friday`.
- Start dates: `--start` and `--clear-start`, plus `startDate`, the reminder's time zone and the cross-device id in JSON.
- `--clear-due` also removes before-due alarms, the Early Reminder, and a start date that was only a copy of the due date. Moving the due date before a start date you set yourself is refused.

### Flag, Urgent, Early Reminder, tags and links

Apple's public API has none of these. The fork reads and writes them anyway (see [How the private fields work](#how-the-private-fields-work)).

- The flag: `flagged`, `--flag`, `--unflag`.
- Urgent: `urgent`, `--urgent`, `--not-urgent`.
- The Early Reminder: `earlyReminder`, `--early 1d`, `--early none`.
- Tags: `tags`, `--tag`, `--untag`.
- The links Reminders.app shows: `links`, `--link`, `--unlink`.
- Read only: a sub-task's parent (`parentID`) and the assignee in a shared list (`assignee`).

### Speed and safety

- Views of open reminders (`today`, `overdue`, `upcoming`, `open`, a date, `search`) fetch only open reminders, which keeps frequent reads fast.
- `add`, `edit` and `complete` print the private fields too, read back after the save.
- A failed write says exactly what was saved. When nothing was saved, it says `nothing was changed`.
- `--no-private` skips the private fields, for a quicker read of the public ones.
- `doctor --json` reports whether the private fields work on this Mac, and why not if they don't.

### How the private fields work

The flag, Urgent, Early Reminder, tags, links, sub-task parent and assignee come from ReminderKit, the private framework Reminders.app itself uses, which the fork loads at run time. It needs no Full Disk Access and no permission beyond Reminders access.

Apple can change a private framework in any macOS update, so the fork checks every method it needs before it changes anything:
- If a method is missing, reads still work: the private keys are left out of the JSON and one line goes to stderr.
- Private writes refuse with `nothing was changed`.
- `doctor --json` says which method is missing.

It's tested on macOS 27.

Neither EventKit nor this fork supports Reminders sections, Smart Lists, file and image attachments, or writing sub-tasks and assignees.

## Install

The fork has no Homebrew formula yet, so build it from source:

```bash
pnpm install
pnpm build
# binary at ./bin/remindctl
install -m 755 bin/remindctl /usr/local/bin/remindjoectl
ln -sf remindjoectl /usr/local/bin/remindctl   # optional: scripts that call remindctl get the fork
```

`pnpm build` signs the binary ad hoc. To install on another Mac over SSH and roll back to Homebrew's remindctl, see [docs/fork-install.md](docs/fork-install.md).

`remindjoectl --version` prints the fork's version, such as `0.3.9-joe.5`.

## Requirements

- macOS 14+ (Sonoma or later)
- Swift 6.2+ when building from source
- Full Reminders access for the terminal app that runs `remindjoectl`

## Quick start

```bash
remindjoectl add "Buy milk"
remindjoectl add "Call mom" --list Personal --due tomorrow
remindjoectl add "Meeting" --due "friday 9am" --alarm-before 15m
remindjoectl add "Gym" --due 2026-11-23 --repeat "weekly on mon,fri" --repeat-count 8
remindjoectl add "Pay invoice" --flag --urgent --early 1d --tag money
remindjoectl add "Read the brief" --link "https://example.com/brief"

remindjoectl today
remindjoectl overdue
remindjoectl open
remindjoectl show open --list Work
remindjoectl show open --tag errand --json
remindjoectl search "milk"
remindjoectl info 4A83 --json
remindjoectl doctor --json

remindjoectl edit 4A83 --title "New title" --due 2026-11-24
remindjoectl edit 4A83 --unflag --tag errand --untag home
remindjoectl complete 4A83 7B21
remindjoectl delete 4A83 --force
```

Indexes such as `1` come from the default reminder listing. Most commands also accept an ID prefix such as `4A83`. Scripts and agents should use the full `id` from JSON, because the numbering changes as reminders are added or completed.

For agents, [SKILL.md](SKILL.md) has one working command per task, what each JSON key means, and the rules for reading output and handling errors. [docs/commands.md](docs/commands.md) has every option.

## Commands

| Command | Purpose |
| --- | --- |
| `remindjoectl` / `remindjoectl today` | Show today's reminders |
| `remindjoectl show <view>` | Read reminders by view or date, with `--list`, `--tag` and `--json` |
| `remindjoectl search <query>` | Search incomplete reminder titles, notes, and URLs |
| `remindjoectl info <id>` | Show detailed reminder metadata |
| `remindjoectl list` | Show the reminder lists, or create, rename or delete one |
| `remindjoectl export` | Export reminders as JSON or CSV |
| `remindjoectl link <id>` | Print a best-effort Reminders deep link |
| `remindjoectl open <id>` | Open a reminder or list in Reminders.app |
| `remindjoectl doctor` | Diagnose permissions and the private fields |
| `remindjoectl add <title>` | Create a reminder |
| `remindjoectl edit <id>` | Edit a reminder by index or ID prefix |
| `remindjoectl complete <id...>` | Mark reminders complete |
| `remindjoectl delete <id...>` | Delete reminders |
| `remindjoectl status` | Show Reminders permission status |
| `remindjoectl authorize` | Request Reminders permission when macOS allows it |

Run `remindjoectl <command> --help` for the full option list. Unexpected extra arguments are rejected; quote multi-word titles and list names.

## Showing reminders

Read reminders with `show <view>`. Add `--list` or `--list-id` to pick a list, `--tag` to filter by tag, and `--json` for output a program can read. The view name alone, such as `remindjoectl today`, is a shortcut for `show today`.

Views:

```bash
remindjoectl today
remindjoectl tomorrow
remindjoectl week
remindjoectl overdue
remindjoectl upcoming
remindjoectl open
remindjoectl completed
remindjoectl all
remindjoectl 2026-01-03
```

`today` shows reminders due today and overdue ones. `open` shows every incomplete reminder, including those with no due date. Add `--tag errand` to show only reminders with that tag, and repeat `--tag` to need every tag given. It reads tags through ReminderKit, so it fails with `--no-private`.

```bash
remindjoectl show all --tag errand --tag home
```

Search titles, notes, and URLs:

```bash
remindjoectl search "milk"
remindjoectl search "invoice" --list Work
remindjoectl search "project" --completed --json
remindjoectl search "milk" --tag errand
```

Standard search output includes stable reminder IDs instead of numeric indexes.

Inspect one reminder:

```bash
remindjoectl info 1
remindjoectl info 4A83 --json
```

Limit a view to one list:

```bash
remindjoectl show overdue --list Work
remindjoectl show open --list-id 7A12 --json
```

## Lists

Use `list` for the lists themselves: the list of lists, and creating, renaming and deleting a list.

```bash
remindjoectl list
remindjoectl list Projects --create
remindjoectl list Work --rename Office
remindjoectl list OldList --delete --force
```

Create, rename and delete accept one list name. `list <name...>` is the remindctl form of a list read: it prints the reminders in one or more lists and also prints completed ones. For the open reminders in a list, use `show open --list <name>`.
List names resolve by exact match, case-insensitive match, then a normalized match that ignores emoji and punctuation. If a name is ambiguous, use `--list-id`.

```bash
remindjoectl show open --list-id 7A12
remindjoectl add "Review notes" --list-id 7A12
remindjoectl edit 4A83 --list-id 7A12
```

## Dates and due times

Accepted by `--due`, `--start`, `--alarm`, `--repeat-until` and date filters:

- `today`, `tomorrow`, `yesterday`, `now`
- A weekday, such as `friday` or `fri`: the next one after today. `next friday` is the same; `this friday` is this week's.
- A time after `today`, `tomorrow` or a weekday: `"friday 9:00"`, `"friday 5:30pm"`, `"tomorrow 9am"`
- `YYYY-MM-DD`
- `YYYY-MM-DD HH:mm`
- ISO 8601 with timezone, such as `2026-01-03T12:34:56Z`
- Local ISO 8601 without timezone, such as `2026-01-03T12:34:56`

Date-only due values create all-day reminders. Date-time values create timed reminders.
A time skipped by a clock change moves forward on the same day; if that would land on the next day, the date is refused.
Absolute dates must contain a valid calendar date, time, and offset; invalid dates and trailing text are rejected. Legacy `MM/dd/yyyy` and `dd-MM-yy`/`dd-MM-yyyy` inputs keep their explicit month/day order.

## Alarms

A timed due date gets an alarm at the due time. Use `--alarm` for a fixed time, or `--alarm-before` for an alarm that moves with the due date.

```bash
remindjoectl add "Meeting" --due "2026-01-03 09:00" --alarm "2026-01-03 08:55"
remindjoectl add "Meeting" --due "2026-01-03 09:00" --alarm-before 15m
remindjoectl edit 4A83 --alarm-before none
remindjoectl edit 4A83 --clear-alarm
```

Moving a timed due date moves the alarm at the old due time with it. A date-only due date or `--clear-due` removes that alarm. Other alarms stay. `--alarm` and `--clear-alarm` change fixed-time alarms only. `--alarm-before` (units `m`, `h`, `d`, `w`) changes before-due alarms only and needs a due date. JSON lists every alarm under `alarms`; `alarmDate` is still the earliest fixed-time alarm.

## Repeat

```bash
remindjoectl add "Take vitamins" --due tomorrow --repeat daily
remindjoectl add "Water filter" --due 2026-09-13 --repeat "every 6 months"
remindjoectl add "Pay rent" --due 2026-12-25 --repeat "monthly on last fri"
remindjoectl add "Summer course" --due 2026-06-01 --repeat "weekly on tue,thu" --repeat-until 2026-08-31
remindjoectl edit 4A83 --repeat-count 6
remindjoectl edit 4A83 --no-repeat
```

Supported repeat values:

- `daily`, `weekly`, `biweekly`, `monthly`, `yearly`
- `every N days/weeks/months/years`
- `weekly on mon,fri`
- `monthly on 1,15` (`-1` is the last day)
- `monthly on last fri`, `monthly on 2nd tue` (positions `1st` to `5th` and `last`)
- `yearly on` with the same day lists

A repeat needs a due date. A bad value fails with the list of valid forms.

## Flag, Urgent, Early Reminder, tags and links

```bash
remindjoectl add "Pay invoice" --flag
remindjoectl edit 4A83 --urgent
remindjoectl edit 4A83 --early 1d        # m, h, d, w or mo, up to a year
remindjoectl edit 4A83 --early none
remindjoectl edit 4A83 --tag errand --untag home
remindjoectl edit 4A83 --link "https://example.com/new" --unlink "https://example.com/old"
```

Tags have no spaces and are given without `#`. A tag or link already there is not added twice, and removing one the reminder doesn't have is not an error. Links match with the scheme and host in any case.

`--link` sets the link Reminders.app shows. `--url` is a separate field, EventKit's URL, which remindctl also copies into a `remindctl URL (managed): ...` notes line. It works as it did in remindctl.

If a private write fails, the command exits 1 and the message says what was saved, for example `reminder created (id …); flag not set: …`. Don't retry an `add` blindly: check with `info` or `search` first.

## Location triggers

Use `--location` on `add` to create an arriving geofence trigger. Add `--leaving` to trigger when leaving, and `--radius` to customize the geofence radius in meters.

```bash
remindjoectl add "Check mailbox" --location "1 Apple Park Way, Cupertino, CA"
remindjoectl add "Lock up" --location "Home" --leaving
remindjoectl add "Get groceries" --location "123 Main St" --radius 200
```

Location triggers use EventKit and CoreLocation geocoding. They may depend on system location services and network availability.

## Output

Global output flags:

- `--json` emits machine-readable JSON.
- `--plain` emits stable tab-separated lines.
- `--format table` emits tabular output for scan-heavy commands.
- `--quiet` emits minimal output, usually counts or nothing.
- `--no-color` disables colored output.
- `--no-input` disables interactive prompts.
- `--no-private` skips the private fields.

JSON keeps every remindctl 0.3.8 key and adds new ones: `startDate`, `startDateIsAllDay`, `timeZone`, `externalID`, `alarms`, the full `recurrenceRule`, and from ReminderKit `flagged`, `urgent`, `earlyReminder`, `tags`, `links`, `parentID` and `assignee`. A key with no value is left out. Read JSON from stdout only; warnings go to stderr. [docs/commands.md](docs/commands.md) lists every key.

## Export, links and completion

```bash
remindjoectl export --json
remindjoectl export --list Work --export-format csv
remindjoectl link 1
remindjoectl open 1
remindjoectl open --list Work --app
remindjoectl completion zsh
```

`link` and `open <id>` use best-effort Reminders deep links based on EventKit IDs.

## Permissions

```bash
remindjoectl status
remindjoectl authorize
remindjoectl doctor --for-agent
```

If macOS reports access as denied, enable the terminal app in:

```text
System Settings > Privacy & Security > Reminders
```

If no prompt appears, run this once from the same terminal app, allow access, and rerun `remindjoectl status`:

```bash
osascript -e 'tell application "Reminders" to get name of reminders'
```

Over SSH, grant access on the Mac that runs `remindjoectl`. macOS grants access per program, so a new build may need it granted again.

## EventKit limits

Reminder reads skip orphaned EventKit reminders whose calendar is missing; other reminders remain available.
If a calendar is missing after `add`, `edit`, or `complete` saves a reminder, the command reports `Reminder is missing a calendar` instead of crashing. The change has already been saved; check Reminders.app before retrying.

Moving reminders with `edit --list` or `edit --list-id` can fail when either list is shared. If EventKit rejects the move with `com.apple.reminderkit error -3002`, move the reminder in Reminders.app, then retry any other edits.

## Development

```bash
make test                      # tests with coverage
make check                     # strict lint + tests + 90% coverage gate
scripts/check-coverage.sh      # full suite and the RemindCore coverage gate
scripts/test-install-fork.sh   # checks for the install and rollback scripts
make remindctl ARGS="status"   # clean build + run
pnpm build                     # release build into ./bin/remindctl
```

Install the same checksum-verified SwiftLint as upstream's CI with `bash scripts/install-linters.sh`, then `export PATH="$PWD/.build/linters:$PATH"` before `make lint`. When only the Command Line Tools are installed (no Xcode), SwiftLint also needs `export TOOLCHAIN_DIR=/Library/Developer/CommandLineTools`. The fork's release number lives in `fork-version.env`.

The Swift code, modules and signing identifier keep the name `remindctl`, so upstream fixes still merge in cleanly. Upstream's release steps are in [docs/RELEASING.md](docs/RELEASING.md).

## Credits and licence

`remindjoectl` is a fork of [remindctl](https://github.com/openclaw/remindctl) by Peter Steinberger and keeps its MIT licence ([LICENSE](LICENSE)). It follows upstream and merges in its releases. The original tool's site is [remindctl.sh](https://remindctl.sh).
