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
    keyword = ito.rgb(0x81a1c1),
    number = ito.rgb(0xb48ead),
    comment = ito.rgb(0x616e88),
  },
})
