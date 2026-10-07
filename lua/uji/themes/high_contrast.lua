local ito = require("ito")

return require("uji.themes.default")({
  name = "high_contrast",
  colors = {
    background = ito.rgb(0x000000),
    text = ito.rgb(0xffffff),
    muted = ito.rgb(0xd0d0d0),
    code = ito.rgb(0x00ffff),
    accent = ito.rgb(0xffff00),
    user_bg = ito.rgb(0xffffff),
    selected_bg = ito.rgb(0xffff00),
    error = ito.rgb(0xff6060),
    notice = ito.rgb(0xffff00),
    link = ito.rgb(0x00ffff),
    ink = ito.rgb(0x000000),
    syntax = {
      keyword = ito.rgb(0xffff00),
      string = ito.rgb(0x00ffff),
      number = ito.rgb(0xff80ff),
      comment = ito.rgb(0xd0d0d0),
      func = ito.rgb(0x80ff80),
      type = ito.rgb(0xffb000),
      constant = ito.rgb(0xff80ff),
    },
    diff = {
      added = ito.rgb(0x00ff00),
      removed = ito.rgb(0xff6060),
      added_bg = ito.rgb(0x005900),
      removed_bg = ito.rgb(0x592222),
      added_word_bg = ito.rgb(0x009900),
      removed_word_bg = ito.rgb(0x993a3a),
    },
  },
  styles = function(c)
    local S = ito.TextStyle
    return {
      dim = S({ foreground = c.muted }),
      faint = S({ foreground = c.muted }),
      system = S({ foreground = c.muted }),
      emphasis = S({ underline = true }),
      user = S({ foreground = c.ink, background = c.user_bg }),
      selected = S({ foreground = c.ink, background = c.selected_bg }),
      chosen = S({ foreground = c.ink, background = c.selected_bg, bold = true }),
      chosen_name = S({ foreground = c.ink, background = c.selected_bg, bold = true }),
      chosen_desc = S({ foreground = c.ink, background = c.selected_bg }),
      border = S({ foreground = c.text }),
      confirm_selected = S({ foreground = c.accent, bold = true, underline = true }),
    }
  end,
})
