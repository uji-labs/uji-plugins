local ito = require("ito")

local M = {}

local CROWDED = 80
local SEPARATOR = "  ·  "

local LOGO = {
  "██    ██        ██  ██",
  "██    ██        ██  ██",
  "██    ██        ██  ██",
  "██    ██  ██    ██  ██",
  "  ████      ████    ██",
}

local function muted(text)
  return ito.Text(text):foreground(ito.theme().colors.muted)
end

local function bold(text, colour)
  return ito.Text(text):foreground(colour):bold()
end

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

M.Cwd = ito.view(function()
  local dir = uji.session.info().short_directory
  return dir ~= "" and bold(dir, ito.theme().colors.accent)
end)

M.Model = ito.view(function()
  local current = uji.model.current()
  return current.name ~= nil and bold(current.model, ito.theme().colors.text)
end)

M.Effort = ito.view(function()
  local effort = uji.model.current().effort
  return effort ~= nil and effort ~= "off" and bold(effort .. " effort", ito.theme().colors.syntax.constant)
end)

M.Context = ito.view(function()
  local ctx = uji.session.context()
  if not ctx.window or ctx.window == 0 then return false end
  local pct = math.floor(ctx.used / ctx.window * 100 + 0.5)
  local colors = ito.theme().colors
  return bold(string.format("context %d%%", pct), pct >= CROWDED and colors.notice or colors.syntax.string)
end)

M.Tokens = ito.view(function()
  local usage = uji.session.usage()
  local fresh = usage.input + usage.cache_write + usage.output
  return fresh > 0 and muted(compact(fresh) .. " tok")
end)

M.Cache = ito.view(function()
  local last = uji.session.usage().last
  local prefix = last.input + last.cache_read + last.cache_write
  return last.cache_read > 0 and prefix > 0
    and muted(string.format("cache %d%%", math.floor(last.cache_read / prefix * 100 + 0.5)))
end)

M.Turns = ito.view(function()
  local turns = 0
  for _, message in ipairs(uji.session.messages()) do
    if message.type == "user" then turns = turns + 1 end
  end
  return turns > 0 and muted(turns .. (turns == 1 and " turn" or " turns"))
end)

M.Bar = ito.view(function(props)
  return ito.Subviews(props, function(subviews)
    local row = {}
    for index, subview in ipairs(subviews) do
      local before = subviews[index - 1]
      if before and not before.weight and not subview.weight then
        row[#row + 1] = muted(props.separator or SEPARATOR):dim()
      end
      row[#row + 1] = subview
    end
    return ito.HStack(row):padding({ horizontal = 1 }):height(1)
  end)
end)

M.Default = ito.view(function()
  return M.Bar({ M.Cwd(), M.Model(), M.Effort(), ito.Spacer(), M.Context() })
end)

M.Logo = ito.view(function()
  return #uji.session.messages() == 0 and ito.Text(table.concat(LOGO, "\n")):foreground(ito.theme().colors.accent)
end)

function M.setup()
  if M.shown then
    M.shown:remove()
  end
  M.shown = uji.ui.toolbar({ ito.ToolbarItem(ito.ToolbarPlacement.bottom_bar, M.Default) })
end

return M
