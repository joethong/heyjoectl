#!/usr/bin/env bash
# shellcheck disable=SC2029 # remote commands expand our local paths on purpose
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOST="${REMINDJOECTL_HOST:-}"
[[ -n $HOST ]] || { echo "Refusing: set REMINDJOECTL_HOST to the target Mac's SSH host, for example REMINDJOECTL_HOST=my-mac $0" >&2; exit 2; }
BREW=/opt/homebrew/bin/brew
BIN=/opt/homebrew/bin
BUILT="<swift build --show-bin-path>/remindctl"

# shellcheck source=version.env
source "$ROOT/version.env"
# shellcheck source=fork-version.env
source "$ROOT/fork-version.env"
VERSION="${MARKETING_VERSION}-joe.${FORK_RELEASE}"
RELEASE_DIR="remindjoectl-releases/$VERSION"

usage() {
  echo "Usage: scripts/install-fork.sh [--apply]" >&2
  echo "Without --apply it only prints the steps." >&2
  exit 2
}
[[ $# -le 1 ]] || usage
case "${1:-}" in
  "") APPLY=0 ;;
  --apply) APPLY=1 ;;
  *) usage ;;
esac

UNDO="Nothing on the target Mac has changed."

die() {
  echo >&2
  echo "Failed: $1" >&2
  echo "Stopped here; no later step ran. $UNDO" >&2
  exit 1
}

step() {
  local desc=$1
  shift
  echo
  echo "==> $desc"
  echo "    \$ $*"
  [[ $APPLY == 1 ]] || return 0
  "$@" || die "$desc"
}

refuse() {
  echo >&2
  echo "Refusing: $1" >&2
  echo "$UNDO" >&2
  exit 1
}

check_target_version() {
  local path=$1 got
  echo
  echo "==> Check $path on $HOST reports $VERSION"
  echo "    \$ ssh $HOST env -u REMINDCTL_VERSION $path --version"
  [[ $APPLY == 1 ]] || return 0
  got="$(ssh "$HOST" "env -u REMINDCTL_VERSION $path --version")" || die "could not run $path --version on $HOST"
  echo "    $path --version: $got"
  [[ $got == "$VERSION" ]] || die "$path on $HOST reports $got, expected $VERSION"
}

cd "$ROOT"

if [[ $APPLY == 1 ]]; then
  echo "Installing remindjoectl $VERSION on $HOST."
else
  echo "Dry run: installing remindjoectl $VERSION on $HOST. Nothing is changed; run with --apply to do it."
fi

echo
echo "==> Check the tree is clean and its commit is on origin/main"
echo "    \$ git status --porcelain --untracked-files=no; git ls-files --others -- Sources Package.swift Package.resolved; git fetch origin; git merge-base --is-ancestor HEAD origin/main"
dirty="$(git status --porcelain --untracked-files=no)" || refuse "could not read the git status of $ROOT"
[[ -z $dirty ]] || refuse "tracked files have uncommitted changes. Commit them through a reviewed pull request first:
$dirty"
untracked="$(git ls-files --others -- Sources Package.swift Package.resolved ':(exclude,glob)**/.DS_Store')" || refuse "could not read the git status of $ROOT"
[[ -z $untracked ]] || refuse "untracked or git-ignored files would be built into the binary. Commit them through a reviewed pull request, or move them out of the way:
$untracked"
git fetch --quiet origin || refuse "could not fetch origin, so I can't tell whether this commit is reviewed"
COMMIT="$(git rev-parse HEAD)"
git merge-base --is-ancestor "$COMMIT" origin/main || refuse "commit $COMMIT is not on origin/main. Merge it through a pull request, pull main, and run this from there"
echo "    commit $COMMIT is on origin/main"

