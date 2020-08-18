local U = require 'snippets.common'
local parser = require 'snippets.parser'
local vim = vim
local api = vim.api
local nvim_get_current_line = api.nvim_get_current_line
local format = string.format
local concat = table.concat
local insert = table.insert
local min = math.min

local function identity1(x) return x.v end

local function get_line_indent()
  return nvim_get_current_line():match("^%s+") or ""
end

local function get_line_comment()
  local cms = vim.bo.commentstring
  -- This whole pesc dance is a bummer.
  local pattern = "^(%s*)"..
    (U.find_sub(vim.pesc((U.find_sub(cms, "\0", "%s", 1, true))), "(%s*).*", "\0", 1, true))
  local pre_ws, inner_ws = nvim_get_current_line():match(pattern)
  if pre_ws then
    return pre_ws..cms:format("")..inner_ws
  end
  return ""
end

local function once(fn, N)
  assert(type(fn) == 'function')
  local value
  return function(...)
    if not value then value = {fn(...)} end
    return unpack(value, 1, N or #value)
  end
end

local function into_snippet(s)
  if type(s) == 'string' then
    s = parser.parse_snippet(s)
  end
  return U.make_snippet(s)
end

local function lowest_id(s)
  assert(U.is_snippet(s))
  local id
  for i, v in ipairs(s) do
    if U.is_variable(v) then
      if id then
        id = min(v.id, id)
      else
        id = v.id
      end
    end
  end
  if id and id >= 0 then
    return -1
  end
  return id or -1
end

local function prefix_new_lines_with_function(s, fn)
  local S = into_snippet(s)
  local prefix_var = U.make_preorder_function_component(fn)
  -- Use a unique negative number so it's evaluated first.
  prefix_var.id = lowest_id(S) - 1
  local R = {}
  for _, v in ipairs(S) do
    if type(v) == 'string' then
      local lines = vim.split(v, '\n', true)
      insert(R, lines[1])
      for i = 2, #lines do
        insert(R, '\n')
        insert(R, prefix_var)
        insert(R, lines[i])
      end
    else
      local existing_transform = v.transform or identity1
      -- Add prefix to any variables which have NLs.
      v.transform = function(S)
        -- Lookup the existing prefix created by our variable.
        local prefix = S[prefix_var.id]
        local value = existing_transform(S)
        local lines = vim.split(value, '\n', true)
        for i = 2, #lines do
          lines[i] = prefix..lines[i]
        end
        return concat(lines, '\n')
      end
      insert(R, v)
    end
  end
  return U.make_snippet(R), prefix_var
end

local function match_indentation(s)
  return prefix_new_lines_with_function(s, get_line_indent)
end

local function match_comment(s)
  return prefix_new_lines_with_function(s, get_line_comment)
end

local function force_comment(s)
  local function get_comment_prefix()
    -- Add an extra space to it.
    return vim.bo.commentstring:format(""):gsub("%S$", "%0 ")
  end
  local S = prefix_new_lines_with_function(s, get_comment_prefix)
  insert(S, 1, U.make_preorder_function_component(function()
    local comment = get_line_comment()
    if comment ~= "" then
      return ""
    end
    return get_comment_prefix()
  end))
  return S
end

local function match_comment_or_indentation(s)
  return prefix_new_lines_with_function(s, function()
    local comment = get_line_comment()
    if comment == "" then
      return get_line_indent()
    end
    return comment
  end)
end

return {
  match_indentation = match_indentation;
  match_comment = match_comment;
  force_comment = force_comment;
  match_comment_or_indentation = match_comment_or_indentation;
  into_snippet = into_snippet;
  lowest_id = lowest_id;
  prefix_new_lines_with_function = prefix_new_lines_with_function;
}
