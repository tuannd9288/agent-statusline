#!/usr/bin/env bash
# Render every example at several widths, then test the installer.
# Never touches your real ~/.claude: everything runs in a temporary HOME.
#
#   bash test/run.sh            # run all checks, print a short summary
#   bash test/run.sh --show     # also print the rendered lines (with colors)
#   WIDTHS="80 120 200" EXAMPLES="warm cold" bash test/run.sh --show

set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
show=0
[ "${1:-}" = "--show" ] && show=1

widths=${WIDTHS:-"30 50 80 100 120 150 200"}
examples=${EXAMPLES:-""}
if [ -z "$examples" ]; then
  for f in "$root"/examples/*.json; do
    n=${f##*/}; examples="$examples ${n%.json}"
  done
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/agent-statusline-test.XXXXXX")
trap 'rm -rf "$work"' EXIT

# A fake home with a neutral signed-in account, and a small git repo.
export HOME="$work/home"
export CLAUDE_CONFIG_DIR="$work/home/.claude"
unset AGENT_STATUSLINE_HIDE_ACCOUNT
mkdir -p "$CLAUDE_CONFIG_DIR" "$work/projects/my-app"
printf '{"oauthAccount":{"emailAddress":"alex@example.com"}}\n' > "$CLAUDE_CONFIG_DIR/.claude.json"
(
  cd "$work/projects/my-app" &&
  git init -q -b main . 2>/dev/null || git init -q . &&
  git -c user.name=test -c user.email=test@example.com commit -q --allow-empty -m init &&
  git branch -q -M main &&
  : > notes.txt   # untracked file -> dirty mark
)

# All examples are written relative to this moment.
export AGENT_STATUSLINE_NOW=1767000000

