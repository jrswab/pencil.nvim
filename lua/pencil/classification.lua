local M = {}

function M.normalize(name)
  return tostring(name or ""):gsub("([a-z0-9])([A-Z])", "%1_%2"):lower():gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
end

function M.combine(ts, syntax)
  if ts == "prose" and syntax ~= "protected" then return "prose" end
  if ts == "protected" and syntax ~= "prose" then return "protected" end
  if syntax == "prose" and ts == "unknown" then return "prose" end
  if syntax == "protected" and ts == "unknown" then return "protected" end
  return ts == syntax and ts or "unknown"
end

function M.has_delimiter(bytes, delimiters)
  for i = 1, #bytes do
    for _, delimiter in ipairs(delimiters) do
      if bytes:byte(i) == delimiter then return true end
    end
  end
  return false
end

local protected = { align=true, align_=true, alignat=true, alignat_=true, bmatrix=true, cases=true, comment=true, displaymath=true, equation=true, equation_=true, filecontents=true, filecontents_=true, flalign=true, flalign_=true, gather=true, gather_=true, lstlisting=true, listing=true, math=true, matrix=true, minted=true, multline=true, multline_=true, pmatrix=true, split=true, thebibliography=true, verbatim=true, verbatim_=true, vmatrix=true, xalignat=true, xalignat_=true, xxalignat=true, xxalignat_=true }
local prose = { document=true, abstract=true, quote=true, quotation=true, verse=true, center=true, flushleft=true, flushright=true }

function M.tex_environment_result(name)
  name = M.normalize(name)
  if protected[name] then return "protected" end
  if prose[name] then return "prose" end
  return "unknown"
end

function M.tex_environment(text)
  local stack, outer, found, position = {}, nil, false, 1
  while true do
    local bs, be, begin_name = text:find("\\begin%s*{%s*([%a][%w_-]*)%s*}", position)
    local es, ee, end_name = text:find("\\end%s*{%s*([%a][%w_-]*)%s*}", position)
    if not bs and not es then break end
    if es and (not bs or es < bs) then
      end_name = M.normalize(end_name)
      if stack[#stack] ~= end_name then return "unknown" end
      stack[#stack] = nil; position = ee + 1
    else
      local name = M.normalize(begin_name)
      outer = outer or name
      stack[#stack + 1] = name
      found = true; position = be + 1
    end
  end
  if not found or #stack ~= 0 then return "unknown" end
  local name = outer
  for nested in text:gmatch("\\begin%s*{%s*([%a][%w_-]*)%s*}") do
    if M.tex_environment_result(nested) == "protected" then return "protected" end
  end
  return M.tex_environment_result(name)
end

function M.reduce_treesitter(records)
  local result
  for _, evidence in ipairs(records or {}) do
    if evidence ~= "prose" and evidence ~= "protected" then return "unknown" end
    if result and result ~= evidence then return "unknown" end
    result = evidence
  end
  return result or "unknown"
end

return M
