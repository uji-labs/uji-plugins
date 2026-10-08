local ito = require("ito")

local C = ito.Color.indexed
local rgb = ito.rgb

local function railed(text)
  local ctx = ito.theme()
  return ito.HStack({
    ito.Text("┃"):style(ctx.styles.highlight):padding({ trailing = 1 }):repeating(),
    ito.Text(text):style(ctx.styles.user):wrap():grow(),
  })
end

local function header()
  local styles = ito.theme().styles
  return ito.Text({ { "uji", styles.heading1 }, { " · Run /help for commands", styles.muted } })
end

local function screen(slots)
  local placement = ito.ToolbarPlacement
  return ito.VStack({
    ito.HStack({
      header(),
      ito.ToolbarItems(placement.top_bar_leading, ito.HStack),
      ito.Spacer(),
      ito.ToolbarItems(placement.top_bar_trailing, ito.HStack),
    }):spacing(1),
    ito.Spacer():height(1),
    slots.transcript():grow(),
    slots.activity():padding({ vertical = 1 }),
    slots.modals(),
    ito.ToolbarItems(placement.keyboard),
    slots.composer(),
    ito.Spacer():height(1),
    ito.ToolbarItems(placement.bottom_bar),
  })
end

local function code_block(props)
  local ctx = ito.theme()
  local rule, dim = ctx.symbols.rule, ctx.styles.dim
  return ito.VStack({
    ito.HStack({
      ito.Text(rule):style(dim),
      props.language ~= nil and ito.Text(props.language):style(dim),
      ito.Text(rule):style(dim):repeating():grow(),
    }):spacing(1):padding({ leading = 2 }),
    uji.ui.Code(props),
    ito.Text(rule):style(dim):repeating():padding({ leading = 2 }),
  })
end

return require("uji.themes.default")({
  name = "fx",
  colors = {
    background = rgb(0x000000),
    text = C(252),
    muted = C(245),
    code = rgb(0x75c7f0),
    accent = C(255),
    selected_bg = rgb(0x2a2a2a),
    error = rgb(0xe5484d),
    notice = C(252),
    link = rgb(0x70b8ff),
    syntax = {
      keyword = rgb(0xe796f3),
      string = rgb(0x3dd68c),
      number = rgb(0xffa057),
      comment = rgb(0x6e6e6e),
      func = rgb(0x70b8ff),
      type = rgb(0x0bd8b6),
      constant = rgb(0xffca16),
    },
    call = {
      done = C(255),
    },
    diff = {
      added = rgb(0x30a46c),
      removed = rgb(0xe5484d),
      added_bg = rgb(0x132d21),
      removed_bg = rgb(0x3b1219),
      added_word_bg = rgb(0x174933),
      removed_word_bg = rgb(0x611623),
    },
  },
  styles = function(c)
    local S = ito.TextStyle
    return {
      user = S({ foreground = c.text, bold = true }),
      link = S({ foreground = c.link }),
    }
  end,
  symbols = { tool = "●", pointer = "❯", prompt = "❯", input = "┃" },
  limits = { reply_margin = 2 },
  views = {
    [uji.ui.Screen] = screen,
    [uji.ui.UserMessage] = function(props)
      return railed(props.message.text or "")
    end,
    [uji.ui.CodeBlock] = code_block,
  },
})
