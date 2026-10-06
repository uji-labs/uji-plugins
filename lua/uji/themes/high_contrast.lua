local ito = require("ito")

return require("uji.themes.default")({
  name = "high_contrast",
  colors = {
    text = ito.rgb(0xffffff),
    muted = ito.rgb(0xd0d0d0),
    code = ito.rgb(0x00ffff),
    accent = ito.rgb(0xffff00),
    user_bg = ito.rgb(0xffffff),
    selected_bg = ito.rgb(0xffff00),
    error = ito.rgb(0xff6060),
    notice = ito.rgb(0xffff00),
    ink = ito.rgb(0x000000),
  },
  styles = function(c)
    local S = ito.TextStyle
    return {
      dim = S({ foreground = c.muted }),
      faint = S({ foreground = c.muted }),
      system = S({ foreground = c.muted }),
      code_comment = S({ foreground = c.muted }),
      emphasis = S({ underline = true }),
      user = S({ foreground = c.ink, background = c.user_bg }),
      selected = S({ foreground = c.ink, background = c.selected_bg }),
      chosen = S({ foreground = c.ink, background = c.selected_bg, bold = true }),
      chosen_name = S({ foreground = c.ink, background = c.selected_bg, bold = true }),
      chosen_desc = S({ foreground = c.ink, background = c.selected_bg }),
      border = S({ foreground = c.text }),
      link = S({ foreground = c.code, underline = true }),
      confirm_selected = S({ foreground = c.accent, bold = true, underline = true }),
    }
  end,
})
