-- Make some tool roots read-only.
--
-- `uji.tool.roots` grants read AND write, because all the file tools share one
-- confinement check. That is usually wrong for reference material: you want the
-- agent to read a sibling repo, not edit it.
--
-- This denies writes into nominated roots, leaving reads alone. It is a guard
-- against the agent doing something unintended, not a security boundary --
-- the real confinement is in core, and this sits on top of it.
--
--   require("readonly").setup({ "~/reference/codex", "~/other-project" })

local M = {}

local WRITERS = {
  write_file = true,
  edit_file = true,
}

local roots = {}

local function expand(path)
  local home = os.getenv("HOME")
  if home and path:sub(1, 2) == "~/" then
    return home .. path:sub(2)
  end
  return path
end

-- Only absolute paths can land outside the session directory; a relative path
-- resolves against cwd, which is always writable.
local function under(path, root)
  if path == root then
    return true
  end
  return path:sub(1, #root + 1) == root .. "/"
end

function M.decide(name, args)
  if not WRITERS[name] then
    return nil
  end
  local path = args and args.path
  if type(path) ~= "string" or path:sub(1, 1) ~= "/" then
    return nil
  end
  for _, root in ipairs(roots) do
    if under(path, root) then
      return {
        deny = path
          .. " is in a read-only root ("
          .. root
          .. "). Read it if you need to, but make your changes in the working directory.",
      }
    end
  end
  return nil
end

function M.roots()
  return roots
end

function M.setup(paths, opts)
  opts = opts or {}
  roots = {}
  for _, path in ipairs(paths or {}) do
    roots[#roots + 1] = expand(path)
  end

  -- Ahead of the default policy so the refusal is explained, not just a prompt.
  uji.on("before_tool", function(event)
    return M.decide(event.name, event.arguments)
  end, { name = "readonly", priority = opts.priority or 20 })
end

return M
