local ito = require("ito")

return require("uji.themes.default")({
  name = "gruvbox_dark",
  colors = {
    background = ito.rgb(0x282828),
    text = ito.rgb(0xebdbb2),
    muted = ito.rgb(0xa89984),
    code = ito.rgb(0xb8bb26),
    accent = ito.rgb(0xfabd2f),
    user_bg = ito.rgb(0x3c3836),
    selected_bg = ito.rgb(0x504945),
    error = ito.rgb(0xfb4934),
    notice = ito.rgb(0xfe8019),
    link = ito.rgb(0x83a598),
    syntax = {
      keyword = ito.rgb(0xfb4934),
      string = ito.rgb(0xb8bb26),
      number = ito.rgb(0xd3869b),
      comment = ito.rgb(0x928374),
      func = ito.rgb(0x8ec07c),
      type = ito.rgb(0xfabd2f),
      constant = ito.rgb(0xd3869b),
    },
    diff = {
      added = ito.rgb(0xb8bb26),
      removed = ito.rgb(0xfb4934),
      added_bg = ito.rgb(0x4c4d28),
      removed_bg = ito.rgb(0x5d302b),
      added_word_bg = ito.rgb(0x696a27),
      removed_word_bg = ito.rgb(0x87372d),
    },
  },
})
