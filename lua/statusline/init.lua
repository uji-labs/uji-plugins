local M = {}

local DIM = "#4a4a4a"
local MUTED = "#808080"

local SPOTS = {
  top = { split = "top", priority = 10 },
  above = { split = "bottom", priority = 60 },
  below = { split = "bottom", priority = 10 },
}

local LOGO = {
  color = "#f9e2af",
  lines = {
    "██    ██        ██  ██",
    "██    ██        ██  ██",
    "██    ██        ██  ██",
    "██    ██  ██    ██  ██",
    "  ████      ████    ██",
  },
}

local state = { sep = "  ·  ", lines = {}, placed = {} }

local function compact(n)
  local value, unit = n, ""
  if n >= 1000000 then
    value, unit = n / 1000000, "M"
  elseif n >= 1000 then
    value, unit = n / 1000, "k"
  else
    return tostring(n)
  end
  return (string.format("%.1f", value):gsub("%.0$", "")) .. unit
end

local function shorten(path)
  local home = os.getenv("HOME")
  if home and home ~= "" and path:sub(1, #home) == home then
    return "~" .. path:sub(#home + 1)
  end
  return path
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

  uji.status.add("effort", function()
    local effort = uji.status.effort()
    if not effort then return nil end
    return { text = "think " .. effort, color = MUTED }
  end, { priority = 22 })

  uji.status.add("context", function()
    local ctx = uji.status.context()
    if not ctx.window or ctx.window == 0 then return nil end
    local pct = math.floor(ctx.used / ctx.window * 100 + 0.5)
    return {
      text = string.format("%s/%s ctx (%d%%)", compact(ctx.used), compact(ctx.window), pct),
      color = pct >= 80 and "yellow" or MUTED,
    }
  end, { priority = 25 })

  uji.status.add("tokens", function()
    local usage = uji.session.usage()
    local fresh = usage.input + usage.cache_write + usage.output
    if fresh == 0 then return nil end
    return { text = compact(fresh) .. " tok", color = MUTED }
  end, { priority = 26 })

  uji.status.add("cache", function()
    local last = uji.session.usage().last
    local prefix = last.input + last.cache_read + last.cache_write
    if last.cache_read == 0 or prefix == 0 then return nil end
    return {
      text = string.format("cache %d%%", math.floor(last.cache_read / prefix * 100 + 0.5)),
      color = MUTED,
    }
  end, { priority = 27 })

  uji.status.add("turns", function()
    local turns = 0
    for _, message in ipairs(uji.session.messages()) do
      if message.type == "user" then turns = turns + 1 end
    end
    if turns == 0 then return nil end
    return { text = turns .. (turns == 1 and " turn" or " turns"), color = MUTED }
  end, { priority = 30 })
end

local function names(slot)
  local out = {}
  for _, name in ipairs(slot or {}) do
    if name == "*" then
      for _, other in ipairs(uji.status.list()) do
        if not state.placed[other] then out[#out + 1] = other end
      end
    else
      out[#out + 1] = name
    end
  end
  return out
end

local function joined(slot, into)
  local first = true
  for _, part in ipairs(uji.status.render(names(slot))) do
    if not first then into[#into + 1] = { text = state.sep, color = DIM } end
    into[#into + 1] = part
    first = false
  end
end

local function row(line)
  local spans = { " " }
  joined(line.left, spans)
  if line.center then
    spans[#spans + 1] = { fill = true }
    joined(line.center, spans)
  end
  spans[#spans + 1] = { fill = true }
  joined(line.right, spans)
  spans[#spans + 1] = " "
  return spans
end

local function layout(specs)
  local lines, placed = {}, {}
  for index, spec in ipairs(specs) do
    local spot = SPOTS[spec.at or "below"]
    if not spot then
      error("statusline: line " .. index .. " is at `" .. tostring(spec.at) .. "`, not top, above or below", 3)
    end
    lines[index] = { left = spec.left, center = spec.center, right = spec.right, spot = spot, priority = spec.priority }
    for _, slot in ipairs({ spec.left or {}, spec.center or {}, spec.right or {} }) do
      for _, name in ipairs(slot) do placed[name] = true end
    end
  end
  return lines, placed
end

local function open(line)
  line.win = uji.ui.open_win({ split = line.spot.split, size = 1, priority = line.priority or line.spot.priority })
end

local function hide_logo()
  if state.logo then
    uji.ui.close_win(state.logo)
    state.logo = nil
  end
end

local function show_logo(spec)
  if spec == true then spec = LOGO end
  local lines, width = {}, 0
  for index, text in ipairs(spec.lines) do
    lines[index] = { text = text, color = spec.color }
    width = math.max(width, uji.width(text))
  end
  state.logo = uji.ui.open_win({ float = { width = width, height = #lines }, priority = 100 })
  uji.ui.set_lines(state.logo, lines)
  uji.on("message_appended", hide_logo, { name = "statusline.logo" })
  uji.on("session_resumed", function()
    if #uji.session.messages() > 0 then hide_logo() end
  end, { name = "statusline.logo" })
end

function M.render()
  for _, line in ipairs(state.lines) do
    uji.ui.set_lines(line.win, { row(line) })
  end
end

function M.setup(opts)
  opts = opts or {}
  state.sep = opts.separator or state.sep
  if opts.defaults ~= false then
    defaults()
  end
  state.lines, state.placed = layout(opts.lines or { { at = "below", left = { "*" }, priority = opts.priority } })
  for index = #state.lines, 1, -1 do
    if state.lines[index].spot.split == "bottom" then open(state.lines[index]) end
  end
  for _, line in ipairs(state.lines) do
    if line.spot.split == "top" then open(line) end
  end
  if opts.logo then
    show_logo(opts.logo)
  end
  uji.on("status_changed", M.render, { name = "statusline" })
  uji.on("message_appended", M.render, { name = "statusline" })
  M.render()
end

return M
