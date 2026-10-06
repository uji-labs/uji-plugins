local ito = require("ito")

return require("uji.themes.default")({
  name = "gruvbox_dark",
  colors = {
    text = ito.rgb(0xebdbb2),
    muted = ito.rgb(0xa89984),
    code = ito.rgb(0xb8bb26),
    accent = ito.rgb(0xfabd2f),
    user_bg = ito.rgb(0x3c3836),
    selected_bg = ito.rgb(0x504945),
    error = ito.rgb(0xfb4934),
    notice = ito.rgb(0xfe8019),
    link = ito.rgb(0x83a598),
    keyword = ito.rgb(0xfb4934),
    number = ito.rgb(0xd3869b),
    comment = ito.rgb(0x928374),
  },
  styles = function(c)
    local S = ito.TextStyle
    return {
      link = S({ foreground = c.link, underline = true }),
      code_keyword = S({ foreground = c.keyword }),
      code_number = S({ foreground = c.number }),
      code_comment = S({ foreground = c.comment, italic = true }),
    }
  end,
})
