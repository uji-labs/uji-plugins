# uji-plugins

Plugins for [uji](https://github.com/uji-labs/uji).

## Install

```lua
uji.pack.add({ "uji-labs/uji-plugins" })

require("statusline").setup({})
require("planmode").setup({})
require("telescope").setup({})
```

For local development, point at a working copy instead:

```lua
uji.pack.add({ { dir = "~/Projects/uji-plugins" } })
```

## statusline

Views for status lines. `setup()` declares the default bar as a bottom bar
toolbar item, with the directory, model, effort, context, tokens, cache and
turns. Each segment is a view, `statusline.Bar` joins them with separators, and
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
| `/approve` | leave plan mode and execute the plan just given |

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

## Requires

uji with `uji.pack`, `uji.job`, `uji.input.capture`, `uji.context.add`,
`uji.ui.exec`, `uji.ui.toolbar`, ito, and `{ priority }` on `uji.on`.
