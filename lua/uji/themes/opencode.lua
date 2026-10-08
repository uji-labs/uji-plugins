local ito = require("ito")

local rgb = ito.rgb

local LOGO = {
  { "██    ██", "        ██  ██" },
  { "██    ██", "        ██  ██" },
  { "██    ██", "        ██  ██" },
  { "██    ██", "  ██    ██  ██" },
  { "  ████  ", "    ████    ██" },
}

local function logo()
  local styles = ito.theme().styles
  local spans = {}
  for index, row in ipairs(LOGO) do
    if index > 1 then
      spans[#spans + 1] = { "\n" }
    end
    spans[#spans + 1] = { row[1], styles.muted }
    spans[#spans + 1] = { row[2], styles.text }
  end
  return ito.Text(spans)
end

local function greeting()
  local styles = ito.theme().styles
  return ito.VStack({
    logo():align(ito.Alignment.center),
    ito.Text({
      { "● Tip", styles.tip },
      { " Run ", styles.muted },
      { "/help", styles.text },
      { " to see what uji can do", styles.muted },
    }):align(ito.Alignment.center),
  }):spacing(2)
end

local function prompt(content)
  local styles = ito.theme().styles
  return ito.VStack({
    ito.HStack({
      ito.Text("┃"):style(styles.bar):repeating(),
      content:padding({ vertical = 1, horizontal = 1 }):grow(),
    }):background(styles.panel),
    ito.HStack({ ito.Text("╹"):style(styles.bar), ito.Text("▀"):style(styles.edge):repeating():grow() }),
  })
end

local function user(props)
  local styles = ito.theme().styles
  return ito.HStack({
    ito.Text("┃"):style(styles.bar):repeating(),
    ito.Text(props.message.text or ""):style(styles.text):wrap():padding({ vertical = 1, horizontal = 2 }):grow(),
  }):background(styles.user)
end

local function screen(parts)
  local placement = ito.ToolbarPlacement
  return ito.VStack({
    ito.HStack({
      ito.ToolbarItems(placement.top_bar_leading, ito.HStack),
      ito.Spacer(),
      ito.ToolbarItems(placement.top_bar_trailing, ito.HStack),
    }),
    ito.ZStack({ parts.transcript():grow(), parts.greeting() }):grow(),
    parts.activity():padding({ vertical = 1 }),
    parts.modals(),
    ito.ToolbarItems(placement.keyboard, ito.HStack),
    prompt(parts.composer()),
    ito.ToolbarItems(placement.bottom_bar),
  }):padding({ horizontal = 2 })
end

return require("uji.themes.default")({
  name = "opencode",
  colors = {
    background = rgb(0x0a0a0a),
    text = rgb(0xeeeeee),
    muted = rgb(0x808080),
    code = rgb(0x7fd88f),
    accent = rgb(0x9d7cd8),
    user_bg = rgb(0x141414),
    selected_bg = rgb(0x1e1e1e),
    cursor = rgb(0xeeeeee),
    error = rgb(0xe06c75),
    notice = rgb(0xf5a742),
    link = rgb(0x5c9cf5),
    panel = rgb(0x1e1e1e),
    bar = rgb(0x5c9cf5),
    tip = rgb(0xf5a742),
    strong = rgb(0xf5a742),
    syntax = {
      keyword = rgb(0x9d7cd8),
      string = rgb(0x7fd88f),
      number = rgb(0xf5a742),
      comment = rgb(0x808080),
      func = rgb(0xfab283),
      type = rgb(0xe5c07b),
      constant = rgb(0xf5a742),
    },
    call = {
      done = rgb(0x808080),
    },
    diff = {
      added = rgb(0xb8db87),
      removed = rgb(0xe26a75),
      added_bg = rgb(0x1b2b34),
      removed_bg = rgb(0x2d1f26),
      added_word_bg = rgb(0x20303b),
      removed_word_bg = rgb(0x37222c),
    },
  },
  styles = function(c)
    local S = ito.TextStyle
    return {
      user = S({ foreground = c.text, background = c.user_bg }),
      strong = S({ foreground = c.strong, bold = true }),
      table_head = S({ foreground = c.accent, bold = true }),
      link = S({ foreground = c.link }),
      panel = S({ background = c.panel }),
      bar = S({ foreground = c.bar }),
      edge = S({ foreground = c.panel }),
      tip = S({ foreground = c.tip }),
    }
  end,
  symbols = { tool = "→", bullets = { "-", "-", "-" } },
  limits = { reply_margin = 3 },
  views = {
    [uji.ui.Screen] = screen,
    [uji.ui.Greeting] = greeting,
    [uji.ui.UserMessage] = user,
  },
})
