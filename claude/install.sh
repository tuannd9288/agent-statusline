#!/usr/bin/env bash
# agent-statusline installer for Claude Code
# https://github.com/tuannd9288/agent-statusline (MIT)
#
# Install:    curl -fsSL https://raw.githubusercontent.com/tuannd9288/agent-statusline/main/claude/install.sh | bash
# Uninstall:  curl -fsSL https://raw.githubusercontent.com/tuannd9288/agent-statusline/main/claude/install.sh | bash -s -- --uninstall
# From a clone: bash claude/install.sh [--uninstall]
#
# What it does:
#   1. Copies statusline.sh into your Claude config folder (~/.claude, or
#      $CLAUDE_CONFIG_DIR if you set it).
#   2. Points the "statusLine" setting in settings.json at it, keeping every
#      other setting as it was.
#   3. Before changing anything the first time, saves your current status line
#      script and setting into a timestamped backup folder. --uninstall puts
#      them back.
# It never installs software, never touches anything else, and running it twice
# changes nothing the second time.

set -eu

MARKER="# agent-statusline: Claude Code status line"
BASE_URL=${AGENT_STATUSLINE_BASE_URL:-https://raw.githubusercontent.com/tuannd9288/agent-statusline/main}

say()  { printf '%s\n' "$*"; }
fail() { printf 'agent-statusline: %s\n' "$*" >&2; exit 1; }

mode=install
for arg in "$@"; do
  case $arg in
    --uninstall) mode=uninstall ;;
    -h|--help)
      sed -n '2,19p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) fail "unknown option: $arg (use --uninstall or --help)" ;;
  esac
done

# ── Requirements ──────────────────────────────────────────────────────────────
# We never install packages for you. If something is missing, we say exactly
# what to run and stop.
install_hint() {
  local pkg=$1
  if [ "$(uname -s)" = "Darwin" ]; then
    if command -v brew >/dev/null 2>&1; then
      say "    brew install $pkg"
    else
      say "    Install Homebrew first (https://brew.sh), then run:"
      say "    brew install $pkg"
    fi
  elif command -v apt-get >/dev/null 2>&1; then
    say "    sudo apt-get install -y $pkg"
  elif command -v dnf >/dev/null 2>&1; then
    say "    sudo dnf install -y $pkg"
  elif command -v pacman >/dev/null 2>&1; then
    say "    sudo pacman -S $pkg"
  else
    say "    Install \"$pkg\" with your system's package manager."
  fi
}

missing=""
for tool in jq git; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  say "agent-statusline needs these programs, which are not installed:$missing"
  say ""
  for tool in $missing; do
    say "  To install $tool, run:"
    install_hint "$tool"
  done
  say ""
  say "Then run this installer again. Nothing was changed."
  exit 1
fi

# ── Paths ─────────────────────────────────────────────────────────────────────
config_dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
config_dir=${config_dir%/}
script_path="$config_dir/statusline.sh"
settings="$config_dir/settings.json"
backup_root="$config_dir/agent-statusline-backups"

case $script_path in
  *[[:space:]]*) command_value="\"$script_path\"" ;;
  *) command_value=$script_path ;;
esac

desired=$(jq -cn --arg cmd "$command_value" \
  '{type:"command",command:$cmd,padding:0,refreshInterval:30}')

is_ours() { [ -f "$1" ] && grep -qF "$MARKER" "$1"; }

# Write $2 into $1 without replacing the file itself (keeps symlinks and
# permissions, e.g. a settings.json managed by a dotfiles repo).
write_over() {
  local target=$1 source=$2
  if [ -e "$target" ]; then
    cat "$source" > "$target"
  else
    cp "$source" "$target"
  fi
}

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/agent-statusline.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

read_settings() {
  if [ -f "$settings" ]; then
    if [ ! -s "$settings" ]; then
      printf '{}'
    elif ! jq -e 'type == "object"' "$settings" >/dev/null 2>&1; then
      fail "$settings is not valid JSON. Fix it (or move it away) and run again. Nothing was changed."
    else
      cat "$settings"
    fi
  else
    printf '{}'
  fi
}

