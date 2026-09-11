local M = {}

local DIM = "#4a4a4a"
local MUTED = "#808080"

local state = { win = nil, sep = "  ·  " }

local function shorten(path)
  local home = os.getenv("HOME")
  if home and home ~= "" and path:sub(1, #home) == home then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

function M.render()
  if not state.win then return end
  local parts = uji.status.segments()
  if #parts == 0 then
    uji.ui.clear(state.win)
    return
  end
  local spans = { { text = " ", color = DIM } }
  for i, part in ipairs(parts) do
    if i > 1 then
      spans[#spans + 1] = { text = state.sep, color = DIM }
    end
    spans[#spans + 1] = part
  end
  uji.ui.set_lines(state.win, { spans })
end

local function defaults()
  uji.status.add("cwd", function()
    local dir = shorten(uji.session.info().directory or "")
    if dir == "" then return nil end
    return { text = dir, color = "cyan" }
  end, { priority = 10 })

  uji.status.add("model", function()
    local provider = uji.status.provider()
    if not provider then return nil end
    return { text = provider .. "/" .. uji.status.model(), color = MUTED }
  end, { priority = 20 })

  uji.status.add("tokens", function()
    local usage = uji.session.usage()
    if usage.total == 0 then return nil end
    local text = usage.total >= 1000
      and string.format("%.1fk tok", usage.total / 1000)
      or usage.total .. " tok"
    return { text = text, color = MUTED }
  end, { priority = 25 })

  uji.status.add("turns", function()
    local turns = 0
    for _, message in ipairs(uji.session.messages()) do
      if message.type == "user" then turns = turns + 1 end
    end
    if turns == 0 then return nil end
    return { text = turns .. (turns == 1 and " turn" or " turns"), color = MUTED }
  end, { priority = 30 })
end

function M.setup(opts)
  opts = opts or {}
  state.sep = opts.separator or state.sep
  state.win = opts.win
    or uji.ui.open_win({
      split = opts.split or "bottom",
      size = 1,
      priority = opts.priority or 10,
    })
  if opts.defaults ~= false then
    defaults()
  end
  uji.on("status_changed", M.render)
  uji.on("MessageAppended", M.render)
  M.render()
end

return M
