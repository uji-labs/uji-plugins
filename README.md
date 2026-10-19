# uji-plugins

Plugins for [uji](https://github.com/uji-labs/uji).

## Install

```lua
uji.pack.add({ "uji-labs/uji-plugins" })

require("statusline").setup({})
require("memory").setup({})
require("planmode").setup({})
require("telescope").setup({})
require("themes").setup({})
require("claude_code").setup({})
```

For local development, point at a working copy instead:

```lua
uji.pack.add({ { dir = "~/Projects/uji-plugins" } })
```

## statusline

Views for status lines. `setup()` declares the default bar as a bottom bar
toolbar item, with the directory, model, effort, running jobs and how full the
context is. Each segment is a view, `statusline.Bar` joins them with separators,
and you put bars in toolbar sections with `uji.ui.toolbar`.

```lua
local ito = require("ito")
local statusline = require("statusline")

uji.ui.toolbar({
  ito.ToolbarItem(ito.ToolbarPlacement.keyboard, function()
    return statusline.Bar({ statusline.Model(), ito.Spacer(), statusline.Effort() })
  end),
  ito.ToolbarItem(ito.ToolbarPlacement.bottom_bar, function()
    return statusline.Bar({ statusline.Cwd(), ito.Spacer(), statusline.Context() })
  end),
})
```

The segments are `statusline.Cwd`, `Model`, `Effort`, `Jobs`, `Context`,
`Tokens`, `Cache` and `Turns`, and any view of your own goes in a bar the same
way. A segment that draws nothing gets no separator, so `Jobs` is only there
while something runs, and clicking it opens the jobs picker. `statusline.Logo`
shows the uji logo while the session is empty; a theme's screen puts it over
the transcript with `screen.transcript():overlay(statusline.Logo())`.

## memory

Notes uji writes for itself, kept across sessions. uji reads the index of them
before every turn and fetches a note file with `read_file` when one matters.

| | |
|---|---|
| `MEMORY.md` | The index, one line per topic, read at 200 lines or 25 KB. |
| `<topic>.md` | The notes themselves, under `<data>/memory/<project>/`. |
| `/memory` | Lists the index and the topic files, and opens the one you pick in `$EDITOR`. |
| `remember` | The tool uji adds a note with, under a topic of its choosing. |

Instructions you write are not this plugin's: uji reads `AGENTS.md`, `CLAUDE.md`
and `AGENTS.override.md` in the folder stack itself.

```lua
require("memory").setup()
```

## planmode

Read-only exploration. Blocks edits and shell commands, tells the model why,
shows `planmode.Badge` as a bottom bar toolbar item, or in a statusline bar with `badge = false`.

| | |
|---|---|
| `/plan` or `<C-b>` | toggle |
| `/plan <task>` | toggle on and submit the task as plan-only |

`read_file` and read-only commands such as `rg`, `ls` and `git log` stay
allowed. `edit_file` and `write_file` are disabled, and any other command asks
first via `uji.on("before_tool", …)` at priority 10, so it rules before policy registered
later. The reason is also injected into the system prompt through
`uji.context.add`, so the model knows before it tries.

```lua
require("planmode").setup({ keys = false, priority = 10 })
```

`planmode.decide(tool)` is the whole policy as a pure function, if you want the
gate without the commands.

## telescope

Fuzzy picker.

| | |
|---|---|
| `<C-p>` / `telescope_find` | files, opens the pick in `$EDITOR` |
| `<C-r>` / `telescope_history` | your past messages, refills the composer |
| `<C-f>` / `telescope_search` | ripgrep as you type, opens the matching file |

Opening suspends the TUI through `uji.ui.exec`, runs the editor on the real
terminal, then restores. `UJI_EDITOR` wins over `VISUAL` over `EDITOR`.

Uses `rg` when present, falls back to `find`. Runs through `uji.job.start`, so
a large repo never blocks the UI.

`telescope.fuzzy.score(haystack, needle)` and `.rank(items, query)` are
reusable; `telescope.picker.open(title, items, on_choice)` is the picker.

```lua
require("telescope").setup({ keys = false })
```

## automode-jev

Auto mode. A decision model answers the approval questions uji would otherwise
put to you.

Only calls the tool policy would ask about are asked about; a rule that already
allows or denies a call still decides it. The judge rates how likely the call
is to be safe to run unattended. At the threshold or above it runs; below it
uji asks as usual, with the number in the question. The judge never refuses on
its own, and any failure (no key, an error, a timeout) leaves the question to
you.

`backend` names the judge. `"jev"`, the default, is
[TypeSafe](https://typesafe.ai)'s decision model, which answers through
`uji.model.decide` with numbers of its own calibration. `"session"` is the
model uji is already talking to, asked over chat, so any provider works —
OpenRouter included — and the number is that model's own estimate rather than
a calibrated one.

A shell command the judge won't run, from `run_command` or Claude Code's
`Bash`, comes to you broken down: `shfmt` puts each statement and each `&&`
`||` `|` step on its own line, every line is scored in one more request, and
the question shows each line's score. With `COLORTERM` set to `truecolor` or
`24bit` the score runs from red at 0% through yellow to green at 100%;
otherwise it is green at the threshold or above, yellow from 50%, red below.
Without `shfmt` on `PATH` (or the `shfmt` setting) the command keeps the
lines it was written with.

| | |
|---|---|
| `/auto` | toggle |
| `/auto on` / `/auto off` | turn it on or off |
| `/auto 0.8` / `/auto 80%` | set the threshold for the session |
| `/auto status` | show both |

The key is uji's to hold: `TYPESAFE_API_KEY`, a file that
`TYPESAFE_API_KEY_FILE` names, one in uji's
[auth file](https://docs.uji.sh/api/auth.html#the-auth-file), or the one
`/login` saved for the `jev` provider in uji's own credential store.

```lua
require("automode-jev").setup({
  backend = "session",   -- judge with the model in use; the default is "jev"
  threshold = 0.8,
  shfmt = "shfmt",
})
```

## themes

Seven themes and a picker for them.

| Theme | Look |
|---|---|
| `fx` | grey text, bold white headings and a `┃` rail beside your messages |
| `opencode` | opencode |
| `tokyo_night` | Tokyo Night (night) |
| `catppuccin_mocha` | Catppuccin Mocha |
| `gruvbox_dark` | Gruvbox dark |
| `nord` | Nord |
| `high_contrast` | white text, yellow accents, black on yellow selections, no dim or italic text |

The themes are files in `lua/uji/themes`, so any of them works by name without
`setup`:

```lua
uji.ui.configure({ theme = "tokyo_night" })
```

Each theme paints its own background. A terminal draws painted cells fully
opaque unless it applies its opacity to them too, which Ghostty does with
`background-opacity-cells = true`. Adding the pack makes uji restart once, the
first time, to load the themes.

| | |
|---|---|
| `/theme` | lists every theme, yours and uji's too, opening on the one in use |
| `/theme <name>` | switches to a theme and keeps it |

In the list, each theme you move to shows on the whole screen at once. Enter
keeps it, and esc puts back the theme you had. A kept theme is on the next time
uji starts, unless your config sets a theme with `uji.ui.configure`, which
wins.

`setup` binds no key. Pass one to bind it:

```lua
require("themes").setup({ keys = "<C-t>" })
```

## Requires

uji with `uji.pack`, `uji.job`, `uji.model.decide`, `uji.input.capture`,
`uji.context.add`, `uji.ui.exec`, `uji.ui.toolbar`, `uji.ui.theme`,
`uji.ui.save_theme`, ito, and `{ priority }` on `uji.on`.

## claude_code

A `claude-code` provider that runs the `claude` command and shows its work in
uji: Claude Code's own sign-in, tools, `CLAUDE.md` and MCP servers, with uji's
transcript, approval, interrupt and resume. It talks to `claude` the way the
Claude Agent SDK does, over `--input-format stream-json`, one process per
session. Needs `claude` on your `PATH`, signed in.

```lua
require("claude_code").setup({
  command = { "claude" },
  permission_mode = "default",
  models = { "claude-opus-5-5", "claude-haiku-4-5-20251001" },
})
```
