# Installing the fork on another Mac

Two scripts put the fork on another Mac over SSH and take it off again, replacing a Homebrew-installed remindctl there. Run them on your own Mac, in this repo. They reach the target Mac as the SSH host you set in `REMINDJOECTL_HOST` (required; for example `REMINDJOECTL_HOST=my-mac scripts/install-fork.sh`), which needs Homebrew's remindctl installed.

After the install, `remindctl` on the target Mac is the fork, so scripts and agents that call `remindctl` get it with no change. Homebrew's 0.3.8 stays installed, pinned and unlinked, so the rollback can bring it back.

Neither script runs any remindctl command on the target Mac except `--version`, which needs no Reminders permission.

## 1. Dry run

```sh
scripts/install-fork.sh
```

This reads what `/opt/homebrew/bin/remindctl` is on the target Mac and prints every step. It changes nothing. Check the version it names (for example `0.3.9-joe.5`).

If it says `Refusing`, the script stopped before it touched the target Mac. The reason is one of these.

- **Uncommitted changes.** Tracked files in this repo differ from the last commit, and the script lists them. It only ships reviewed code. Commit the change through a pull request, or undo it with `git checkout -- <file>`, and run again. A `FORK_RELEASE` bump must be committed together with the regenerated `Sources/remindctl/Version.swift` (run `scripts/generate-version.sh`). Otherwise the first `--apply` rewrites that tracked file and the next run is refused for it.
- **Untracked source files.** Untracked files under `Sources/`, or an untracked `Package.swift` or `Package.resolved`, are refused too, because SwiftPM builds them into the binary. This includes files that `.gitignore` hides, such as `Sources/remindctl/bin/X.swift`; only `.DS_Store` is let through. The script lists them. Commit them through a pull request or move them out of the way. Other untracked files, such as scratch notes or `.build`, are ignored.
- **Not on `origin/main`.** The script runs `git fetch origin` and the commit you are on is not part of `origin/main`. Merge the work through a pull request, pull `main`, and run from there. A commit that is already in `origin/main` is fine, even if `main` has moved on.
- **Could not fetch origin.** The script can't tell whether the commit is reviewed without asking GitHub. Check the network and `git remote -v`, then run again.
- **`/opt/homebrew/bin/remindctl` is neither Homebrew's link nor ours.** Find out what it is before going on.
- **The release folder already holds a different binary.** This one shows up only with `--apply`, after the build (see step 2).

## 2. Install

```sh
scripts/install-fork.sh --apply
```

It builds and signs the binary on your Mac and checks its version. Before the copy it compares the SHA-256 checksum of the new binary with `~/remindjoectl-releases/<version>/remindjoectl` on the target Mac, if one is there. The same binary means a rerun from the same checkout and is fine. A rebuild of the same commit in another folder or worktree may not be byte for byte the same. In that case the script reads `COMMIT` in the release folder: if it names this same commit, it prints "the same commit, built elsewhere; replacing it" and goes on. A different binary whose `COMMIT` is missing or names another commit is refused, because the release folder is the record of what was installed. Raise `FORK_RELEASE` in `fork-version.env` through a pull request to make a new version. Remove the folder on the target Mac by hand only if you are sure that version was never installed. Then it copies the binary to `~/remindjoectl-releases/<version>/` on the target Mac, writes the commit it was built from to `COMMIT` in the same folder, and checks the binary runs there. The copy goes to a temporary name first and is moved into place, so a dropped connection never leaves a half-copied binary under the release name. Only then does it touch Homebrew: it installs it as `/opt/homebrew/bin/remindjoectl`, with `remindctl` linked to it. It ends by printing `remindctl --version` and `remindjoectl --version` from the target Mac. Both should show the new version.

If a step fails, the script stops and says how to undo. Before the copy it says "Nothing on the target Mac has changed". During the copy it says only the release folder may have changed, and a rerun is safe. Once Homebrew's remindctl is touched it says to run the rollback.

## 3. Check through the real caller

Check through whatever calls `remindctl` on the target Mac (a script, a scheduled job or an agent), not only over SSH: for example `remindctl --version`, `remindctl show today --json` and `remindctl doctor --json`. The answer should match the Reminders app.

If it reports an error, roll back first so the caller works again. A Reminders permission error (`denied` or `not-determined`) is the likely first failure: macOS grants Reminders access per program. In our use the caller kept its approval across releases, but grant it again through that caller, not over SSH, if it doesn't.

## 4. Roll back

```sh
scripts/rollback-fork.sh            # dry run
scripts/rollback-fork.sh --apply
```

This moves our `remindctl` link aside, runs `brew link remindctl`, and deletes our link only once `remindctl` points at Homebrew's copy. If `brew link` fails, our link is put back, the script exits with `brew link remindctl failed; our remindctl link is back in place and still works`, and `remindctl` on the target Mac keeps working as the fork. Fix what `brew link` complained about and run the rollback again. It then removes our `remindjoectl` binary and unpins Homebrew's remindctl. It checks `remindctl` is Homebrew's link again and prints `remindctl --version`. That must be exactly the version `brew list --versions remindctl` reports (today `0.3.8`); if it is not, the script fails and names both versions. If `remindctl` is something other than ours or Homebrew's, it stops and leaves it alone. The release folders in `~/remindjoectl-releases/` stay. Every step is safe to run again, so if one fails, fix the cause and rerun it. If the connection drops during that switch (it takes about a second), `remindctl` may be missing on the target Mac: run the rollback again, and it links Homebrew's copy. The install recovers the same way.
