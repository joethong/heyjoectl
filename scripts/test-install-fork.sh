#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=version.env
source "$ROOT/version.env"
# shellcheck source=fork-version.env
source "$ROOT/fork-version.env"
version="${MARKETING_VERSION}-joe.${FORK_RELEASE}"
work="$(mktemp -d "${TMPDIR:-/tmp}/remindjoectl-install-tests.XXXXXX")"
trap 'rm -rf "$work"' EXIT

passed=0
fail() {
  echo "FAIL: $*" >&2
  echo "--- last output ---" >&2
  cat "$work/out" >&2 || true
  exit 1
}
ok() {
  passed=$((passed + 1))
  echo "ok - $*"
}

make_fakes() {
  local bin="$work/fakebin"
  mkdir -p "$bin"

  cat >"$bin/ssh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
host=$1
shift
echo "ssh $host $*" >>"$FAKE_WORK/calls.log"
cmd="$*"
cmd="${cmd//\/opt\/homebrew/$FAKE_WORK/prefix}"
cd "$FAKE_WORK/home"
FAKE_ON_TARGET=1 HOME="$FAKE_WORK/home" PATH="/usr/bin:/bin:/usr/sbin:/sbin" bash -c "$cmd"
SH

  cat >"$bin/scp" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "scp $*" >>"$FAKE_WORK/calls.log"
[[ -z ${FAKE_SCP_FAIL:-} ]] || exit 1
src=$1
dest=${2#*:}
if [[ -n ${FAKE_SCP_PARTIAL:-} ]]; then
  head -c 5 "$src" >"$FAKE_WORK/home/$dest"
  exit 1
fi
cp "$src" "$FAKE_WORK/home/$dest"
SH

  cat >"$bin/swift" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
echo "swift $*" >>"$FAKE_WORK/calls.log"
out="$PWD/.build/fake-products/Release"
if [[ " $* " == *" --show-bin-path "* ]]; then
  echo "$out"
  exit 0
fi
[[ -z ${FAKE_SWIFT_FAIL:-} ]] || exit 1
mkdir -p "$out"
printf '#!/bin/sh\nif [ -n "$FAKE_ON_TARGET" ] && [ -n "$FAKE_TARGET_CANT_RUN" ]; then exit 1; fi\necho %s\n' "$FAKE_BUILD_VERSION" >"$out/remindctl"
chmod 755 "$out/remindctl"
SH

  cat >"$bin/codesign" <<'SH'
#!/usr/bin/env bash
echo "codesign $*" >>"$FAKE_WORK/calls.log"
SH

  chmod 755 "$bin"/*
}

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null XDG_CONFIG_HOME="$work/xdg"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

in_repo() {
  git -C "$work/repo" "$@"
}

make_repo() {
  local repo="$work/repo"
  mkdir -p "$repo/scripts"
  cp "$ROOT/scripts/install-fork.sh" "$ROOT/scripts/rollback-fork.sh" "$ROOT/scripts/generate-version.sh" "$repo/scripts/"
  cp "$ROOT/version.env" "$ROOT/fork-version.env" "$repo/"
  (cd "$repo" && scripts/generate-version.sh)
  git init -q --bare -b main "$work/origin.git"
  in_repo init -q -b main
  in_repo add -A
  in_repo commit -q -m "release candidate"
  in_repo remote add origin "$work/origin.git"
  in_repo push -q origin main
}

make_target() {
  local prefix="$work/prefix"
  rm -rf "$prefix" "${work:?}/home"
  mkdir -p "$prefix/bin" "$prefix/Cellar/remindctl/0.3.8/bin" "$prefix/var/homebrew/pinned" "$work/home"
  printf '#!/bin/sh\necho 0.3.8\n' >"$prefix/Cellar/remindctl/0.3.8/bin/remindctl"
  chmod 755 "$prefix/Cellar/remindctl/0.3.8/bin/remindctl"
  ln -s ../Cellar/remindctl/0.3.8/bin/remindctl "$prefix/bin/remindctl"

  cat >"$prefix/bin/brew" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
prefix="$(cd "$(dirname "$0")/.." && pwd)"
echo "ran brew $*" >>"$FAKE_WORK/calls.log"
[[ ${FAKE_BREW_FAIL:-} != "$1" ]] || { echo "Error: fake brew $1 failed" >&2; exit 1; }
link="$prefix/bin/remindctl"
case "$1 ${2:-}" in
  "pin remindctl") touch "$prefix/var/homebrew/pinned/remindctl" ;;
  "unpin remindctl") rm "$prefix/var/homebrew/pinned/remindctl" ;;
  "list --pinned") ls "$prefix/var/homebrew/pinned" ;;
  "list --versions") echo "remindctl ${FAKE_BREW_VERSION:-0.3.8}" ;;
  "unlink remindctl")
    case "$(readlink "$link" || true)" in
      ../Cellar/remindctl/*) rm "$link" ;;
    esac
    ;;
  "link remindctl")
    if [[ -e $link || -L $link ]]; then
      echo "Error: Could not symlink bin/remindctl" >&2
      exit 1
    fi
    [[ -z ${FAKE_BREW_LINK_NOOP:-} ]] || exit 0
    ln -s ../Cellar/remindctl/0.3.8/bin/remindctl "$link"
    ;;
  *) echo "fake brew: unexpected $*" >&2; exit 2 ;;
esac
SH
  chmod 755 "$prefix/bin/brew"
  : >"$work/calls.log"
}

snapshot() {
  (
    cd "$work/prefix"
    find . | sort | while IFS= read -r path; do
      if [[ -L $path ]]; then
        echo "$path -> $(readlink "$path")"
      elif [[ -f $path ]]; then
        echo "$path $(stat -f %Lp "$path") $(shasum "$path" | cut -d' ' -f1)"
      else
        echo "$path/"
      fi
    done
  )
}

run_script() {
  local name=$1
  shift
  (cd "$work/repo" && PATH="$work/fakebin:$PATH" FAKE_WORK="$work" "./scripts/$name" "$@") >"$work/out" 2>&1
}

expect_ok() {
  run_script "$@" || fail "$* exited non-zero"
}

expect_fail() {
  if run_script "$@"; then
    fail "$* unexpectedly succeeded"
  fi
}

expect_output() {
  grep -qF -- "$1" "$work/out" || fail "output lacks: $1"
}

expect_called() {
  grep -qF -- "$1" "$work/calls.log" || fail "not called: $1"
}

expect_before() {
  local first second
  first="$(grep -nF -- "$1" "$work/calls.log" | head -n 1 | cut -d: -f1 || true)"
  second="$(grep -nF -- "$2" "$work/calls.log" | head -n 1 | cut -d: -f1 || true)"
  [[ -n $first ]] || fail "not called: $1"
  [[ -n $second ]] || fail "not called: $2"
  (( first < second )) || fail "'$1' ran after '$2'"
}

expect_not_called() {
  if grep -qF -- "$1" "$work/calls.log"; then
    fail "should not have called: $1"
  fi
}

make_fakes
make_repo
export FAKE_WORK="$work" FAKE_BUILD_VERSION="$version" REMINDJOECTL_HOST=target-mac

make_target
before="$(snapshot)"
expect_ok install-fork.sh
[[ "$(snapshot)" == "$before" ]] || fail "install dry run changed the target Mac"
[[ ! -d "$work/home/remindjoectl-releases" ]] || fail "install dry run made a release folder"
expect_not_called "swift "
expect_not_called "codesign "
expect_not_called "scp "
expect_not_called "ran brew "
expect_output "Dry run"
expect_output "brew pin remindctl"
expect_output "brew unlink remindctl"
expect_output "--apply"
ok "install dry run changes nothing and prints every step"

expect_ok rollback-fork.sh
[[ "$(snapshot)" == "$before" ]] || fail "rollback dry run changed the target Mac"
expect_not_called "ran brew "
expect_output "brew link remindctl"
ok "rollback dry run changes nothing"

expect_ok install-fork.sh --apply
[[ "$(readlink "$work/prefix/bin/remindctl")" == remindjoectl ]] || fail "remindctl does not point to remindjoectl"
[[ "$(stat -f %Lp "$work/prefix/bin/remindjoectl")" == 755 ]] || fail "remindjoectl is not mode 755"
[[ -f "$work/prefix/var/homebrew/pinned/remindctl" ]] || fail "remindctl not pinned"
[[ -x "$work/home/remindjoectl-releases/$version/remindjoectl" ]] || fail "release folder missing"
[[ -x "$work/prefix/Cellar/remindctl/0.3.8/bin/remindctl" ]] || fail "Homebrew copy removed"
expect_called "swift build -c release --arch arm64 --product remindctl"
expect_called "codesign --force --sign - --identifier com.steipete.remindctl"
expect_output "remindctl --version: $version"
expect_output "remindjoectl --version: $version"
ok "install --apply puts our binary behind remindctl"

expect_before "install -m 755" "ln -sf remindjoectl"
expect_before "ran brew pin remindctl" "ran brew unlink remindctl"
ok "install --apply installs the binary before linking remindctl to it, and pins before unlinking"

expect_ok install-fork.sh --apply
[[ "$(readlink "$work/prefix/bin/remindctl")" == remindjoectl ]] || fail "second install broke the link"
ok "install --apply runs twice"

expect_ok rollback-fork.sh --apply
[[ "$(snapshot)" == "$before" ]] || fail "rollback did not restore the target Mac"
[[ -x "$work/home/remindjoectl-releases/$version/remindjoectl" ]] || fail "rollback removed the release folder"
expect_output "remindctl --version: 0.3.8"
ok "install then rollback leaves things as they were"

expect_ok rollback-fork.sh --apply
[[ "$(snapshot)" == "$before" ]] || fail "second rollback changed the target Mac"
ok "rollback --apply runs twice"

make_target
rm "$work/prefix/bin/remindctl"
printf '#!/bin/sh\necho someone else\n' >"$work/prefix/bin/remindctl"
before="$(snapshot)"
expect_fail install-fork.sh --apply
[[ "$(snapshot)" == "$before" ]] || fail "refusal changed the target Mac"
expect_not_called "swift "
expect_not_called "ran brew "
expect_output "Refusing"
expect_fail install-fork.sh
expect_output "Refusing"
ok "refuses a foreign remindctl, in dry run and apply"

make_target
before="$(snapshot)"
FAKE_BREW_FAIL="unlink" expect_fail install-fork.sh --apply
expect_output "Failed: "
expect_output "scripts/rollback-fork.sh --apply"
expect_called "ran brew unlink remindctl"
[[ "$(readlink "$work/prefix/bin/remindctl")" == ../Cellar/remindctl/0.3.8/bin/remindctl ]] || fail "failed install left remindctl changed"
grep -q "remindctl --version" "$work/calls.log" && fail "ran steps after the failed one"
expect_ok rollback-fork.sh --apply
[[ "$(snapshot)" == "$before" ]] || fail "rollback after a failed install did not restore the target Mac"
ok "stops at a failed step and the rollback it prints restores the target Mac"

make_target
FAKE_SWIFT_FAIL=1 expect_fail install-fork.sh --apply
expect_output "Failed: "
expect_output "Nothing on the target Mac has changed"
expect_not_called "codesign "
expect_not_called "scp "
ok "stops when the build fails"

make_target
before="$(snapshot)"
FAKE_BUILD_VERSION=0.3.9 expect_fail install-fork.sh --apply
expect_output "reports 0.3.9, expected $version"
expect_output "Nothing on the target Mac has changed"
expect_not_called "scp "
expect_not_called "mkdir"
[[ "$(snapshot)" == "$before" ]] || fail "version mismatch changed the target Mac"
ok "version mismatch stops before copying"

make_target
before="$(snapshot)"
FAKE_SCP_FAIL=1 expect_fail install-fork.sh --apply
expect_output "Only the release folder"
expect_not_called "ran brew "
[[ "$(snapshot)" == "$before" ]] || fail "failed copy changed /opt/homebrew"
ok "a failed copy stops before /opt/homebrew and says what changed"

make_target
before="$(snapshot)"
FAKE_TARGET_CANT_RUN=1 expect_fail install-fork.sh --apply
expect_output "could not run remindjoectl-releases/$version/remindjoectl --version"
expect_output "Only the release folder"
expect_not_called "ran brew "
[[ "$(snapshot)" == "$before" ]] || fail "a binary the target Mac cannot run still changed /opt/homebrew"
ok "a binary the target Mac cannot run stops before remindctl is switched"

make_target
REMINDJOECTL_HOST=otherhost expect_ok install-fork.sh --apply
expect_called "ssh otherhost "
expect_called ".build/fake-products/Release/remindctl otherhost:"
expect_not_called "ssh target-mac "
ok "REMINDJOECTL_HOST picks the host"

make_target
for script in install-fork.sh rollback-fork.sh; do
  REMINDJOECTL_HOST='' expect_fail "$script"
  expect_output "Refusing: set REMINDJOECTL_HOST"
  [[ -s "$work/calls.log" ]] && fail "$script without a host still ran a command"
done
ok "the scripts refuse without REMINDJOECTL_HOST"

make_target
rm "$work/prefix/bin/remindctl"
expect_ok install-fork.sh --apply
[[ "$(readlink "$work/prefix/bin/remindctl")" == remindjoectl ]] || fail "install over a missing remindctl did not link ours"
expect_ok rollback-fork.sh --apply
[[ "$(readlink "$work/prefix/bin/remindctl")" == ../Cellar/remindctl/0.3.8/bin/remindctl ]] || fail "rollback did not relink Homebrew's"
ok "installs when remindctl is missing, and rolls back to Homebrew's"

make_target
expect_ok install-fork.sh --apply
FAKE_BREW_FAIL=list expect_fail rollback-fork.sh --apply
expect_output "Failed: Let Homebrew upgrade remindctl again"
[[ -f "$work/prefix/var/homebrew/pinned/remindctl" ]] || fail "pin vanished"
ok "rollback stops when brew list --pinned fails"

make_target
rm "$work/prefix/bin/remindctl"
printf '#!/bin/sh\necho 9.9.9\n' >"$work/prefix/other"
chmod 755 "$work/prefix/other"
ln -s ../other "$work/prefix/bin/remindctl"
before="$(snapshot)"
expect_fail install-fork.sh
expect_output "Refusing"
expect_fail rollback-fork.sh --apply
expect_output "neither ours nor from Homebrew"
expect_not_called "ran brew "
[[ "$(snapshot)" == "$before" ]] || fail "a foreign symlink was changed"
ok "install and rollback leave a foreign symlink alone"

make_target
expect_ok install-fork.sh --apply
printf '#!/bin/sh\necho 0.3.9\n' >"$work/prefix/Cellar/remindctl/0.3.8/bin/remindctl"
FAKE_BREW_VERSION=0.3.9 expect_ok rollback-fork.sh --apply
expect_output "remindctl --version: 0.3.9"
ok "rollback accepts whatever version Homebrew has installed when the binary matches it"

make_target
expect_ok install-fork.sh --apply
printf '#!/bin/sh\necho 0.3.7\n' >"$work/prefix/Cellar/remindctl/0.3.8/bin/remindctl"
expect_fail rollback-fork.sh --apply
expect_output "remindctl --version: 0.3.7"
expect_output "reports 0.3.7, but Homebrew has 0.3.8 installed"
ok "rollback fails when remindctl is not the version Homebrew has installed, naming both"

make_target
expect_ok install-fork.sh --apply
[[ "$(cat "$work/home/remindjoectl-releases/$version/COMMIT")" == "$(in_repo rev-parse HEAD)" ]] || fail "COMMIT is not the installed commit"
ok "install --apply records the commit next to the binary"

: >"$work/calls.log"
expect_ok install-fork.sh --apply
expect_output "same binary"
expect_called "scp "
ok "install --apply accepts a release folder that already holds the same binary"

release="$work/home/remindjoectl-releases/$version"
head_commit="$(in_repo rev-parse HEAD)"
printf '#!/bin/sh\necho earlier build\n' >"$release/remindjoectl"
chmod 755 "$release/remindjoectl"
printf '%s\n' 0000000000000000000000000000000000000000 >"$release/COMMIT"
before="$(snapshot)"
earlier="$(shasum "$release/remindjoectl")"
: >"$work/calls.log"
expect_fail install-fork.sh --apply
expect_output "Refusing"
expect_output "different binary"
expect_output "0000000000000000000000000000000000000000"
expect_output "Nothing on the target Mac has changed"
expect_not_called "scp "
expect_not_called "ran brew "
[[ "$(shasum "$release/remindjoectl")" == "$earlier" ]] || fail "the release binary was overwritten"
[[ "$(snapshot)" == "$before" ]] || fail "refusal changed the target Mac"
ok "install refuses a different binary whose COMMIT names another commit"

rm "$release/COMMIT"
before="$(snapshot)"
: >"$work/calls.log"
expect_fail install-fork.sh --apply
expect_output "Refusing"
expect_output "different binary"
expect_output "none recorded"
expect_not_called "scp "
expect_not_called "ran brew "
[[ "$(shasum "$release/remindjoectl")" == "$earlier" ]] || fail "the release binary was overwritten"
[[ ! -e "$release/COMMIT" ]] || fail "a refusal wrote COMMIT"
[[ "$(snapshot)" == "$before" ]] || fail "refusal changed the target Mac"
ok "install refuses a different binary when COMMIT is missing"

printf '%s\n' "$head_commit" >"$release/COMMIT"
: >"$work/calls.log"
expect_ok install-fork.sh --apply
expect_output "the same commit, built elsewhere; replacing it"
expect_called "scp "
[[ "$(shasum "$release/remindjoectl")" != "$earlier" ]] || fail "the release binary was not replaced"
[[ "$(cat "$release/COMMIT")" == "$head_commit" ]] || fail "COMMIT is not the installed commit"
[[ "$(readlink "$work/prefix/bin/remindctl")" == remindjoectl ]] || fail "rerun of the same commit did not install"
ok "install replaces a different binary when COMMIT names this same commit"

echo "# edited" >>"$work/repo/version.env"
make_target
expect_fail install-fork.sh
expect_output "Refusing"
expect_output "uncommitted changes"
expect_output "version.env"
expect_fail install-fork.sh --apply
expect_output "Refusing"
expect_not_called "ssh "
expect_not_called "swift "
expect_not_called "scp "
[[ ! -d "$work/home/remindjoectl-releases" ]] || fail "refusal made a release folder"
in_repo checkout -q -- version.env
ok "install refuses a tree with uncommitted changes, before touching the target Mac"

mkdir -p "$work/repo/Sources/remindctl"
echo "// stray" >"$work/repo/Sources/remindctl/Stray.swift"
make_target
expect_fail install-fork.sh
expect_output "Refusing"
expect_output "untracked"
expect_output "Sources/remindctl/Stray.swift"
expect_fail install-fork.sh --apply
expect_output "Refusing"
expect_not_called "ssh "
expect_not_called "swift "
expect_not_called "scp "
rm "$work/repo/Sources/remindctl/Stray.swift"
for name in Package.swift Package.resolved; do
  : >"$work/repo/$name"
  expect_fail install-fork.sh
  expect_output "Refusing"
  expect_output "untracked"
  expect_output "$name"
  rm "$work/repo/$name"
done
ok "install refuses untracked files under Sources/, Package.swift and Package.resolved, before touching the target Mac"

echo "bin/" >>"$work/repo/.git/info/exclude"
mkdir -p "$work/repo/Sources/remindctl/bin"
echo "// stray" >"$work/repo/Sources/remindctl/bin/Ignored.swift"
echo "junk" >"$work/repo/Sources/.DS_Store"
expect_fail install-fork.sh
expect_output "Refusing"
expect_output "Sources/remindctl/bin/Ignored.swift"
expect_fail install-fork.sh --apply
expect_not_called "ssh "
expect_not_called "swift "
rm "$work/repo/Sources/remindctl/bin/Ignored.swift"
expect_ok install-fork.sh
rm "$work/repo/Sources/.DS_Store"
: >"$work/repo/.git/info/exclude"
ok "install refuses a git-ignored source file under Sources/, but not a .DS_Store"

echo "scratch" >"$work/repo/scratch-notes.txt"
make_target
expect_ok install-fork.sh
expect_output "Dry run"
expect_ok install-fork.sh --apply
rm "$work/repo/scratch-notes.txt"
ok "install allows untracked files elsewhere"

in_repo commit -q --allow-empty -m "not reviewed"
make_target
expect_fail install-fork.sh
expect_output "Refusing"
expect_output "not on origin/main"
expect_fail install-fork.sh --apply
expect_output "Refusing"
expect_not_called "ssh "
expect_not_called "swift "
in_repo reset -q --hard origin/main
ok "install refuses a commit that is not on origin/main, before touching the target Mac"

in_repo commit -q --allow-empty -m "merged elsewhere"
in_repo push -q "$work/origin.git" HEAD:main
make_target
expect_ok install-fork.sh --apply
[[ "$(cat "$work/home/remindjoectl-releases/$version/COMMIT")" == "$(in_repo rev-parse HEAD)" ]] || fail "COMMIT is not the installed commit"
ok "install fetches origin before it decides a commit is on origin/main"

in_repo remote set-url origin "$work/missing.git"
make_target
expect_fail install-fork.sh --apply
expect_output "Refusing"
expect_output "fetch"
expect_not_called "ssh "
expect_not_called "swift "
in_repo remote set-url origin "$work/origin.git"
ok "install refuses when it cannot fetch origin"

make_target
expect_ok install-fork.sh --apply
before="$(snapshot)"
: >"$work/calls.log"
FAKE_BREW_FAIL="link" expect_fail rollback-fork.sh --apply
expect_called "ran brew link remindctl"
expect_output "Failed: "
expect_output "brew link remindctl failed"
expect_output "our remindctl link is back in place"
[[ "$(readlink "$work/prefix/bin/remindctl")" == remindjoectl ]] || fail "failed relink did not leave our remindctl link"
[[ "$(env -u REMINDCTL_VERSION "$work/prefix/bin/remindctl" --version)" == "$version" ]] || fail "remindctl does not run after the failed relink"
[[ "$(snapshot)" == "$before" ]] || fail "failed relink changed the target Mac"
expect_ok rollback-fork.sh --apply
expect_output "remindctl --version: 0.3.8"
ok "rollback with a failing brew link keeps our remindctl link working, and a rerun finishes"

make_target
FAKE_SCP_PARTIAL=1 expect_fail install-fork.sh --apply
expect_output "Only the release folder"
expect_not_called "ran brew "
[[ ! -e "$work/home/remindjoectl-releases/$version/remindjoectl" ]] || fail "a partial copy landed under the release binary's name"
expect_ok install-fork.sh --apply
[[ "$(readlink "$work/prefix/bin/remindctl")" == remindjoectl ]] || fail "rerun after a partial copy did not install"
expect_output "no binary there yet"
ok "an interrupted copy leaves no partial release binary, and the rerun installs"

make_target
expect_ok install-fork.sh --apply
before="$(snapshot)"
FAKE_BREW_LINK_NOOP=1 expect_fail rollback-fork.sh --apply
expect_output "our remindctl link is back in place"
[[ "$(readlink "$work/prefix/bin/remindctl")" == remindjoectl ]] || fail "a brew link that linked nothing removed our remindctl link"
[[ "$(snapshot)" == "$before" ]] || fail "failed relink changed the target Mac"
ok "rollback keeps our link when brew link exits 0 but links nothing"

make_target
in_repo commit -q --allow-empty -m "newer on origin"
in_repo push -q "$work/origin.git" HEAD:main
in_repo reset -q --hard HEAD~1
expect_ok install-fork.sh --apply
[[ "$(cat "$work/home/remindjoectl-releases/$version/COMMIT")" == "$(in_repo rev-parse HEAD)" ]] || fail "COMMIT is not the installed commit"
[[ "$(in_repo rev-parse HEAD)" != "$(in_repo rev-parse origin/main)" ]] || fail "origin/main did not move ahead of HEAD"
ok "install accepts an older commit that is already in origin/main"

expect_fail install-fork.sh --bogus
expect_output "Usage"
expect_fail install-fork.sh --apply --bogus
expect_output "Usage"
expect_fail rollback-fork.sh --apply --bogus
expect_output "Usage"
ok "rejects unknown and extra arguments"

echo "all $passed install-fork checks passed"
