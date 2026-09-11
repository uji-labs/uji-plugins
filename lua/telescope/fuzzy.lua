local M = {}

-- Subsequence scorer: every needle char must appear in order.
-- Rewards consecutive runs and matches at word boundaries, penalises gaps.
function M.score(haystack, needle)
  if needle == "" then return 0 end
  local hay = haystack:lower()
  local want = needle:lower()
  local total, at, run = 0, 1, 0
  for i = 1, #want do
    local c = want:sub(i, i)
    local found = hay:find(c, at, true)
    if not found then return nil end
    if found == at and at > 1 then
      run = run + 1
      total = total + 12 + run
    else
      run = 0
      total = total + 1
      local prev = found > 1 and hay:sub(found - 1, found - 1) or "/"
      if prev:match("[/_%-%. ]") then total = total + 8 end
      total = total - math.min((found - at) * 2, 24)
    end
    at = found + 1
  end
  return total - math.floor((#hay - at) / 8)
end

function M.rank(items, query)
  local hits = {}
  for i, item in ipairs(items) do
    local s = M.score(item, query)
    if s then hits[#hits + 1] = { item = item, score = s, index = i } end
  end
  table.sort(hits, function(a, b)
    if a.score ~= b.score then return a.score > b.score end
    return a.index < b.index
  end)
  local out = {}
  for i, hit in ipairs(hits) do out[i] = hit.item end
  return out
end

return M
