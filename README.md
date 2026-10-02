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

Status lines built from segments. With no options it draws one line below the
input with the directory, model, effort, context, tokens, cache and turns.
`lines` lays out your own: which segments sit left, center or right, and
whether a line is at the top, just above the input or below it. `"*"` stands
for every segment no line names, so other plugins' segments still show.

```lua
require("statusline").setup({
  logo = true,               -- the uji logo while the session is empty
  lines = {
    { at = "above", left = { "model" }, right = { "effort" } },
    { at = "below", left = { "cwd", "*" }, right = { "context" } },
  },
})

uji.status.add("branch", function()
  return { text = branch(), color = "magenta" }
end, { priority = 15 })
```

The built-in segments are `cwd`, `model`, `effort`, `context`, `tokens`,
`cache` and `turns`; adding one with the same name after `setup` replaces it.
A segment returning `nil` is dropped, so separators never double up.

## planmode

Read-only exploration. Blocks edits and shell commands, tells the model why,
shows `PLAN` in the footer.

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

uji with `uji.pack`, `uji.job`, `uji.input.capture`, `uji.status.add`,
`uji.context.add`, `uji.ui.exec`, and `{ priority }` on `uji.on` and
`uji.ui.open_win`.
