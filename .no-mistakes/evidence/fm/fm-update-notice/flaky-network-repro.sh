#!/usr/bin/env bash
# Operator-level reproduction of the reported symptom: the firstmate update
# notice repeating every time the network flaps. One watched tool (firstmate,
# a git source two commits behind its origin branch), eight watcher sweeps,
# with the remote unreachable on the sweeps marked "network down". What the
# operator would see on each sweep is printed verbatim.
#
# Usage: flaky-network-repro.sh <path-to-fm-tool-update-check.sh> <label>
set -u
CHECK=$1
LABEL=$2
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/flaky-repro.XXXXXX")
export GIT_AUTHOR_NAME=fmtest GIT_AUTHOR_EMAIL=fmtest@example.invalid
export GIT_COMMITTER_NAME=fmtest GIT_COMMITTER_EMAIL=fmtest@example.invalid

HOME_DIR="$ROOT/home"; mkdir -p "$HOME_DIR/state" "$HOME_DIR/config"
BARE="$ROOT/firstmate.git"; WORK="$ROOT/firstmate"
git init -q --bare --initial-branch=main "$BARE"
git clone -q "$BARE" "$WORK" 2>/dev/null
for n in one two three; do printf '%s\n' "$n" > "$WORK/$n"; git -C "$WORK" add "$n"; git -C "$WORK" commit -qm "$n"; done
git -C "$WORK" push -q origin main
git -C "$WORK" remote set-head origin main >/dev/null 2>&1
git -C "$WORK" reset -q --hard HEAD~2   # the clone is two commits behind origin/main

# A git wrapper that refuses network reads while the flag file exists, the way
# an unreachable remote does.
SHIM="$ROOT/bin"; mkdir -p "$SHIM"
REAL_GIT=$(command -v git)
cat > "$SHIM/git" <<SH
#!/usr/bin/env bash
if [ -e '$ROOT/offline' ]; then
  for arg in "\$@"; do
    if [ "\$arg" = ls-remote ]; then
      printf 'fatal: could not read from remote repository\n' >&2
      exit 128
    fi
  done
fi
exec $REAL_GIT "\$@"
SH
chmod 0755 "$SHIM/git"

printf '{"tools":[{"name":"firstmate","git":{"repo":"%s","remote":"origin","branch":"main"}}]}\n' \
  "$WORK" > "$HOME_DIR/config/watched-tools.json"

printf '=== %s ===\n' "$LABEL"
notices=0
for sweep in 1 2 3 4 5 6 7 8; do
  case $sweep in
    3|4|6) touch "$ROOT/offline"; state='network down' ;;
    *)     rm -f "$ROOT/offline"; state='network up  ' ;;
  esac
  out=$(env FM_CHECK_TIMEOUT=30 FM_HOME="$HOME_DIR" PATH="$SHIM:$PATH" \
            FM_TOOL_UPDATE_INTERVAL=0 "$CHECK" 2>&1)
  if [ -n "$out" ]; then
    notices=$((notices + 1))
    printf 'sweep %d (%s): %s\n' "$sweep" "$state" "${out//$WORK/<repo>}"
  else
    printf 'sweep %d (%s): (nothing shown to the operator)\n' "$sweep" "$state"
  fi
done
printf -- '-- %d notice(s) shown across 8 sweeps for one unchanged pending update\n\n' "$notices"
rm -rf "$ROOT"
