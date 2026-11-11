# Pi status bar

[Pi](https://www.npmjs.com/package/@mariozechner/pi-coding-agent) does not have a
status line of its own. This uses the
[`@kreeger/pi-statusbar`](https://github.com/kreeger/pi-statusbar) extension
(MIT licensed) with the layout in [`statusbar.json`](statusbar.json).

## What it shows

| Section | What you see | Why it matters |
| --- | --- | --- |
| `model` | The model in use | Bigger models are slower and use more of your limit |
| `thinking` | The thinking level | More thinking = better answers on hard problems, but slower |
| `directory` | The folder you are working in | Avoids typing into the wrong window |
| `git` | Branch and whether there are unsaved changes | Shows which version you are changing |
| `context` | How full the conversation memory is | Near full, the agent starts forgetting older details |
| `codex-quota` | Codex usage left (only with OpenAI/Codex models) | Warns you before you hit the limit |
| `cache` | Cache reads and writes | High reads mean faster, cheaper replies |
| `cost` | Running cost of the session | Helps you notice expensive sessions |
| `token-flow` | Text sent and received | The raw number behind cost and limits |

## Install

In a terminal:

```bash
pi install npm:@kreeger/pi-statusbar@0.2.0
mkdir -p ~/.pi/agent
curl -fsSL https://raw.githubusercontent.com/tuannd9288/agent-statusline/main/pi/statusbar.json -o ~/.pi/agent/statusbar.json
```

Restart Pi. If you already had a `~/.pi/agent/statusbar.json`, copy it somewhere
safe first; the `curl` line replaces it.

Pinning `@0.2.0` means you get the exact version this layout was tested with.

### A note on `codex-quota`

According to the extension's own README, the `codex-quota` section is
experimental: it reads your local Codex sign-in (`~/.codex/auth.json`, read-only)
and asks a private Codex endpoint for your usage. It only shows the used
percentage and never displays the credentials. If you would rather not have
that, delete the `"codex-quota",` line from `~/.pi/agent/statusbar.json`.

## Undo

```bash
rm ~/.pi/agent/statusbar.json   # back to the extension's default layout
```

To remove the extension entirely, delete the folder
`~/.pi/agent/extensions/pi-statusbar` (or check `pi --help` for a remove
command in your Pi version), then restart Pi.
