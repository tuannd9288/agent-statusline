#!/usr/bin/env bash
# Installer tests. Each case gets a fresh temporary HOME and CLAUDE_CONFIG_DIR,
# so your real ~/.claude is never read or changed.
# shellcheck disable=SC2016,SC2034  # checks are eval-ed strings on purpose

set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installer="$root/claude/install.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/agent-statusline-install.XXXXXX")
trap 'rm -rf "$work"' EXIT

pass=0
failures=0
ok()   { pass=$((pass + 1)); }
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }
check() { if eval "$2"; then ok; else fail "$1"; fi; }

case_n=0
new_home() {
  case_n=$((case_n + 1))
  export HOME="$work/case$case_n"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  mkdir -p "$HOME"
}
run() { bash "$installer" "$@" >"$work/out" 2>&1; }
# Snapshot of a directory: every file's path and checksum, excluding nothing.
snapshot() { (cd "$1" && find . -type f -o -type l | LC_ALL=C sort | while IFS= read -r f; do
  printf '%s %s\n' "$f" "$(cksum < "$f")"; done); }
cmd_of() { jq -r '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json"; }

# 1. Fresh install: nothing exists yet.
new_home
run;                                         check "fresh: exit 0" '[ $? -eq 0 ]'
check "fresh: script installed"              '[ -x "$CLAUDE_CONFIG_DIR/statusline.sh" ]'
check "fresh: settings created"              '[ -f "$CLAUDE_CONFIG_DIR/settings.json" ]'
check "fresh: statusLine object" \
  'jq -e --arg c "$CLAUDE_CONFIG_DIR/statusline.sh" ".statusLine == {type:\"command\",command:\$c,padding:0,refreshInterval:30}" "$CLAUDE_CONFIG_DIR/settings.json" >/dev/null'
check "fresh: backup records no previous statusLine" \
  '[ "$(cat "$CLAUDE_CONFIG_DIR"/agent-statusline-backups/*/statusLine.json)" = null ]'

# 2. Idempotent: second run changes nothing.
before=$(snapshot "$HOME")
run;                                         check "idempotent: exit 0" '[ $? -eq 0 ]'
after=$(snapshot "$HOME")
check "idempotent: no file changed"          '[ "$before" = "$after" ]'
check "idempotent: says up to date"          'grep -q "up to date" "$work/out"'

# 3. Uninstall after a fresh install removes everything we added.
run --uninstall;                             check "fresh uninstall: exit 0" '[ $? -eq 0 ]'
check "fresh uninstall: script removed"      '[ ! -e "$CLAUDE_CONFIG_DIR/statusline.sh" ]'
check "fresh uninstall: settings removed (was absent)" '[ ! -e "$CLAUDE_CONFIG_DIR/settings.json" ]'

# 4. Existing setup: custom script, other settings, own statusLine.
new_home
mkdir -p "$CLAUDE_CONFIG_DIR"
printf '#!/bin/sh\necho my own line\n' > "$CLAUDE_CONFIG_DIR/statusline.sh"
cat > "$CLAUDE_CONFIG_DIR/settings.json" <<'JSON'
{
  "model": "opus",
  "permissions": { "allow": ["Bash(ls:*)"] },
  "statusLine": { "type": "command", "command": "~/.claude/statusline.sh", "padding": 2 },
  "env": { "FOO": "bar" }
}
JSON
orig_settings=$(jq -S . "$CLAUDE_CONFIG_DIR/settings.json")
orig_script=$(cat "$CLAUDE_CONFIG_DIR/statusline.sh")
run;                                         check "existing: exit 0" '[ $? -eq 0 ]'
check "existing: other keys kept" \
  '[ "$(jq -S "del(.statusLine)" "$CLAUDE_CONFIG_DIR/settings.json")" = "$(printf "%s" "$orig_settings" | jq -S "del(.statusLine)")" ]'
check "existing: refreshInterval 30"         '[ "$(jq .statusLine.refreshInterval "$CLAUDE_CONFIG_DIR/settings.json")" = 30 ]'
check "existing: script backed up" \
  '[ "$(cat "$CLAUDE_CONFIG_DIR"/agent-statusline-backups/*/statusline.sh)" = "$orig_script" ]'
check "existing: statusLine backed up" \
  '[ "$(jq -c . "$CLAUDE_CONFIG_DIR"/agent-statusline-backups/*/statusLine.json)" = "{\"type\":\"command\",\"command\":\"~/.claude/statusline.sh\",\"padding\":2}" ]'

# 5. Re-install (e.g. an upgrade) does not create a second backup.
run
check "reinstall: still one backup"          '[ "$(ls "$CLAUDE_CONFIG_DIR/agent-statusline-backups" | wc -l | tr -d " ")" = 1 ]'

# 6. Uninstall restores the original exactly.
run --uninstall;                             check "restore: exit 0" '[ $? -eq 0 ]'
check "restore: script restored"             '[ "$(cat "$CLAUDE_CONFIG_DIR/statusline.sh")" = "$orig_script" ]'
check "restore: settings restored"           '[ "$(jq -S . "$CLAUDE_CONFIG_DIR/settings.json")" = "$orig_settings" ]'
run --uninstall
check "restore twice: nothing to do"         'grep -q "not installed" "$work/out"'

# 7. Missing jq: prints how to install it and changes nothing.
new_home
bin="$work/bin-nojq"; mkdir -p "$bin"
for t in bash sh git cat grep sed mkdir mktemp rm cp mv chmod date uname cmp dirname tr ls find; do
  p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$bin/$t"
done
PATH="$bin" "$bin/bash" "$installer" >"$work/out" 2>&1
check "no jq: exit 1"                        '[ $? -eq 1 ]'
check "no jq: names jq"                      'grep -q "install -y jq\|brew install jq\|Install \"jq\"" "$work/out"'
check "no jq: nothing written"               '[ ! -e "$CLAUDE_CONFIG_DIR" ]'

# 8. Invalid settings.json: stop without changing anything.
new_home
mkdir -p "$CLAUDE_CONFIG_DIR"; printf '{ broken' > "$CLAUDE_CONFIG_DIR/settings.json"
run
check "bad json: non-zero exit"              '[ $? -ne 0 ]'
check "bad json: file untouched"             '[ "$(cat "$CLAUDE_CONFIG_DIR/settings.json")" = "{ broken" ]'
check "bad json: no script written"          '[ ! -e "$CLAUDE_CONFIG_DIR/statusline.sh" ]'

# 9. Piped through bash (the curl | bash path), served from a local copy.
new_home
serve="$work/serve/claude"; mkdir -p "$serve"; cp "$root/claude/statusline.sh" "$serve/"
AGENT_STATUSLINE_BASE_URL="file://$work/serve" bash < "$installer" >"$work/out" 2>&1
check "piped: exit 0"                        '[ $? -eq 0 ]'
check "piped: script installed"              'cmp -s "$CLAUDE_CONFIG_DIR/statusline.sh" "$root/claude/statusline.sh"'

# 10. Default config dir (~/.claude) when CLAUDE_CONFIG_DIR is not set.
new_home
( unset CLAUDE_CONFIG_DIR; bash "$installer" >"$work/out" 2>&1 )
check "default dir: installed in ~/.claude"  '[ -x "$HOME/.claude/statusline.sh" ] && [ "$(jq -r .statusLine.command "$HOME/.claude/settings.json")" = "$HOME/.claude/statusline.sh" ]'

# 11. Symlinked settings.json stays a symlink.
new_home
mkdir -p "$CLAUDE_CONFIG_DIR" "$HOME/dotfiles"
printf '{"theme":"dark"}\n' > "$HOME/dotfiles/settings.json"
ln -s "$HOME/dotfiles/settings.json" "$CLAUDE_CONFIG_DIR/settings.json"
run
check "symlink: still a symlink"             '[ -L "$CLAUDE_CONFIG_DIR/settings.json" ]'
check "symlink: target updated"              '[ "$(jq -r .theme "$HOME/dotfiles/settings.json")" = dark ] && [ "$(cmd_of)" = "$CLAUDE_CONFIG_DIR/statusline.sh" ]'

# 12. bash 3.2 (macOS /bin/bash) runs the installer too.
if [ -x /bin/bash ] && [ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" = 3 ]; then
  new_home
  /bin/bash "$installer" >"$work/out" 2>&1
  check "bash 3.2: install"                  '[ $? -eq 0 ] && [ -x "$CLAUDE_CONFIG_DIR/statusline.sh" ]'
  /bin/bash "$installer" --uninstall >"$work/out" 2>&1
  check "bash 3.2: uninstall"                '[ $? -eq 0 ] && [ ! -e "$CLAUDE_CONFIG_DIR/statusline.sh" ]'
fi

printf 'installer checks: %s passed, %s failed\n' "$pass" "$failures"
[ "$failures" -eq 0 ]
