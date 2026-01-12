-- Put mentees here (as they will appear in the author list)
local mentee_names = {
  -- examples:
  -- { last = "Hawkins", first = "P. S." },
  -- { last = "Pierre",  first = "S." }
}

local function is_space(x)
  return x and (x.t == "Space" or x.t == "SoftBreak")
end

local function is_str(x)
  return x and x.t == "Str"
end

local function str_text(x)
  return (is_str(x) and x.text) or ""
end

local function escape_lua_pattern(s)
  return (s:gsub("([^%w])", "%%%1"))
end

-- Match surname token at position i (handles Dellinger, Dellinger*, with or without comma)
local function match_surname(inlines, i, surname)
  if not is_str(inlines[i]) then return nil end
  local t = inlines[i].text

  -- allow optional star, optional trailing comma
  local base = "^" .. escape_lua_pattern(surname) .. "%*?,?$"
  if not t:match(base) then return nil end

  local j = i

  -- if comma is NOT in the same token, allow a following comma token
  if not t:match(",$") and is_str(inlines[j + 1]) and inlines[j + 1].text == "," then
    j = j + 1
  end

  return j
end

-- Match initials starting at i, return end index
-- Accepts "R. J.", "R.J.", and also "R." + "J." split
local function match_initials_RJ(inlines, i)
  if not inlines[i] then return nil end

  -- Case 1: single token like "R. J." or "R.J."
  if is_str(inlines[i]) then
    local t = inlines[i].text
    if t:match("^R%.%s*J%.") or t:match("^R%.J%.") then
      return i
    end
  end

  -- Case 2: "R." [space] "J."
  if is_str(inlines[i]) and str_text(inlines[i]) == "R." then
    local j = i
    if is_space(inlines[j + 1]) then j = j + 1 end
    if is_str(inlines[j + 1]) and str_text(inlines[j + 1]):match("^J%.") then
      return j + 1
    end
  end

  return nil
end

-- Generic matcher for mentee initials like "P. S." or "S." etc
local function match_initials_prefix(inlines, i, first_prefix)
  if not inlines[i] then return nil end

  -- If citeproc kept it in one token
  if is_str(inlines[i]) then
    if inlines[i].text:match("^" .. escape_lua_pattern(first_prefix)) then
      return i
    end
  end

  -- If split across tokens, approximate by stringifying the next few Str/Space nodes
  local acc = {}
  local j = i
  local steps = 0
  while inlines[j] and steps < 8 do
    if is_str(inlines[j]) then table.insert(acc, inlines[j].text)
    elseif is_space(inlines[j]) then table.insert(acc, " ")
    else break end
    local joined = table.concat(acc)
    if joined:match("^" .. escape_lua_pattern(first_prefix)) then
      return j
    end
    j = j + 1
    steps = steps + 1
  end

  return nil
end

local function wrap_range(inlines, i, j, wrapper)
  local slice = {}
  for k = i, j do table.insert(slice, inlines[k]) end
  local repl = wrapper(slice)

  local out = {}
  for k = 1, i - 1 do table.insert(out, inlines[k]) end
  table.insert(out, repl)
  for k = j + 1, #inlines do table.insert(out, inlines[k]) end
  return out
end

function Inlines(inlines)
  local i = 1
  while i <= #inlines do

    -- Bold Dellinger, R. J. (and Dellinger*, R. J.)
    do
      local s_end = match_surname(inlines, i, "Dellinger")
      if s_end then
        local k = s_end + 1
        while is_space(inlines[k]) do k = k + 1 end
        local init_end = match_initials_RJ(inlines, k)
        if init_end then
          inlines = wrap_range(inlines, i, init_end, function(slice)
            return pandoc.Strong(slice)
          end)
          i = i + 1
          goto continue
        end
      end
    end

    -- Underline mentee names: "Lastname, X. Y."
    if is_str(inlines[i]) then
      for _, mentee in ipairs(mentee_names) do
        local s_end = match_surname(inlines, i, mentee.last)
        if s_end then
          local k = s_end + 1
          while is_space(inlines[k]) do k = k + 1 end
          local init_end = match_initials_prefix(inlines, k, mentee.first)
          if init_end then
            inlines = wrap_range(inlines, i, init_end, function(slice)
              local txt = pandoc.utils.stringify(slice)
              return pandoc.RawInline("latex", "\\underline{" .. txt .. "}")
            end)
            i = i + 1
            goto continue
          end
        end
      end
    end

    ::continue::
    i = i + 1
  end
  return inlines
end