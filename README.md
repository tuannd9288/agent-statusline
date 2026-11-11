# agent-statusline

A status line for coding agents that shows your limits, how full the
conversation is, and a **prompt cache countdown**, installed in one step.

Made for **Claude Code**. Also includes ready-made setups for **Codex** and
**Pi**, and a pointer for **Antigravity CLI**.

```
◆ Opus 5.5 · high │ 👤 alex │ ▣ my-app · ⎇ main* │ ctx 42% used │ ◷ 5h 77% left │ ◷ 7d 59% left
cache ● 1h ███████░░░ 38m left · hit 91% · misses 0
```

You do not need to be a developer to use this.

---

## What is a status line?

When you chat with Claude Code, there is a strip of text at the bottom of the
window, just under where you type. That strip is the **status line**. By default
it shows very little. This project fills it with the things that actually help
you while you work: which model you are using, how much of your usage limit is
left, how full the conversation is, and whether your next message will be fast
and cheap or slow and expensive.

It is like the fuel gauge and speedometer on a car dashboard: you do not stare
at it, but a quick glance stops surprises.

## What each part means, and why it matters

Line 1, from left to right:

| You see | What it is | Why it matters |
| --- | --- | --- |
| `◆ Opus 5.5 · high` | The model and its effort level | Bigger models and higher effort give better answers but are slower and use your limits faster. |
| `👤 alex` | The account you are signed in with (the part of your email before `@`) | If you have a work and a personal account, you can see which one is being charged. |
| `▣ my-app · ⎇ main*` | The project folder and the git branch. `*` means there are unsaved (uncommitted) changes | Stops you from working in the wrong project or on the wrong version. |
| `⑂ #42` | The pull request for this branch, if there is one. Green = approved, red = changes requested | Shows review status without opening a browser. |
| `ctx 42% used` | How full the conversation's memory (the *context window*) is. Green, then yellow at 50 %, magenta at 70 %, red at 90 % | When it fills up, Claude summarizes older messages and may forget details. Start a fresh conversation for a new task before it gets red. |
| `◷ 5h 77% left` | Usage left in your current 5-hour window (Pro / Max subscriptions) | Green, yellow under 50 %, red under 20 %. Tells you to slow down before you are cut off. |
| `◷ 7d 59% left` | Usage left for the week | Same, for the weekly cap. |
| `⇄ cache 95%` | How much of the last message was read from cache | High is good. A sudden drop means something made Claude re-read everything. |
| `$1.23` | Estimated cost of this session at list price | Useful on an API key; on a subscription it is an indication, not a bill. |
| `↓84.2k ↑6.1k` | Text sent to and received from the model, in *tokens* (roughly ¾ of a word each) | The raw number behind cost and limits. |
| `◎ reviewer` / `◇ fix login bug` | The agent or session name, when there is one | Helps when you run several sessions at once. |

Parts that do not apply are simply not shown. On a narrow window the less
important parts disappear first, so the line never wraps.

### Line 2: the cache countdown

```
cache ● 1h ███████░░░ 38m left · hit 91% · misses 0       ← green: warm
cache ● 1h ██░░░░░░░░ 9m left · hit 87% · misses 1        ← yellow: under 20% of the time left
cache ○ cold · next message re-caches 82k tokens          ← red: expired
```

**Why this matters.** Every time you send a message, Claude Code sends the
*whole* conversation again, because the model does not remember anything between
messages. The **prompt cache** lets it skip re-reading the part it has already
seen. While the cache is *warm*, replies start faster and use much less of your
usage limit. Once it *expires*, the next message has to process everything from
scratch, which is slower and more expensive. The countdown shows how much time is
left, so you know whether to send that follow-up now or accept the slower turn.

How long the cache lasts:

- On a **Claude subscription** (Pro, Max, ...), the main conversation's cache
  lasts **1 hour** after your last message.
- **Subagents** (helpers Claude starts in the background) get **5 minutes**.
- With an **API key**, or once you are using **extra usage credits** on a
  subscription, it is **5 minutes**.

A few things worth knowing:

- **Switching models** in the middle of a conversation (`/model`) starts the
  cache over: the next message re-reads everything.
- **Editing CLAUDE.md** in the middle of a session does *not* break the cache,
  but the change also does not take effect until `/clear`, `/compact` or a restart.
- **`/rewind`** goes back to an earlier point and can reuse the cache from that
  point. **`/compact`** replaces the conversation with a summary and builds a
  new cache.

