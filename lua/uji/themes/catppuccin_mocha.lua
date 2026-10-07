local ito = require("ito")

return require("uji.themes.default")({
  name = "catppuccin_mocha",
  colors = {
    background = ito.rgb(0x1e1e2e),
    text = ito.rgb(0xcdd6f4),
    muted = ito.rgb(0x7f849c),
    code = ito.rgb(0xa6e3a1),
    accent = ito.rgb(0xcba6f7),
    user_bg = ito.rgb(0x313244),
    selected_bg = ito.rgb(0x45475a),
    cursor = ito.rgb(0xf5e0dc),
    error = ito.rgb(0xf38ba8),
    notice = ito.rgb(0xf9e2af),
    link = ito.rgb(0x89b4fa),
    syntax = {
      keyword = ito.rgb(0xcba6f7),
      string = ito.rgb(0xa6e3a1),
      number = ito.rgb(0xfab387),
      comment = ito.rgb(0x9399b2),
      func = ito.rgb(0x89b4fa),
      type = ito.rgb(0xf9e2af),
      constant = ito.rgb(0xfab387),
    },
    diff = {
      added = ito.rgb(0xa6e3a1),
      removed = ito.rgb(0xf38ba8),
      added_bg = ito.rgb(0x404f4b),
      removed_bg = ito.rgb(0x53394c),
      added_word_bg = ito.rgb(0x5b7762),
      removed_word_bg = ito.rgb(0x7e4f65),
    },
  },
})
