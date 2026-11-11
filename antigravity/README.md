# Antigravity CLI

Google's Antigravity CLI ships an example status line script in its repository:

**https://github.com/google-antigravity/antigravity-cli/tree/main/examples/statusline**

Follow the instructions there to install it.

That repository has no license, so this project cannot include or redistribute
the script, or any part of it. Instead, here are the three changes we make to our
own copy, described in words, so it matches the Claude Code status line in this
repository:

1. **Truncate long names.** Branch names and model names are cut to a fixed
   length with an ellipsis (`…`), so a long branch name cannot push the rest of
   the line off screen or make it wrap.
2. **Context colors at 50 / 70 / 90 %.** Context usage turns yellow at 50 %,
   magenta at 70 % and red at 90 %, the same thresholds as the Claude Code line.
3. **Compact context text.** The context segment reads like the Claude Code
   line, for example `ctx 42% used`, instead of a longer label.
