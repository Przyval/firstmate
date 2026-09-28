#!/usr/bin/env bash
# The other half of the intent: suppressing the repeat must not make the check go
# quiet. Same operator home as flaky-network-repro.sh. A link that stays down is
# still reported (once), and a pending update that actually changes is news again.
set -u
CHECK=$1
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/news-repro.XXXXXX")
export GIT_AUTHOR_NAME=fmtest GIT_AUTHOR_EMAIL=fmtest@example.invalid
export GIT_COMMITTER_NAME=fmtest GIT_COMMITTER_EMAIL=fmtest@example.invalid
HOME_DIR="$ROOT/home"; mkdir -p "$HOME_DIR/state" "$HOME_DIR/config"
BARE="$ROOT/firstmate.git"; WORK="$ROOT/firstmate"
git init -q --bare --initial-branch=main "$BARE"; git clone -q "$BARE" "$WORK" 2>/dev/null
for n in one two three; do printf '%s\n' "$n" > "$WORK/$n"; git -C "$WORK" add "$n"; git -C "$WORK" commit -qm "$n"; done
git -C "$WORK" push -q origin main; git -C "$WORK" remote set-head origin main >/dev/null 2>&1
git -C "$WORK" reset -q --hard HEAD~2
SHIM="$ROOT/bin"; mkdir -p "$SHIM"; REAL_GIT=$(command -v git)
cat > "$SHIM/git" <<SH
#!/usr/bin/env bash
if [ -e '$ROOT/offline' ]; then
  for arg in "\$@"; do
    if [ "\$arg" = ls-remote ]; then printf 'fatal: could not read from remote repository\n' >&2; exit 128; fi
  done
fi
exec $REAL_GIT "\$@"
SH
chmod 0755 "$SHIM/git"
printf '{"tools":[{"name":"firstmate","git":{"repo":"%s","remote":"origin","branch":"main"}}]}\n' "$WORK" > "$HOME_DIR/config/watched-tools.json"
sweep() {
  local note=$1 out
  out=$(env FM_CHECK_TIMEOUT=30 FM_HOME="$HOME_DIR" PATH="$SHIM:$PATH" FM_TOOL_UPDATE_INTERVAL=0 "$CHECK" 2>&1)
  printf '%-34s %s\n' "$note" "${out:-(nothing shown to the operator)}" | sed "s#$WORK#<repo>#g"
}
printf '=== still reports real news (HEAD) ===\n'
sweep 'network up, update pending:'
rm -f "$ROOT/offline"
touch "$ROOT/offline"
sweep 'outage sweep 1:'
sweep 'outage sweep 2:'
sweep 'outage sweep 3:'
sweep 'outage sweep 4:'
rm -f "$ROOT/offline"
git -C "$WORK" reset -q --hard origin/main~1   # the pending update actually changes
sweep 'network back, update changed:'
rm -rf "$ROOT"
