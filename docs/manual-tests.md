# Manual tests

## Scope
Run on a local GUI session (not SSH-only) so the Reminders permission prompt can appear.

## Test data
- Use a dedicated list: `remindctl-manual-YYYYMMDD` (create if missing).
- Create 3 reminders with distinct states:
  - `remindctl test A` (due today, priority high)
  - `remindctl test B` (due tomorrow)
  - `remindctl test C` (no due date)

## Checklist
- authorize: `remindctl authorize`
- status: `remindctl status`
- doctor: `remindctl doctor --for-agent --json`
- list lists: `remindctl list`
- list table output: `remindctl list --format table`
- list list contents: `remindctl list "remindctl-manual-YYYYMMDD"`
- list by ID: `remindctl list --list-id <list-id-prefix>`
- add reminders (3 variants)
- add to exact list ID: `remindctl add "remindctl test D" --list-id <list-id-prefix>`
- show filters: `today`, `tomorrow`, `week`, `overdue`, `upcoming`, `open`, `completed`, `all`
- search: `remindctl search "remindctl test" --format table`
- info: `remindctl info <id-prefix> --json`
- export: `remindctl export --list-id <list-id-prefix> --json` and `--export-format csv`
- link: `remindctl link <id-prefix>` and `remindctl link --list-id <list-id-prefix>`
- open filter: `remindctl open --list-id <list-id-prefix> --format table`
- edit: update title/notes/priority/due date
- mixed alarms: create a reminder with absolute, relative, and location alarms; prove a due-only edit keeps all three and a clear-due-only edit keeps the absolute and location alarms but removes the relative (before-due) one (#45), while explicit alarm replacement/clear changes only absolute alarms
- complete: mark one reminder complete
- delete: remove reminders, then delete list

## Private fields (ReminderKit read)
Run these against real Reminders, on a local GUI session. They touch the store read-only. Record counts only, never titles or notes. Use `remindjoectl` for the installed command, or the debug binary from `make remindctl`. Needs `jq`.

1. Counts. `remindjoectl show all --json > "$TMPDIR/all.json"`, then:
   - total: `jq 'length' "$TMPDIR/all.json"`
   - flagged: `jq '[.[] | select(.flagged == true)] | length' "$TMPDIR/all.json"`
   - Urgent: `jq '[.[] | select(.urgent == true)] | length' "$TMPDIR/all.json"`
2. No gaps. `jq '[.[] | select(has("flagged") | not)] | length' "$TMPDIR/all.json"` must print `0`.
3. Doctor. `remindjoectl doctor --json | jq '.privateFields'` must show `"available": true`, `"reason": null` and this Mac's `macOSVersion`.
4. Off switch. `remindjoectl show all --json --no-private > "$TMPDIR/off.json"` (never print it) must have no `flagged`, `urgent`, `earlyReminder`, `tags`, `parentID` or `assignee` key. It must equal the output of a build without the bridge (the installed release from before the bridge, or a build from a commit before PR #28). Save that build's output as `"$TMPDIR/nobridge.json"` and compare silently: `diff <(jq -S . "$TMPDIR/off.json") <(jq -S . "$TMPDIR/nobridge.json") > /dev/null && echo equal`. Report only `equal` or `different`.
5. Bridge broken. In a throwaway copy of the repo, change `RPFrameworkPath` in `Sources/RemindPrivate/RemindPrivate.m` to a path that does not exist, then build it with `swift build`. Never commit this change.
   - `<throwaway-build> show all --json > "$TMPDIR/broken.json" 2> "$TMPDIR/broken.err"` must exit 0.
   - `wc -l < "$TMPDIR/broken.err"` must print `1`, and that line must read ``remindctl: private fields unavailable: ReminderKit did not load; run `remindctl doctor` for details``.
   - `diff <(jq -S . "$TMPDIR/broken.json") <(jq -S . "$TMPDIR/off.json") > /dev/null && echo equal` must print `equal`.
   - `<throwaway-build> doctor --json | jq '.privateFields'` must show `"available": false` and the full reason, with the `dlopen` paths.
6. Delete `$TMPDIR/all.json`, `off.json`, `nobridge.json`, `broken.json` and `broken.err` afterwards.

## Private fields (ReminderKit write)
These write, so run them only in a throwaway list `remindctl-fork-test-YYYYMMDD` that the check makes and deletes. Record counts of your own reminders before and after; they must match.

1. `remindjoectl list remindctl-fork-test-YYYYMMDD --create`.
2. `remindjoectl add "flag test" --list remindctl-fork-test-YYYYMMDD --flag --json` exits 0 with `"flagged" : true`; `info <id> --json` agrees, and so does Reminders.app.
3. `remindjoectl edit <id> --unflag --json` exits 0 with `"flagged" : false`; `info` agrees.
4. `remindjoectl edit <id> --flag --title renamed --json` changes both.
5. `edit <id> --flag --unflag` and `add x --list <throwaway> --flag --no-private` each exit 1 and change nothing.
6. With the throwaway build from the read section's step 5 (bridge broken): `add "should not exist" --list <throwaway> --flag` and `edit <id> --flag --title changed` each exit 1 with `flag not set: ReminderKit did not load (...); nothing was changed`. The list's count and the title stay the same.
7. `remindjoectl add "urgent timed" --list remindctl-fork-test-YYYYMMDD --due "<tomorrow> 09:00" --urgent --json` exits 0 with `"urgent" : true`; `info <id> --json` agrees, and so does Reminders.app.
8. `remindjoectl add "urgent no due" --list remindctl-fork-test-YYYYMMDD --urgent --json` exits 0 with `"urgent" : true`: Urgent needs no due date (macOS 27, 20 Nov 2026). Reminders.app must agree with `info`.
9. `remindjoectl edit <timed id> --not-urgent --json` exits 0 with `"urgent" : false`; `info` agrees.
10. `remindjoectl edit <timed id> --flag --urgent --json` exits 0 with `"flagged" : true` and `"urgent" : true`.
11. `edit <id> --urgent --not-urgent` and `add x --list <throwaway> --urgent --no-private` each exit 1 and change nothing.
12. With the broken-bridge build: `add "should not exist" --list <throwaway> --urgent` exits 1 with `Urgent not set: ReminderKit did not load (...); nothing was changed`, and the list's count stays the same.
13. `remindjoectl add "early timed" --list remindctl-fork-test-YYYYMMDD --due "<tomorrow> 09:00" --early 1d --json | jq -c .earlyReminder; echo "exit ${pipestatus[1]}"` (zsh) prints `{"count":1,"unit":"days"}` and then `exit 0`. `remindjoectl info <id> --json | jq -c .earlyReminder` prints the same, and Reminders.app shows "1 day before".
14. `remindjoectl edit <early timed id> --early 15m --json | jq -c .earlyReminder; echo "exit ${pipestatus[1]}"` prints `{"count":15,"unit":"minutes"}` and then `exit 0`. Then run `--early 1mo`, `--early 1w` and `--early 2h` the same way; each prints its own value and `exit 0`.
15. After steps 13, 14 and 19, Reminders.app shows exactly one Early Reminder on the reminder, never the old one beside the new, and `remindjoectl info <id> --json | jq -c .earlyReminder` prints that one. After step 18 it shows none, and `info` has no `earlyReminder` key. After step 20 it is unchanged. If more than one is stored, `info` has no `earlyReminder` key and stderr says `1 Early Reminder could not be read` (#51).
16. `remindjoectl add "early date only" --list remindctl-fork-test-YYYYMMDD --due "<tomorrow>" --early 1d --json`: record whether it exits 0 with the value or exits 1 with `Early Reminder set but read back as ...`. Either way `info` must match what was printed.
17. `remindjoectl add "early no due" --list remindctl-fork-test-YYYYMMDD --early 1d --json`: record the same. An exit 1 must name the reminder's id and say what was read back.
18. `remindjoectl edit <early timed id> --early none --json` exits 0 with no `earlyReminder` key; `info` and Reminders.app agree.
19. `remindjoectl edit <early timed id> --flag --urgent --early 2d --json` exits 0 with all three set.
20. `edit <id> --early 0d`, `edit <id> --early 1y`, `edit <id> --early 13mo`, `edit <id> --early 9223372036854775807mo` and `add x --list <throwaway> --early 1d --no-private` each exit 1 and change nothing.
21. With the broken-bridge build: `add "should not exist" --list <throwaway> --early 1d` exits 1 with `Early Reminder not set: ReminderKit did not load (...); nothing was changed`, and the list's count stays the same.
22. `remindjoectl add "tag test" --list remindctl-fork-test-YYYYMMDD --tag home --tag "#errand" --json | jq -c .tags; echo "exit ${pipestatus[1]}"` (zsh) prints `["errand","home"]` and then `exit 0`. `remindjoectl info <id> --json | jq -c .tags` prints the same, and Reminders.app shows #errand and #home.
23. `remindjoectl edit <tag id> --tag HOME --json | jq -c .tags` prints `["errand","home"]`: a tag the reminder has, in any case, is not added again. Reminders.app shows each tag once.
24. `remindjoectl edit <tag id> --untag errand --json | jq -c .tags` prints `["home"]`; `info` and Reminders.app agree. This step proves that removing one tag saves; an exit 1 with `tag errand removed but read back as tags errand, home` means it did not.
25. `remindjoectl edit <tag id> --untag home --json | jq -c .tags` prints `[]`; Reminders.app shows no tags.
26. `remindjoectl edit <tag id> --untag home --json` again exits 0 with `"tags" : []`: removing a tag the reminder does not have is not an error.
27. `edit <id> --tag "two words"`, `edit <id> --tag ""`, `edit <id> --tag home --untag Home` and `add x --list <throwaway> --tag home --no-private` each exit 1 and change nothing.
28. With the broken-bridge build: `add "should not exist" --list <throwaway> --tag home` exits 1 with `tag home not added: ReminderKit did not load (...); nothing was changed`, and the list's count stays the same.
29. `remindjoectl add "clear due early" --list remindctl-fork-test-YYYYMMDD --due "<tomorrow> 09:00" --early 1d`, then `remindjoectl edit <id> --clear-due --json` exits 0 with no `dueDate` and no `earlyReminder` key, and nothing on stderr. `info` and Reminders.app agree: no due date, no Early Reminder (#51).
30. `remindjoectl edit <id> --due "<tomorrow> 09:00" --early 1d`, then `remindjoectl edit <id> --clear-due --no-private --json` exits 0 with no `dueDate`. Stderr has exactly one line: `remindctl: due date cleared, but any Early Reminder was left: turned off by --no-private`. `info --json | jq -c .earlyReminder` still prints `{"count":1,"unit":"days"}`. With the broken-bridge build, `edit <id> --clear-due --json` also exits 0 with no `dueDate`, no `earlyReminder` key and one stderr line, `remindctl: due date cleared, but any Early Reminder was left: ReminderKit did not load`; `edit <id> --clear-due --early none` still exits 1.
31. `remindjoectl add "clear due plain" --list remindctl-fork-test-YYYYMMDD --due "<tomorrow> 09:00"`, then `remindjoectl edit <id> --clear-due --json` exits 0 with nothing on stderr, and the JSON has the same keys as 0.3.8 gave.
32. `remindjoectl add "start after due" --list remindctl-fork-test-YYYYMMDD --due "<in 5 days> 09:00" --start "<in 3 days> 09:00"`, then `remindjoectl edit <id> --due "<tomorrow> 09:00"` exits 1 with `The start date would be after the new due date; give an earlier --start, or --clear-start`. `info` shows both dates unchanged. `--due "<in 4 days> 09:00"` exits 0 and keeps the start.
33. `edit <id> --early 1M` and `edit <id> --tag "home,errand"` each exit 1 and change nothing. `edit <id> --tag "##home" --json | jq -c .tags` prints `["home"]`.
34. `remindjoectl add "link test" --list remindctl-fork-test-YYYYMMDD --link https://example.com/a --link mailto:test@example.com --json | jq -c .links; echo "exit ${pipestatus[1]}"` (zsh) prints `["https://example.com/a","mailto:test@example.com"]` and `exit 0`; `url` is left out. Reminders.app shows both links in the link field. `info <id>` prints two `Link:` lines, and `show` marks the line `[link]` (#55).
35. In Reminders.app, add the link `https://example.com/from-app` to the same reminder. `remindjoectl info <link id> --json | jq -c .links` lists it with the other two.
36. `remindjoectl edit <link id> --link https://example.com/a --json | jq -c .links` lists the same three: a link already there is not added again. `edit <link id> --unlink https://example.com/a --json | jq -c .links` drops it, and Reminders.app agrees. `edit <link id> --unlink https://example.com/a --json` again exits 0. `edit <link id> --link HTTPS://Example.com/from-app --json | jq -c .links` adds nothing (scheme and host match in any case), and `edit <link id> --unlink HTTPS://EXAMPLE.com/from-app --json | jq -c .links` removes it. In Reminders.app, add the link `tel:+15551234567` and a photo; `info <link id> --json | jq -c .links` lists the `tel:` link but not the photo, and `edit <link id> --unlink tel:+15551234567` removes the link and leaves the photo (#60).
37. `edit <link id> --link ftp://example.com`, `edit <link id> --link example.com`, `edit <link id> --link https://example.com/b --unlink https://example.com/b` and `edit <link id> --link https://example.com/b --no-private` each exit 1 and change nothing. With the broken-bridge build, `add "should not exist" --list <throwaway> --link https://example.com` exits 1 with `link https://example.com not added: ReminderKit did not load (...); nothing was changed`.
38. `remindjoectl edit <link id> --url https://example.com/eventkit --json | jq -c '{url, links}'` shows `url` set and `links` unchanged: the two fields stay apart.
39. Apple's database agrees (read-only). A link is a row in `ZREMCDOBJECT` whose `Z_ENT` is the number `Z_PRIMARYKEY` gives `REMCDURLAttachment`, with the URL in its `url` column (find the exact name, such as `ZURL`, with `PRAGMA table_info(ZREMCDOBJECT)`), linked to the reminder's `Z_PK` through one of the `ZREMINDER*` columns. Count the rows for the test reminder; it matches the length of `links`.
40. `remindjoectl list remindctl-fork-test-YYYYMMDD --delete --force`.

## Release gate
- `make check` must pass strict SwiftLint, tests, and the 90% RemindCore coverage gate.
- `make docs-site` must build without broken internal links.
- `make release-harness` must prove signature, notarization, per-slice plist, source/tag and token-isolation checks with credential-free fixtures.
- `make release-check TAG=vX.Y.Z` must pass before pushing an authorized release tag.
- Run the default no-publish dispatch on protected main; require exact-source push CI, signing/notarization, and native arm64/Intel verification to pass.
- On a disposable macOS GUI session, download and extract the candidate through the normal browser path, confirm `com.apple.quarantine` propagated naturally, then record Gatekeeper behavior. Do not set the attribute manually or substitute raw-CLI `spctl` acceptance.
- Record whether Reminders permission belongs to Terminal/Ghostty or the binary, and test upgrade from the previous official binary. Do not infer TCC continuity from the identifier alone.
- Only the tag-triggered CI pipeline publishes releases and dispatches Homebrew. Verify its exact tap run and the installed version after a real authorized release.

## Results
- Date:
- Machine:
- Permission state before/after:
- Notes:
