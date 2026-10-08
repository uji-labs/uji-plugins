local ito = require("ito")

local C = ito.Color.indexed

local function railed(text)
  local ctx = ito.theme()
  return ito.HStack({
    ito.Text("┃"):style(ctx.styles.highlight):padding({ trailing = 1 }):repeating(),
    ito.Text(text):style(ctx.styles.user):wrap():grow(),
  })
end

local function screen(slots)
  local placement = ito.ToolbarPlacement
  return ito.VStack({
    ito.HStack({
      ito.ToolbarItems(placement.top_bar_leading, ito.HStack),
      ito.Spacer(),
      ito.ToolbarItems(placement.top_bar_trailing, ito.HStack),
    }),
    slots.transcript():grow(),
    slots.activity():padding({ vertical = 1 }),
    slots.modals(),
    ito.ToolbarItems(placement.keyboard),
    slots.composer(),
    ito.ToolbarItems(placement.bottom_bar),
  })
end

return require("uji.themes.default")({
  name = "fx",
  colors = {
    background = C(16),
    text = C(252),
    muted = C(245),
    code = C(250),
    accent = C(255),
    selected_bg = C(239),
    error = ito.rgb(0xe5484d),
    notice = C(252),
    link = C(75),
    syntax = {
      keyword = C(252),
      string = C(250),
      number = C(250),
      comment = C(245),
      func = C(255),
      type = C(252),
      constant = C(250),
    },
    diff = {
      added = C(77),
      removed = C(167),
      added_bg = C(22),
      removed_bg = C(52),
      added_word_bg = C(28),
      removed_word_bg = C(88),
    },
  },
  styles = function(c)
    local S = ito.TextStyle
    return {
      user = S({ foreground = c.text, bold = true }),
      link = S({ foreground = c.link }),
    }
  end,
  symbols = { tool = "●", pointer = "❯", prompt = "❯", input = "┃ " },
  views = {
    [uji.ui.Screen] = screen,
    [uji.ui.UserMessage] = function(props)
      return railed(props.message.text or "")
    end,
  },
})
