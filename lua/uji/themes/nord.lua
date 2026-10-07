local ito = require("ito")

return require("uji.themes.default")({
  name = "nord",
  colors = {
    background = ito.rgb(0x2e3440),
    text = ito.rgb(0xd8dee9),
    muted = ito.rgb(0x7b88a1),
    code = ito.rgb(0xa3be8c),
    accent = ito.rgb(0x88c0d0),
    user_bg = ito.rgb(0x3b4252),
    selected_bg = ito.rgb(0x434c5e),
    error = ito.rgb(0xbf616a),
    notice = ito.rgb(0xebcb8b),
    link = ito.rgb(0x81a1c1),
    syntax = {
      keyword = ito.rgb(0x81a1c1),
      string = ito.rgb(0xa3be8c),
      number = ito.rgb(0xb48ead),
      comment = ito.rgb(0x616e88),
      func = ito.rgb(0x88c0d0),
      type = ito.rgb(0x8fbcbb),
      constant = ito.rgb(0xb48ead),
    },
    diff = {
      added = ito.rgb(0xa3be8c),
      removed = ito.rgb(0xbf616a),
      added_bg = ito.rgb(0x4b5653),
      removed_bg = ito.rgb(0x523f4a),
      added_word_bg = ito.rgb(0x637262),
      removed_word_bg = ito.rgb(0x6f4853),
    },
  },
})
