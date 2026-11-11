# Codex status line

Codex (OpenAI's coding agent) has a status line built in. You only have to tell
it which pieces to show. Nothing is installed and no script runs.

## What it shows

| Item | What you see | Why it matters |
| --- | --- | --- |
| `run-state` | Whether Codex is working or waiting for you | You can tell at a glance if it is still busy |
| `model-with-reasoning` | The model and how hard it is thinking | Bigger models and more reasoning are slower and use more of your limit |
| `project-name` | The folder you are working in | Avoids typing into the wrong window |
| `git-branch` | The current branch | Shows which version of the project you are changing |
| `context-used` | How full the conversation memory is | Near full, Codex starts forgetting older details |
| `five-hour-limit` | Usage left in the current 5-hour window | Tells you whether to slow down before you get cut off |
| `weekly-limit` | Usage left this week | Same, for the weekly cap |
| `estimated-thread-cost` | Rough cost of this conversation | Helps you notice expensive sessions |
| `used-tokens` | How much text has gone back and forth | The raw number behind cost and limits |

## Install

1. Open the file `~/.codex/config.toml` in any text editor.
   (`~` means your home folder. On a Mac that is `/Users/<your name>`. The
   `.codex` folder is hidden; in Finder press `Cmd + Shift + .` to show hidden
   folders.) If the file does not exist, create it.
2. Copy everything from [`status-line.toml`](status-line.toml) to the end of the file.
   If the file already has a line that says `[tui]`, put the two settings
   (`status_line = [...]` and `status_line_use_colors = true`) under that
   existing line instead of adding a second `[tui]`.
3. Save and restart Codex.

Or ask Codex itself: *"Add the status line from
github.com/tuannd9288/agent-statusline/blob/main/codex/status-line.toml to my
~/.codex/config.toml"*.

## Undo

Delete the `status_line = [...]` block and the `status_line_use_colors` line
from `~/.codex/config.toml` (and the `[tui]` line if nothing else is under it),
then restart Codex.
