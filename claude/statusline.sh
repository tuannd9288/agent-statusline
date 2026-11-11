#!/usr/bin/env bash
# agent-statusline: Claude Code status line
# https://github.com/tuannd9288/agent-statusline (MIT)
#
# Claude Code pipes a JSON description of the session into this script and
# shows whatever it prints. Everything here comes from that JSON, plus `git`
# for the branch and one local file for the account name. No network calls,
# no tokens spent.
#
# Line 1: model, account, repo + branch, PR, context, limits, cache, cost...
#         Segments drop out as the terminal gets narrower.
# Line 2: prompt cache countdown (only once Claude Code reports prompt_cache).
#
# Requires bash 3.2+ and jq.

input=$(cat)

fields=()
while IFS= read -r line; do
  fields+=("$line")
done < <(
  # Every field is read on its own inside `try`, and every value is
  # type-checked. A field of an unexpected type (a string where an object is
  # expected, a number where a string is expected, ...) only blanks that one
  # value; it never takes the rest of the line down with it.
  printf '%s' "$input" | jq -r '
    def safe(f): try f catch null;
    def clean:
      if type == "string" then gsub("[[:cntrl:]]"; " ")
      elif type == "number" then tostring
      else ""
      end;
    # Whole numbers bash can do arithmetic on: 0 <= n < 10^15, else blank.
    def int:
      if type == "number" and . >= 0 and . < 1e15 then (round | tostring) else "" end;
    def int0: int | if . == "" then "0" else . end;
    def clamp_pct:
      if type == "number" then
        (if . < 0 then 0 elif . > 100 then 100 else . end) | round | tostring
      else ""
      end;
    def left: if type == "number" then (100 - .) | clamp_pct else "" end;
    def usd:
      if type == "number" and . >= 0 and . < 1e9
      then ((. * 100 | round) / 100 | tostring) else "" end;
    def bool: if type == "boolean" then tostring else "" end;
    def ttl:
      if type == "string" and test("^[0-9]{1,6}[mh]$") then . else "" end;
    def model_name:
      if type == "string" then .
      elif type == "object" then
        ([.display_name, .id] | map(select(type == "string" and length > 0)) | first)
      else null
      end;
    def causes:
      if type == "object" and (.causes | type) == "array" and (.causes | length) > 0
      then .causes | map(clean | gsub("_"; " ")) | map(select(length > 0)) | join(", ")
      else ""
      end;
    def first_str(a; b):
      [a, b] | map(select(type == "string" and length > 0)) | first // "";

    [
      (safe(.model | model_name) // "Claude" | clean),
      (safe(.effort.level) | clean),
      (safe(first_str(.workspace.current_dir; .cwd)) | clean),
      (safe(.workspace.repo.name) | clean),
      (safe(first_str(.workspace.project_dir; first_str(.workspace.current_dir; .cwd))) | clean),
      (safe(.context_window.used_percentage) | clamp_pct),
      (safe(.rate_limits.five_hour.used_percentage) | left),
      (safe(.rate_limits.seven_day.used_percentage) | left),
      (safe(.agent.name) | clean),
      (safe(.session_name) | clean),
      (safe(.pr.number) | int),
      (safe(.pr.review_state) | clean),
      (safe(.cost.total_cost_usd) | usd),
      (safe(.context_window.total_input_tokens) | int0),
      (safe(.context_window.total_output_tokens) | int0),
      (safe(.context_window.current_usage.cache_read_input_tokens) | int0),
      (safe(.context_window.current_usage.cache_creation_input_tokens) | int0),
      (safe(.context_window.current_usage.input_tokens) | int0),
      (if safe(.prompt_cache | type) == "object" then "1" else "" end),
      (safe(.prompt_cache.warm) | bool),
      (safe(.prompt_cache.ttl) | ttl),
      (safe(.prompt_cache.expires_at) | int),
      (safe(.prompt_cache.hit_ratio)
        | if type == "number" then
            (if . < 0 then 0 elif . > 1 then 1 else . end) * 100 | round | tostring
          else "" end),
      (safe(.prompt_cache.misses) | int),
      (safe(.prompt_cache.recache_tokens_if_cold) | int),
      (safe(.prompt_cache.last_miss_cause) | causes),
      (safe(.prompt_cache.caching_observed) | bool)
    ] | .[]
  ' 2>/dev/null
)

# Exactly 27 lines or nothing: anything else means the input was not usable.
if [ "${#fields[@]}" -ne 27 ]; then
  fields=()
fi

model=${fields[0]:-Claude}
effort=${fields[1]:-}
cwd=${fields[2]:-}
repo_name=${fields[3]:-}
project_dir=${fields[4]:-}
context_used=${fields[5]:-}
five_hour_left=${fields[6]:-}
seven_day_left=${fields[7]:-}
agent_name=${fields[8]:-}
session_name=${fields[9]:-}
pr_number=${fields[10]:-}
pr_state=${fields[11]:-}
cost_usd=${fields[12]:-}
tokens_in=${fields[13]:-0}
tokens_out=${fields[14]:-0}
cache_read=${fields[15]:-0}
cache_write=${fields[16]:-0}
fresh_in=${fields[17]:-0}
pc_present=${fields[18]:-}
pc_warm=${fields[19]:-}
pc_ttl=${fields[20]:-}
pc_expires_at=${fields[21]:-}
pc_hit=${fields[22]:-}
pc_misses=${fields[23]:-}
pc_recache=${fields[24]:-}
pc_cause=${fields[25]:-}
pc_observed=${fields[26]:-}

model=${model#Claude }
if [ -z "$repo_name" ] && [ -n "$project_dir" ]; then
  repo_name=${project_dir%/}
  repo_name=${repo_name##*/}
fi

truncate_label() {
  local value=$1
  local max_length=$2
  if [ "${#value}" -le "$max_length" ]; then
    printf '%s' "$value"
  else
    printf '%s…' "${value:0:$((max_length - 1))}"
  fi
}

# Claude Code does not pass the signed-in account, but its own state file has
# it. Only the part before "@" is shown. Set AGENT_STATUSLINE_HIDE_ACCOUNT=1 to
# turn this segment off (useful when screen sharing).
account=""
if [ "${AGENT_STATUSLINE_HIDE_ACCOUNT:-0}" != "1" ]; then
  account=$(jq -r '.oauthAccount.emailAddress // empty' "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" 2>/dev/null)
  account=${account%%@*}
fi

model=$(truncate_label "$model" 16)
repo_name=$(truncate_label "$repo_name" 10)
account=$(truncate_label "$account" 14)

reset=$'\033[0m'
bold_cyan=$'\033[1;36m'
blue=$'\033[34m'
green=$'\033[32m'
yellow=$'\033[33m'
red=$'\033[31m'
magenta=$'\033[35m'
dim=$'\033[2m'
separator=" ${dim}│${reset} "

context_color() {
  if [ "$1" -ge 90 ]; then printf '%s' "$red"
  elif [ "$1" -ge 70 ]; then printf '%s' "$magenta"
  elif [ "$1" -ge 50 ]; then printf '%s' "$yellow"
  else printf '%s' "$green"
  fi
}

quota_color() {
  if [ "$1" -lt 20 ]; then printf '%s' "$red"
  elif [ "$1" -lt 50 ]; then printf '%s' "$yellow"
  else printf '%s' "$green"
  fi
}

# 15500 -> 15.5k. A raw token count is six digits of noise; the magnitude is
# the whole message.
human_num() {
  local n=$1
  if   [ "$n" -ge 1000000 ]; then printf '%s.%sM' "$((n / 1000000))" "$(((n % 1000000) / 100000))"
  elif [ "$n" -ge 1000 ];    then printf '%s.%sk' "$((n / 1000))"    "$(((n % 1000) / 100))"
  else printf '%s' "$n"
  fi
}

# 82400 -> 82k, 1250000 -> 1.3M. Rounded, for the cache line.
round_k() {
  local n=$1
  if   [ "$n" -ge 1000000 ]; then
    local tenths=$(((n + 50000) / 100000))
    printf '%s.%sM' "$((tenths / 10))" "$((tenths % 10))"
  elif [ "$n" -ge 1000 ]; then printf '%sk' "$(((n + 500) / 1000))"
  else printf '%s' "$n"
  fi
}

# Share of this turn's input that came from cache. High is cheap and fast; a
# sudden drop means something invalidated the prefix, which is worth seeing at
# the moment it happens rather than on the bill.
cache_color() {
  if   [ "$1" -ge 80 ]; then printf '%s' "$green"
  elif [ "$1" -ge 50 ]; then printf '%s' "$yellow"
  else printf '%s' "$red"
  fi
}

# Git must never run against a network filesystem. `git status` walks the whole
# work tree, and over SMB/NFS every stat is a network round trip; on a slow or
# unresponsive server those calls can block and pile up once per render.
#
# The mount table is the safe way to detect this: `mount` answers from the
# kernel and never contacts the server. Anything that touches the path itself
# (df, stat -f, test -d) can block instead.
is_network_path() {
  local path=$1 line mountpoint fstype
  case $path in
    /*) ;;
    *) return 1 ;;
  esac

  while IFS= read -r line; do
    # macOS: "server:/x on /mnt (nfs, ...)"  Linux: "server:/x on /mnt type nfs (...)"
    if [[ $line =~ ^.*\ on\ (.*)\ type\ ([^ ]+)\ \(.*\)$ ]]; then
      mountpoint=${BASH_REMATCH[1]}
      fstype=${BASH_REMATCH[2]}
    elif [[ $line =~ ^.*\ on\ (.*)\ \((.*)\)$ ]]; then
      mountpoint=${BASH_REMATCH[1]}
      fstype=${BASH_REMATCH[2]%%,*}
    else
      continue
    fi

    case $fstype in
      smbfs|cifs|smb3|nfs|nfs4|afpfs|webdav|davfs|ftp|macfuse|osxfuse|fuse.sshfs|sshfs) ;;
      *) continue ;;
    esac

    # "/" would prefix-match everything, but no network mount is ever the root.
    [ "$mountpoint" = "/" ] && continue
    if [ "$path" = "$mountpoint" ] || [ "${path#"$mountpoint"/}" != "$path" ]; then
      return 0
    fi
  done < <(mount 2>/dev/null)

  return 1
}

git_branch=""
git_dirty=""
if [ -n "$cwd" ] && command -v git >/dev/null 2>&1 && ! is_network_path "$cwd" \
  && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git_branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
  if [ -z "$git_branch" ]; then
    git_branch=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
  fi
  if [ -n "$(git --no-optional-locks -C "$cwd" status --porcelain --untracked-files=normal 2>/dev/null)" ]; then
    git_dirty="*"
  fi
fi
git_branch=$(truncate_label "$git_branch" 10)

columns=${COLUMNS:-120}
case "$columns" in
  ''|*[!0-9]*) columns=120 ;;
esac

# ── Line 1 ───────────────────────────────────────────────────────────────────

if [ "$columns" -lt 36 ]; then
  model_text=${model:0:$columns}
elif [ "$columns" -lt 60 ]; then
  model_text=${model:0:16}
else
  model_text="◆ ${model}"
  if [ -n "$effort" ]; then
    model_text+=" · ${effort}"
  fi
fi
segments=("${bold_cyan}${model_text}${reset}")

if [ "$columns" -ge 90 ] && [ -n "$account" ]; then
  segments+=("👤 ${account}")
fi

if [ "$columns" -ge 100 ] && [ -n "$repo_name" ]; then
  workspace_text="${blue}▣ ${repo_name}${reset}"
  if [ -n "$git_branch" ]; then
    git_color=$green
    [ -n "$git_dirty" ] && git_color=$yellow
    workspace_text+=" · ${git_color}⎇ ${git_branch}${git_dirty}${reset}"
  fi
  segments+=("$workspace_text")
fi

# Only rendered when the branch actually has a pull request.
if [ "$columns" -ge 120 ] && [ -n "$pr_number" ]; then
  case "$pr_state" in
    approved)          pr_color=$green ;;
    changes_requested) pr_color=$red ;;
    *)                 pr_color=$dim ;;
  esac
  segments+=("${pr_color}⑂ #${pr_number}${reset}")
fi

if [ "$columns" -ge 36 ] && [ -n "$context_used" ]; then
  color=$(context_color "$context_used")
  segments+=("${color}ctx ${context_used}% used${reset}")
fi

if [ "$columns" -ge 120 ] && [ -n "$five_hour_left" ]; then
  color=$(quota_color "$five_hour_left")
  segments+=("${color}◷ 5h ${five_hour_left}% left${reset}")
fi

if [ "$columns" -ge 75 ]; then
  if [ -n "$seven_day_left" ]; then
    color=$(quota_color "$seven_day_left")
    segments+=("${color}◷ 7d ${seven_day_left}% left${reset}")
  elif [ "$columns" -lt 120 ] && [ -n "$five_hour_left" ]; then
    color=$(quota_color "$five_hour_left")
    segments+=("${color}◷ 5h ${five_hour_left}% left${reset}")
  fi
fi

cache_total=$((cache_read + cache_write + fresh_in))
if [ "$columns" -ge 150 ] && [ "$cache_total" -gt 0 ]; then
  cache_pct=$((cache_read * 100 / cache_total))
  color=$(cache_color "$cache_pct")
  segments+=("${color}⇄ cache ${cache_pct}%${reset}")
fi

if [ "$columns" -ge 140 ] && [ -n "$cost_usd" ]; then
  segments+=("${dim}\$${cost_usd}${reset}")
fi

if [ "$columns" -ge 190 ] && [ "$tokens_in" -gt 0 ]; then
  segments+=("${dim}↓$(human_num "$tokens_in") ↑$(human_num "$tokens_out")${reset}")
fi

if [ "$columns" -ge 180 ]; then
  case "$agent_name" in
    ""|default|Default|main|Main) ;;
    *) agent_name=$(truncate_label "$agent_name" 20); segments+=("${magenta}◎ ${agent_name}${reset}") ;;
  esac
  case "$session_name" in
    ""|default|Default|main|Main) ;;
    *) session_name=$(truncate_label "$session_name" 20); segments+=("${magenta}◇ ${session_name}${reset}") ;;
  esac
fi

output=""
for segment in "${segments[@]}"; do
  if [ -n "$output" ]; then
    output+="$separator"
  fi
  output+="$segment"
done

printf '%s\n' "$output"

# ── Line 2: prompt cache countdown ───────────────────────────────────────────
#
# Every message resends the whole conversation. While the cache is warm, the
# unchanged part is read back cheaply; once it expires, the next message
# reprocesses everything. This line shows how long you have left.
#
# Nothing is printed until Claude Code includes `prompt_cache` (v2.1.251+, and
# only after the first reply). Any field that is missing is skipped.

[ -n "$pc_present" ] || exit 0

# Caching is off, or the provider does not report it: nothing to count down.
if [ "$pc_observed" = "false" ] && [ "$pc_warm" != "true" ]; then
  exit 0
fi

now=${AGENT_STATUSLINE_NOW:-$(date +%s)}
case "$now" in ''|*[!0-9]*) now=$(date +%s) ;; esac

ttl_secs=""
case "$pc_ttl" in
  *h) n=${pc_ttl%h}; case "$n" in ''|*[!0-9]*) ;; *) ttl_secs=$((n * 3600)) ;; esac ;;
  *m) n=${pc_ttl%m}; case "$n" in ''|*[!0-9]*) ;; *) ttl_secs=$((n * 60)) ;; esac ;;
esac

remaining=""
if [ -n "$pc_expires_at" ]; then
  remaining=$((pc_expires_at - now))
fi

# Decide warm or cold. Trust `warm`, but a timestamp in the past means the
# cache has expired since Claude Code last wrote the JSON.
state=""
if [ "$pc_warm" = "true" ]; then
  state=warm
  if [ -n "$remaining" ] && [ "$remaining" -le 0 ]; then state=cold; fi
elif [ "$pc_warm" = "false" ]; then
  state=cold
elif [ -n "$remaining" ]; then
  if [ "$remaining" -gt 0 ]; then state=warm; else state=cold; fi
fi

format_left() {
  local s=$1
  if   [ "$s" -ge 3600 ]; then
    local h=$((s / 3600)) m=$(((s % 3600) / 60))
    if [ "$m" -gt 0 ]; then printf '%sh %sm' "$h" "$m"; else printf '%sh' "$h"; fi
  elif [ "$s" -ge 60 ]; then printf '%sm' "$(((s + 59) / 60))"
  else printf '%ss' "$s"
  fi
}

cache_parts=()

if [ "$state" = "warm" ]; then
  color=$green
  head="cache ●"
  [ -n "$pc_ttl" ] && head+=" ${pc_ttl}"
  if [ -n "$remaining" ]; then
    if [ -n "$ttl_secs" ] && [ "$ttl_secs" -gt 0 ]; then
      # Yellow in the last 20% of the TTL: time to send the next message, or
      # accept that it will be slower and cost more.
      if [ $((remaining * 5)) -lt "$ttl_secs" ]; then color=$yellow; fi
      width=10
      [ "$columns" -lt 60 ] && width=6
      filled=$(((remaining * width + ttl_secs - 1) / ttl_secs))
      [ "$filled" -gt "$width" ] && filled=$width
      [ "$filled" -lt 0 ] && filled=0
      bar=""
      i=0
      while [ "$i" -lt "$width" ]; do
        if [ "$i" -lt "$filled" ]; then bar+="█"; else bar+="░"; fi
        i=$((i + 1))
      done
      head+=" ${bar}"
    fi
    head+=" $(format_left "$remaining") left"
  elif [ -z "$pc_ttl" ]; then
    head+=" warm"
  fi
  cache_parts+=("$head")
  if [ "$columns" -ge 60 ]; then
    [ -n "$pc_hit" ] && cache_parts+=("hit ${pc_hit}%")
    [ -n "$pc_misses" ] && cache_parts+=("misses ${pc_misses}")
  fi
elif [ "$state" = "cold" ]; then
  color=$red
  cache_parts+=("cache ○ cold")
  if [ -n "$pc_recache" ] && [ "$pc_recache" -gt 0 ]; then
    if [ "$columns" -ge 60 ]; then
      cache_parts+=("next message re-caches $(round_k "$pc_recache") tokens")
    else
      cache_parts+=("re-cache $(round_k "$pc_recache")")
    fi
  fi
  if [ "$columns" -ge 100 ] && [ -n "$pc_cause" ]; then
    cache_parts+=("last miss: ${pc_cause}")
  fi
else
  # No warm flag and no timestamp: show what is known.
  color=$dim
  cache_parts+=("cache")
  [ -n "$pc_hit" ] && cache_parts+=("hit ${pc_hit}%")
  [ -n "$pc_misses" ] && cache_parts+=("misses ${pc_misses}")
  [ "${#cache_parts[@]}" -gt 1 ] || exit 0
fi

line2=""
for part in "${cache_parts[@]}"; do
  if [ -n "$line2" ]; then line2+=" · "; fi
  line2+="$part"
done

printf '%s%s%s\n' "$color" "$line2" "$reset"
