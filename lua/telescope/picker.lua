local fuzzy = require("telescope.fuzzy")

local M = {}
local state = nil

local HEIGHT = 12

local function render()
  if not state then return end
  local lines = {
    { { text = "  " .. state.title, color = "cyan", bold = true } },
    { { text = "  > ", color = "cyan" }, { text = state.query, color = "#d4d4d4" },
      { text = "█", color = "#808080" } },
  }
  for i = state.offset + 1, math.min(state.offset + HEIGHT - 3, #state.matches) do
    local active = (i == state.cursor)
    lines[#lines + 1] = {
      { text = active and "› " or "  ", color = active and "cyan" or "#808080" },
      { text = state.matches[i], color = active and "cyan" or "#d4d4d4" },
    }
  end
  if #state.matches == 0 then
    lines[#lines + 1] = { { text = "  no matches", color = "#808080" } }
  end
  uji.ui.set_lines(state.win, lines)
end

local function refilter()
  state.matches = fuzzy.rank(state.items, state.query)
  state.cursor = 1
  state.offset = 0
  render()
end

local function close()
  if not state then return end
  uji.input.release()
  uji.ui.close_win(state.win)
  state = nil
end

local function move(delta)
  state.cursor = math.max(1, math.min(#state.matches, state.cursor + delta))
  local visible = HEIGHT - 3
  if state.cursor > state.offset + visible then state.offset = state.cursor - visible end
  if state.cursor <= state.offset then state.offset = state.cursor - 1 end
  render()
end

local function on_key(event)
  if not state then return end
  if event.key == "<Esc>" then
    close()
  elseif event.key == "<CR>" then
    local choice = state.matches[state.cursor]
    local accept = state.on_choice
    close()
    accept(choice)
  elseif event.key == "<Up>" or event.key == "<C-p>" then
    move(-1)
  elseif event.key == "<Down>" or event.key == "<C-n>" then
    move(1)
  elseif event.key == "<BS>" then
    state.query = state.query:sub(1, -2)
    refilter()
  elseif event.char and not event.ctrl and not event.alt then
    state.query = state.query .. event.char
    refilter()
  end
end

function M.open(title, items, on_choice)
  if #items == 0 then
    uji.notify("nothing to pick")
    return
  end
  close()
  state = {
    win = uji.ui.open_win({ split = "bottom", size = HEIGHT, border = "horizontal" }),
    title = title,
    items = items,
    query = "",
    on_choice = on_choice,
    cursor = 1,
    offset = 0,
  }
  refilter()
  uji.input.capture(on_key)
end

function M.await(title, items)
  return uji.async.await(function(resume)
    if #items == 0 then
      uji.notify("nothing to pick")
      resume(nil)
      return
    end
    M.open(title, items, resume)
  end)
end

return M
