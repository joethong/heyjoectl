#!/usr/bin/env bash
# shellcheck disable=SC2029 # remote commands expand our local paths on purpose
set -euo pipefail

HOST="${REMINDJOECTL_HOST:-}"
[[ -n $HOST ]] || { echo "Refusing: set REMINDJOECTL_HOST to the target Mac's SSH host, for example REMINDJOECTL_HOST=my-mac $0" >&2; exit 2; }
BREW=/opt/homebrew/bin/brew
BIN=/opt/homebrew/bin

usage() {
  echo "Usage: scripts/rollback-fork.sh [--apply]" >&2
  echo "Without --apply it only prints the steps." >&2
  exit 2
}
[[ $# -le 1 ]] || usage
case "${1:-}" in
  "") APPLY=0 ;;
  --apply) APPLY=1 ;;
  *) usage ;;
esac

die() {
  echo >&2
  echo "Failed: $1" >&2
  echo "Stopped here; no later step ran. Fix the cause and run scripts/rollback-fork.sh --apply again; every step is safe to repeat." >&2
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

if [[ $APPLY == 1 ]]; then
  echo "Rolling $HOST back to Homebrew's remindctl."
else
  echo "Dry run: rolling $HOST back to Homebrew's remindctl. Nothing is changed; run with --apply to do it."
fi

step "Relink Homebrew's remindctl, then remove our link (ours stays if the relink fails)" ssh "$HOST" \
  "set -e; case \"\$(readlink $BIN/remindctl)\" in remindjoectl) mv $BIN/remindctl $BIN/.remindctl-ours; if $BREW link remindctl && case \"\$(readlink $BIN/remindctl)\" in ../Cellar/remindctl/*) true ;; *) false ;; esac; then rm $BIN/.remindctl-ours; else mv $BIN/.remindctl-ours $BIN/remindctl; echo 'brew link remindctl failed; our remindctl link is back in place and still works' >&2; exit 1; fi ;; ../Cellar/remindctl/*) ;; *) if [ -e $BIN/remindctl ] || [ -L $BIN/remindctl ]; then echo '$BIN/remindctl is neither ours nor from Homebrew, left alone' >&2; exit 1; fi; $BREW link remindctl ;; esac"
step "Remove $BIN/remindjoectl (release folders are kept)" ssh "$HOST" \
  "rm -f $BIN/remindjoectl"
step "Let Homebrew upgrade remindctl again" ssh "$HOST" \
  "set -e; pinned=\$($BREW list --pinned); if printf '%s\\n' \"\$pinned\" | grep -qx remindctl; then $BREW unpin remindctl; fi"

echo
echo "==> Check remindctl on $HOST is Homebrew's, at the version Homebrew has installed"
echo "    \$ ssh $HOST readlink $BIN/remindctl; ssh $HOST $BREW list --versions remindctl; ssh $HOST env -u REMINDCTL_VERSION $BIN/remindctl --version"
if [[ $APPLY == 1 ]]; then
  target="$(ssh "$HOST" "readlink $BIN/remindctl")" || die "$BIN/remindctl on $HOST is not a link"
  [[ $target == ../Cellar/remindctl/* ]] || die "$BIN/remindctl on $HOST points to $target, not Homebrew's remindctl"
  listed="$(ssh "$HOST" "$BREW list --versions remindctl")" || die "could not run brew list --versions remindctl on $HOST"
  [[ $listed =~ ^remindctl\ ([^\ ]+)$ ]] || die "expected one Homebrew version of remindctl on $HOST, brew lists: $listed"
  expected="${BASH_REMATCH[1]}"
  got="$(ssh "$HOST" "env -u REMINDCTL_VERSION $BIN/remindctl --version")" || die "could not run remindctl --version on $HOST"
  echo "    remindctl --version: $got"
  [[ $got == "$expected" ]] || die "remindctl on $HOST reports $got, but Homebrew has $expected installed"
  echo
  echo "Done. remindctl on $HOST is Homebrew's again."
fi
