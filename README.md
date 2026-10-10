# uji-plugins

Plugins for [uji](https://github.com/uji-labs/uji).

## Install

```lua
uji.pack.add({ "uji-labs/uji-plugins" })

require("statusline").setup({})
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
toolbar item, with the directory, model, effort and how full the context is. Each segment is a view, `statusline.Bar` joins them with separators, and
you put bars in toolbar sections with `uji.ui.toolbar`.

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

The segments are `statusline.Cwd`, `Model`, `Effort`, `Context`, `Tokens`,
`Cache` and `Turns`, and any view of your own goes in a bar the same way. A
segment that draws nothing gets no separator. `statusline.Logo` shows the uji
logo while the session is empty; a theme's screen puts it over the transcript
with `screen.transcript():overlay(statusline.Logo())`.

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
| `<C-p>` / `/find` | files, opens the pick in `$EDITOR` |
| `<C-a>` / `/attach` | files, `@path` into the composer |
| `<C-g>` / `/branch` | git branches, asks the model about one |
| `<C-r>` / `/history` | your past messages, refills the composer |
| `/grep <pattern>` | ripgrep hits, opens the matching file |

Opening suspends the TUI through `uji.ui.exec`, runs the editor on the real
terminal, then restores. `UJI_EDITOR` wins over `VISUAL` over `EDITOR`.

Uses `rg` when present, falls back to `find`. Runs through `uji.job.start`, so
a large repo never blocks the UI.

`telescope.fuzzy.score(haystack, needle)` and `.rank(items, query)` are
reusable; `telescope.picker.open(title, items, on_choice)` is the picker.

```lua
require("telescope").setup({ keys = false })
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

uji with `uji.pack`, `uji.job`, `uji.input.capture`, `uji.context.add`,
`uji.ui.exec`, `uji.ui.toolbar`, `uji.ui.theme`, `uji.ui.save_theme`, ito,
and `{ priority }` on `uji.on`.

## subagent

A `subagent` tool that hands tasks to agents, each a separate `uji run` with a
context of its own. Every agent shows as a row under the running tool, with
its state, the tool it is calling and the tokens it used. `/agent <name>
<task>` runs one, and `/subagents` lists the agents that ran and opens their
sessions. See the [subagent docs](https://docs.uji.sh/plugins/subagent.html).

## workflow

A `workflow` tool that runs a Lua script orchestrating many agents with
`agent()`, `parallel()`, `pipeline()` and `phase()`. Agents show grouped by
phase under the running tool, `/workflows` inspects, opens and stops runs, and
`resume` reruns a script while reusing the answers that did not change. Needs
`subagent`. See the [workflow docs](https://docs.uji.sh/plugins/workflow.html).

```lua
require("subagent").setup({})
require("workflow").setup({ concurrency = 4 })
```

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
