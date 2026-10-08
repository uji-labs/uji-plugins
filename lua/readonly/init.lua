-- Make some directories read-only.
--
-- This denies edits and writes inside nominated directories, leaving reads
-- alone, so the agent can read a sibling repo without changing it. It is a
-- guard against the agent doing something unintended, not a security boundary.
--
--   require("readonly").setup({ "~/reference/codex", "~/other-project" })
--   require("readonly").setup({ paths = { "~/reference/codex" } })

local M = {}

-- Also takes one table, setup({ paths = { ... } }), which is what uji's Nix
-- module writes.
function M.setup(paths)
  if type(paths) == "table" and paths[1] == nil then
    paths = paths.paths
  end
  local rules = {}
  for _, path in ipairs(paths or {}) do
    local root = path:gsub("[/\\]+$", "")
    rules[#rules + 1] = {
      pattern = root .. "/**",
      message = root .. " is read-only. Read it if you need to, but make your changes in the working directory.",
    }
  end
  uji.tool.policy({ edit_file = { deny = rules }, write_file = { deny = rules } }, { name = "readonly" })
end

return M