Source: [How Claude Code uses prompt caching](https://code.claude.com/docs/en/prompt-caching).

The countdown needs Claude Code **2.1.251 or newer** and appears after Claude's
first reply. On older versions you simply get line 1.

---

## Install (Claude Code)

### Option A: no terminal needed

Open Claude Code and paste this sentence:

> Install the status line from github.com/tuannd9288/agent-statusline for me

Claude will download the installer, show you what it is about to run, and ask
for permission. The installer:

1. checks that two small programs it needs, `jq` and `git`, are present (if not,
   it tells you the exact command to install them and stops; it never installs
   anything by itself),
2. saves a backup of your current status line, if you have one,
3. copies the status line script into your Claude folder and turns it on.

Then restart Claude Code (or just send a message) and the new status line
appears.

### Option B: one command

On a Mac, open the **Terminal** app (press `Cmd + Space`, type *Terminal*,
press Enter). On Linux, open your terminal. Paste this line and press Enter:

```bash
curl -fsSL https://raw.githubusercontent.com/tuannd9288/agent-statusline/main/claude/install.sh | bash
```

Running it again is safe; it changes nothing if you are already up to date. Run
it again later to pick up a newer version.

### Uninstall

Paste into Claude Code: *"Uninstall the agent-statusline status line"*, or run:

```bash
curl -fsSL https://raw.githubusercontent.com/tuannd9288/agent-statusline/main/claude/install.sh | bash -s -- --uninstall
```

This puts back exactly what you had before (your old status line script and
setting), or removes ours if you had none.

### For AI agents asked to install this

If a user asks you to install this status line for Claude Code, run the
installer and report its output:

```bash
curl -fsSL https://raw.githubusercontent.com/tuannd9288/agent-statusline/main/claude/install.sh | bash
```

To uninstall, run the same command with `bash -s -- --uninstall`. Do not edit
`settings.json` by hand and do not install `jq` or `git` without asking; if the
installer says they are missing, show the user the command it printed.

## Other agents

| Agent | How | Folder |
| --- | --- | --- |
| **Codex** | Built-in status line: paste a few lines into `~/.codex/config.toml` | [`codex/`](codex/) |
| **Pi** | The `@kreeger/pi-statusbar` extension plus our layout file | [`pi/`](pi/) |
| **Antigravity CLI** | Google's example script (link only, it has no license) | [`antigravity/`](antigravity/) |

---

## FAQ

**Does it send my data anywhere or use up my limits?**
No. Claude Code hands the script a description of the session; the script
formats it. It makes no network calls and uses no tokens. The only other things
it reads are `git` (for the branch) and Claude Code's own local file for your
account name.

**I don't want my account name on screen (screen sharing, streaming).**
Add `"env": { "AGENT_STATUSLINE_HIDE_ACCOUNT": "1" }` to your Claude
`settings.json`, or ask Claude to do it for you.

**I see odd boxes instead of symbols.**
Your terminal font is missing a symbol. Any modern font (the default on macOS
Terminal, iTerm2, VS Code, Windows Terminal) has them. No special
"Nerd Font" is needed.

**The cache line does not show.**
Update Claude Code (`claude update`) to 2.1.251 or newer, then send one message.
If you use a provider or gateway that does not report caching, the line stays
hidden.

**I use `CLAUDE_CONFIG_DIR` for several profiles.**
The installer respects it. Run it once per profile with the variable set.

**Does it work on Windows?**
Inside WSL, yes. Native Windows is not supported.

**Where are my backups?**
In `~/.claude/agent-statusline-backups/<date-time>/`. After an uninstall the
folder is renamed with `.restored` at the end. You can delete these folders
whenever you like.

---

## Details for the curious

### Files

```
claude/statusline.sh   the status line script (bash + jq)
claude/install.sh      installer / uninstaller
codex/                 Codex config snippet + instructions
pi/                    Pi status bar layout + instructions
antigravity/           link to Google's example + our changes, in words
examples/*.json        sample input from Claude Code (warm, about to expire, cold, ...)
test/run.sh            renders every example at many widths and tests the installer
```

### What the installer changes

Only two things, inside `~/.claude` (or `$CLAUDE_CONFIG_DIR`):

- `statusline.sh` is written (made executable).
- In `settings.json`, the `statusLine` key is set to:

  ```json
  {
    "type": "command",
    "command": "/Users/you/.claude/statusline.sh",
    "padding": 0,
    "refreshInterval": 30
  }
  ```

  Every other setting is left as it was. `refreshInterval: 30` re-runs the
  script every 30 seconds so the countdown moves while you are idle. If
  `settings.json` does not exist it is created; if it is a symlink, the target is
  updated and the symlink kept. If it is not valid JSON, the installer stops
  without changing anything.

The first time it runs, it copies your previous `statusline.sh` (if any) and
your previous `statusLine` setting into a timestamped backup folder. Later runs
(updates) do not overwrite that backup. `--uninstall` restores from the newest
backup.

Requirements: macOS or Linux, bash 3.2 or newer (the macOS default is fine),
`jq`, `git`, and `curl` for the one-line install.

### Width rules

Claude Code passes the terminal width in `COLUMNS`. Segments appear at:

| Columns | Adds |
| --- | --- |
| any | model |
| 36+ | context |
| 60+ | model effort; cache line shows hit % and misses |
| 75+ | 7-day limit (or 5-hour if there is no 7-day) |
| 90+ | account |
| 100+ | repo and branch; cold cache shows the last miss cause |
| 120+ | pull request, 5-hour limit |
| 140+ | cost |
| 150+ | cache % of the last message |
| 180+ | agent and session name |
| 190+ | tokens in / out |

### Settings via environment

| Variable | Effect |
| --- | --- |
| `AGENT_STATUSLINE_HIDE_ACCOUNT=1` | Hide the account segment |
| `CLAUDE_CONFIG_DIR` | Where Claude Code's config lives (default `~/.claude`) |

### Safety notes in the script

`git` is skipped when the folder is on a network drive (SMB, NFS, ...), because
`git status` there can hang and pile up. The check reads the mount table only,
which never touches the network.

### Testing

```bash
bash test/run.sh          # all checks
bash test/run.sh --show   # also print every rendered line
```

The tests use a temporary home folder and never touch your real `~/.claude`.
They run the script with your `bash` and, on macOS, also with `/bin/bash` 3.2.

### Credits

- The one-command install with backup and `--uninstall` is inspired by
  [kamranahmedse/claude-statusline](https://github.com/kamranahmedse/claude-statusline) (MIT).
  No code is shared; this project reads limits from Claude Code's input instead
  of calling the network.
- The cache countdown idea comes from a post by `@Voxyz_ai` on X.
- Pi support uses [kreeger/pi-statusbar](https://github.com/kreeger/pi-statusbar) (MIT).

## License

[MIT](LICENSE)
