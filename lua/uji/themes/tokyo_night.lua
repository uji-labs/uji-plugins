local ito = require("ito")

return require("uji.themes.default")({
  name = "tokyo_night",
  colors = {
    text = ito.rgb(0xc0caf5),
    muted = ito.rgb(0x737aa2),
    code = ito.rgb(0x9ece6a),
    accent = ito.rgb(0x7aa2f7),
    user_bg = ito.rgb(0x292e42),
    selected_bg = ito.rgb(0x283457),
    error = ito.rgb(0xf7768e),
    notice = ito.rgb(0xe0af68),
    link = ito.rgb(0x7dcfff),
    keyword = ito.rgb(0x9d7cd8),
    number = ito.rgb(0xff9e64),
    comment = ito.rgb(0x565f89),
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
