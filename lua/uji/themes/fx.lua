local ito = require("ito")

local C = ito.Color.indexed

local function railed(width, value)
  local ctx = value.ctx
  local rows = {}
  for index, chunk in ipairs(ctx:chunks(value.text, math.max(width - 2, 1))) do
    rows[index] = { { "┃ ", ctx.styles.highlight }, { chunk, ctx.styles.user } }
  end
  return rows
end

return require("uji.themes.default")({
  name = "fx",
  colors = {
    text = C(252),
    muted = C(245),
    code = C(250),
    accent = C(255),
    selected_bg = C(239),
    error = ito.rgb(0xe5484d),
    notice = C(252),
    link = C(75),
  },
  styles = function(c)
    local S = ito.TextStyle
    return {
      user = S({ foreground = c.text, bold = true }),
      link = S({ foreground = c.link }),
      code_keyword = S({ foreground = c.text }),
    }
  end,
  symbols = { tool = "●", pointer = "❯", prompt = "❯" },
  views = {
    [uji.ui.UserMessage] = function(props)
      return ito.Lines(railed, { ctx = ito.theme(), text = props.message.text or "" })
    end,
  },
})