# ── Uninstall ─────────────────────────────────────────────────────────────────
if [ "$mode" = uninstall ]; then
  current=$(read_settings)
  latest=""
  if [ -d "$backup_root" ]; then
    # Timestamped names sort in time order; take the newest.
    for d in "$backup_root"/*/; do
      d=${d%/}
      case $d in *.restored) continue ;; esac
      [ -d "$d" ] && latest=$d
    done
  fi

  if [ -z "$latest" ] && ! is_ours "$script_path"; then
    say "agent-statusline is not installed in $config_dir. Nothing to do."
    exit 0
  fi

  if [ -n "$latest" ]; then
    say "Restoring your previous status line from $latest"
    if [ -f "$latest/statusline.sh" ]; then
      cp -p "$latest/statusline.sh" "$script_path"
    elif is_ours "$script_path"; then
      rm -f "$script_path"
    fi
    previous=$(cat "$latest/statusLine.json")
    printf '%s' "$current" | jq --argjson prev "$previous" \
      'if $prev == null then del(.statusLine) else .statusLine = $prev end' > "$tmp_dir/settings.json"
    mv "$latest" "$latest.restored"
  else
    say "No backup found; removing agent-statusline."
    rm -f "$script_path"
    printf '%s' "$current" | jq --arg cmd "$command_value" \
      'if .statusLine.command == $cmd then del(.statusLine) else . end' > "$tmp_dir/settings.json"
  fi

  if [ -f "$settings" ]; then
    if [ -n "$latest" ] && [ -f "$latest.restored/settings-was-absent" ] \
      && jq -e '. == {}' "$tmp_dir/settings.json" >/dev/null; then
      rm -f "$settings"
    elif ! printf '%s' "$current" | jq -e --slurpfile new "$tmp_dir/settings.json" '. == $new[0]' >/dev/null; then
      write_over "$settings" "$tmp_dir/settings.json"
    fi
  fi
  say "Done. Restart Claude Code (or send a message) to see the change."
  exit 0
fi

# ── Install: get the script ──────────────────────────────────────────────────
self_dir=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

new_script="$tmp_dir/statusline.sh"
if [ -n "$self_dir" ] && [ -f "$self_dir/statusline.sh" ]; then
  cp "$self_dir/statusline.sh" "$new_script"
else
  command -v curl >/dev/null 2>&1 || fail "curl is needed to download the status line script."
  curl -fsSL "$BASE_URL/claude/statusline.sh" -o "$new_script" \
    || fail "could not download $BASE_URL/claude/statusline.sh. Nothing was changed."
fi
is_ours "$new_script" || fail "the downloaded status line script looks wrong. Nothing was changed."
chmod +x "$new_script"

mkdir -p "$config_dir"
current=$(read_settings)

# ── Back up, only the first time ─────────────────────────────────────────────
# "First time" means the script in place is not ours. Later runs (upgrades)
# never overwrite the backup of your original setup.
if ! is_ours "$script_path"; then
  stamp=$(date +%Y%m%d-%H%M%S)
  backup="$backup_root/$stamp"
  n=1
  while [ -e "$backup" ]; do backup="$backup_root/$stamp-$n"; n=$((n + 1)); done
  mkdir -p "$backup"
  if [ -f "$script_path" ]; then
    cp -p "$script_path" "$backup/statusline.sh"
  fi
  printf '%s' "$current" | jq '.statusLine // null' > "$backup/statusLine.json"
  [ -f "$settings" ] || : > "$backup/settings-was-absent"
  say "Saved your current status line setup to $backup"
fi

# ── Write the script and the setting, only if they differ ───────────────────
changed=0
if ! cmp -s "$new_script" "$script_path"; then
  cp "$new_script" "$script_path"
  chmod +x "$script_path"
  changed=1
fi

printf '%s' "$current" | jq --argjson sl "$desired" '.statusLine = $sl' > "$tmp_dir/settings.json"
if [ ! -f "$settings" ] || ! printf '%s' "$current" | jq -e --slurpfile new "$tmp_dir/settings.json" '. == $new[0]' >/dev/null; then
  write_over "$settings" "$tmp_dir/settings.json"
  changed=1
fi

if [ "$changed" = 0 ]; then
  say "agent-statusline is already installed and up to date. Nothing changed."
else
  say "Installed the status line to $script_path"
  say "Updated the statusLine setting in $settings"
  say ""
  say "Restart Claude Code (or send a message) to see it."
  say "To undo: run this installer again with --uninstall."
fi