shells="bash"
# macOS ships bash 3.2 as /bin/bash; test with it too when it differs.
if [ -x /bin/bash ] && [ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" != "$(bash -c 'echo ${BASH_VERSINFO[0]}')" ]; then
  shells="bash /bin/bash"
fi

pass=0
failures=0
fail() { printf 'FAIL: %s\n' "$*"; failures=$((failures + 1)); }

for shell_bin in $shells; do
  for ex in $examples; do
    json="$root/examples/$ex.json"
    [ -f "$json" ] || { fail "missing example $ex"; continue; }
    # Point the example at the temp git repo. Invalid JSON is passed as is.
    if input=$(jq --arg d "$work/projects/my-app" \
      '.cwd = $d | .workspace.current_dir = $d | .workspace.project_dir = $d' "$json" 2>/dev/null); then
      has_cache=$(jq -r 'if (.prompt_cache | type) == "object" then 1 else 0 end' "$json")
    else
      input=$(cat "$json")
      has_cache=0
    fi
    for w in $widths; do
      out=$(printf '%s' "$input" | COLUMNS=$w "$shell_bin" "$root/claude/statusline.sh" 2>"$work/err")
      status=$?
      label="$ex @ ${w} cols ($shell_bin)"
      if [ "$status" -ne 0 ]; then fail "$label: exit $status"; continue; fi
      if [ -s "$work/err" ]; then fail "$label: stderr: $(cat "$work/err")"; continue; fi
      lines=$(printf '%s\n' "$out" | grep -c .)
      if [ "$lines" -lt 1 ]; then fail "$label: no output"; continue; fi
      if [ "$has_cache" = 0 ] && [ "$lines" -ne 1 ]; then fail "$label: expected 1 line, got $lines"; continue; fi
      if [ "$has_cache" = 1 ] && [ "$lines" -ne 2 ]; then fail "$label: expected 2 lines, got $lines"; continue; fi
      pass=$((pass + 1))
      if [ "$show" = 1 ] && [ "$shell_bin" = bash ]; then
        printf '\n── %s @ %s columns\n%s\n' "$ex" "$w" "$out"
      fi
    done
  done
done

# Content checks on the cache line (plain text, colors stripped).
plain() {
  { jq --arg d "$work/projects/my-app" '.cwd = $d | .workspace.current_dir = $d' "$root/examples/$1.json" 2>/dev/null \
      || cat "$root/examples/$1.json"; } \
    | COLUMNS=$2 bash "$root/claude/statusline.sh" | sed $'s/\033\\[[0-9;]*m//g'
}
expect() {
  local ex=$1 w=$2 pattern=$3
  if plain "$ex" "$w" | grep -qF -- "$pattern"; then pass=$((pass + 1))
  else fail "$ex @ $w: expected \"$pattern\" in: $(plain "$ex" "$w" | tr '\n' '|')"; fi
}
expect_not() {
  local ex=$1 w=$2 pattern=$3
  if plain "$ex" "$w" | grep -qF -- "$pattern"; then fail "$ex @ $w: did not expect \"$pattern\""
  else pass=$((pass + 1)); fi
}
expect warm 120 "cache ● 1h ███████░░░ 38m left · hit 91% · misses 0"
expect warm 120 "👤 alex"
expect warm 120 "▣ my-app · ⎇ main*"
expect about-to-expire 120 "9m left"
expect cold 120 "cache ○ cold · next message re-caches 82k tokens · last miss: ttl expired 5m"
expect cold 80 "cache ○ cold · next message re-caches 82k tokens"
expect_not cold 80 "last miss"
expect_not no-cache 200 "cache ●"
expect api-key-5m 120 "cache ● 5m"
expect_not full 200 "re-cache"
expect full 200 "⑂ #42"
expect full 200 "◇ fix login bug"
# Malformed fields: only the bad value (or the cache line) goes; line 1 stays whole.
full_line="◆ Opus 5.5 · high │ 👤 alex │ ▣ my-app · ⎇ main* │ ctx 42% used │ ◷ 5h 77% left │ ◷ 7d 59% left"
for ex in malformed-last-miss-cause malformed-ttl malformed-expires-at malformed-hit-ratio malformed-model; do
  expect "$ex" 120 "$full_line"
done
expect     malformed-last-miss-cause 120 "cache ○ cold · next message re-caches 82k tokens"
expect_not malformed-last-miss-cause 120 "last miss"
expect     malformed-ttl 120 "cache ● 38m left · hit 91% · misses 0"
expect     malformed-expires-at 120 "cache ● 1h · hit 91% · misses 0"
expect     malformed-hit-ratio 120 "cache ● 1h ███████░░░ 38m left · misses 0"
expect_not malformed-hit-ratio 120 "hit"
expect     malformed-rate-limits 120 "◆ Opus 5.5 · high │ 👤 alex │ ▣ my-app · ⎇ main* │ ctx 42% used │ ◷ 7d 59% left"
expect_not malformed-rate-limits 120 "5h"
expect     malformed-rate-limits 120 "cache ● 1h ███████░░░ 38m left"
expect     invalid 120 "◆ Claude │ 👤 alex"
# The exact case from the bug report.
if printf '%s' '{"model":{"display_name":"Opus 5.5"},"prompt_cache":{"warm":false,"last_miss_cause":"weird"}}' \
  | COLUMNS=150 bash "$root/claude/statusline.sh" 2>"$work/err" | head -1 | grep -qF "Opus 5.5" && [ ! -s "$work/err" ]; then
  pass=$((pass + 1)); else fail "bug repro: model name lost"; fi
# Any JSON type in any position: never an error, always a first line.
for bad in '"just a string"' '42' 'null' '[1,2,3]' '{"model":null}' '{"model":7,"effort":[],"workspace":"x","cwd":{}}' \
  '{"context_window":"full","rate_limits":[],"cost":{"total_cost_usd":"1"},"pr":{"number":"7"}}' \
  '{"context_window":{"used_percentage":1e40,"total_input_tokens":-5,"current_usage":{"cache_read_input_tokens":1e300}}}' \
  '{"prompt_cache":"warm"}' '{"prompt_cache":{"warm":"yes","ttl":true,"expires_at":-1,"misses":{},"recache_tokens_if_cold":"82k"}}' \
  '{"prompt_cache":{"warm":true,"ttl":"0m","expires_at":1767000100}}' '{"agent":{"name":["x"]},"session_name":{"a":1}}' ''; do
  for w in 30 80 200; do
    out=$(printf '%s' "$bad" | COLUMNS=$w bash "$root/claude/statusline.sh" 2>"$work/err"); status=$?
    if [ "$status" -eq 0 ] && [ ! -s "$work/err" ] && [ -n "$(printf '%s' "$out" | head -1)" ]; then
      pass=$((pass + 1))
    else
      fail "input $bad @ $w: exit $status, stderr: $(cat "$work/err"), out: $out"
    fi
  done
done
# Yellow (33m) when under 20% of the TTL is left, green (32m) otherwise.
if jq '.' "$root/examples/about-to-expire.json" | COLUMNS=120 bash "$root/claude/statusline.sh" | tail -1 | grep -q $'\033\\[33m'; then
  pass=$((pass + 1)); else fail "about-to-expire: cache line not yellow"; fi
if jq '.' "$root/examples/warm.json" | COLUMNS=120 bash "$root/claude/statusline.sh" | tail -1 | grep -q $'\033\\[32m'; then
  pass=$((pass + 1)); else fail "warm: cache line not green"; fi
# A warm cache whose time has passed is shown as cold.
if jq '.prompt_cache.expires_at = 1766999000' "$root/examples/warm.json" | COLUMNS=120 bash "$root/claude/statusline.sh" \
  | grep -qF "cold"; then pass=$((pass + 1)); else fail "expired warm cache not shown as cold"; fi
# Hiding the account.
if jq '.' "$root/examples/warm.json" | AGENT_STATUSLINE_HIDE_ACCOUNT=1 COLUMNS=200 bash "$root/claude/statusline.sh" \
  | grep -qF "👤"; then fail "AGENT_STATUSLINE_HIDE_ACCOUNT=1 still shows account"; else pass=$((pass + 1)); fi
# Garbage input must not crash.
if printf 'not json' | COLUMNS=120 bash "$root/claude/statusline.sh" >/dev/null 2>"$work/err" && [ ! -s "$work/err" ]; then
  pass=$((pass + 1)); else fail "invalid JSON input produced an error"; fi

printf '\nrender checks: %s passed, %s failed\n' "$pass" "$failures"

# Installer tests (separate temp HOME).
if ! bash "$root/test/install-test.sh"; then
  failures=$((failures + 1))
fi

if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck -s bash "$root"/claude/*.sh "$root"/test/*.sh; then
    printf 'shellcheck: clean\n'
  else
    fail "shellcheck reported problems"
  fi
else
  printf 'shellcheck: not installed, skipped\n'
fi

if [ "$failures" -gt 0 ]; then
  printf '\n%s FAILURE(S)\n' "$failures"
  exit 1
fi
printf '\nALL TESTS PASSED\n'