echo
echo "==> Check what $BIN/remindctl is on $HOST (read only)"
state="$(ssh "$HOST" "
  if [ -L $BIN/remindctl ]; then
    case \"\$(readlink $BIN/remindctl)\" in
      remindjoectl) echo ours ;;
      ../Cellar/remindctl/*) echo homebrew ;;
      *) echo foreign ;;
    esac
  elif [ -e $BIN/remindctl ]; then
    echo foreign
  else
    echo absent
  fi
")" || die "could not read $BIN/remindctl on $HOST"
echo "    $BIN/remindctl is: $state"
if [[ $state != homebrew && $state != ours && $state != absent ]]; then
  echo >&2
  echo "Refusing: $BIN/remindctl on $HOST is neither Homebrew's link nor ours. Nothing was changed." >&2
  exit 1
fi

step "Write the version into the sources ($VERSION)" scripts/generate-version.sh
step "Build the release binary for arm64" swift build -c release --arch arm64 --product remindctl
if [[ $APPLY == 1 ]]; then
  bin_dir="$(swift build -c release --arch arm64 --product remindctl --show-bin-path)" || die "could not ask swift where it put the binary"
  BUILT="$bin_dir/remindctl"
  [[ -x $BUILT ]] || die "swift says the binary is at $BUILT, but it isn't there"
fi
step "Sign it ad hoc" codesign --force --sign - --identifier com.steipete.remindctl "$BUILT"

echo
echo "==> Check the built binary reports $VERSION"
echo "    \$ $BUILT --version"
if [[ $APPLY == 1 ]]; then
  built_version="$(env -u REMINDCTL_VERSION "$BUILT" --version)" || die "could not run $BUILT --version"
  echo "    $BUILT --version: $built_version"
  [[ $built_version == "$VERSION" ]] || die "the built binary reports $built_version, expected $VERSION"
fi

echo
echo "==> Check ~/$RELEASE_DIR on $HOST holds no different binary"
echo "    \$ ssh $HOST shasum -a 256 $RELEASE_DIR/remindjoectl; ssh $HOST cat $RELEASE_DIR/COMMIT"
if [[ $APPLY == 1 ]]; then
  built_sum="$(shasum -a 256 "$BUILT")" || die "could not checksum $BUILT"
  built_sum="${built_sum%% *}"
  there_sum="$(ssh "$HOST" "if [ -e $RELEASE_DIR/remindjoectl ]; then shasum -a 256 $RELEASE_DIR/remindjoectl; fi")" || die "could not checksum ~/$RELEASE_DIR/remindjoectl on $HOST"
  there_sum="${there_sum%% *}"
  if [[ -z $there_sum ]]; then
    echo "    no binary there yet"
  elif [[ $there_sum == "$built_sum" ]]; then
    echo "    the same binary is already there (a rerun)"
  else
    there_commit="$(ssh "$HOST" "if [ -f $RELEASE_DIR/COMMIT ]; then cat $RELEASE_DIR/COMMIT; fi")" || die "could not read ~/$RELEASE_DIR/COMMIT on $HOST"
    if [[ $there_commit == "$COMMIT" ]]; then
      echo "    the same commit, built elsewhere; replacing it"
    else
      refuse '~'"/$RELEASE_DIR on $HOST already holds a different binary (sha256 $there_sum; this build is $built_sum), recorded for commit ${there_commit:-none recorded}. Raise FORK_RELEASE in fork-version.env through a reviewed pull request, or remove that folder on the target Mac yourself if you are sure it was never installed."
    fi
  fi
fi

UNDO="Only the release folder ~/$RELEASE_DIR on the target Mac may have changed; nothing in $BIN has. Rerunning is safe."
step "Make the release folder ~/$RELEASE_DIR on $HOST" ssh "$HOST" "mkdir -p $RELEASE_DIR"
step "Copy the binary to it, under a temporary name" scp "$BUILT" "$HOST:$RELEASE_DIR/remindjoectl.partial"
step "Move it into place" ssh "$HOST" "chmod 755 $RELEASE_DIR/remindjoectl.partial && mv -f $RELEASE_DIR/remindjoectl.partial $RELEASE_DIR/remindjoectl"
step "Record the commit next to it" ssh "$HOST" "printf '%s\\n' $COMMIT >$RELEASE_DIR/COMMIT"
check_target_version "$RELEASE_DIR/remindjoectl"

UNDO="To undo, run: scripts/rollback-fork.sh --apply"
step "Stop Homebrew upgrading remindctl" ssh "$HOST" \
  "set -e; pinned=\$($BREW list --pinned); if ! printf '%s\\n' \"\$pinned\" | grep -qx remindctl; then $BREW pin remindctl; fi"
step "Install it as $BIN/remindjoectl" ssh "$HOST" \
  "install -m 755 $RELEASE_DIR/remindjoectl $BIN/remindjoectl"
step "Unlink Homebrew's remindctl (kept installed) and point remindctl at ours" ssh "$HOST" \
  "case \"\$(readlink $BIN/remindctl)\" in ../Cellar/*) $BREW unlink remindctl ;; esac && ln -sf remindjoectl $BIN/remindctl"

check_target_version "$BIN/remindctl"
check_target_version "$BIN/remindjoectl"
if [[ $APPLY == 1 ]]; then
  echo
  echo "Done. remindctl on $HOST is now remindjoectl $VERSION."
fi
echo "To undo: scripts/rollback-fork.sh (dry run), then scripts/rollback-fork.sh --apply"
