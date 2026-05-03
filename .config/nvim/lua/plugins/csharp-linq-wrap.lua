local M = {}

local default_linq_methods = {
  "Aggregate",
  "All",
  "Any",
  "Append",
  "AsEnumerable",
  "Average",
  "Cast",
  "Chunk",
  "Concat",
  "Contains",
  "Count",
  "DefaultIfEmpty",
  "Distinct",
  "DistinctBy",
  "ElementAt",
  "ElementAtOrDefault",
  "Except",
  "ExceptBy",
  "First",
  "FirstOrDefault",
  "GroupBy",
  "GroupJoin",
  "Intersect",
  "IntersectBy",
  "Join",
  "Last",
  "LastOrDefault",
  "LongCount",
  "Max",
  "MaxBy",
  "Min",
  "MinBy",
  "OfType",
  "Order",
  "OrderBy",
  "OrderByDescending",
  "Prepend",
  "Reverse",
  "Select",
  "SelectMany",
  "SequenceEqual",
  "Single",
  "SingleOrDefault",
  "Skip",
  "SkipLast",
  "SkipWhile",
  "Sum",
  "Take",
  "TakeLast",
  "TakeWhile",
  "ThenBy",
  "ThenByDescending",
  "ToArray",
  "ToDictionary",
  "ToHashSet",
  "ToList",
  "ToLookup",
  "Union",
  "UnionBy",
  "Where",
  "Zip",

  -- EF Core / async LINQ
  "AllAsync",
  "AnyAsync",
  "AverageAsync",
  "ContainsAsync",
  "CountAsync",
  "FirstAsync",
  "FirstOrDefaultAsync",
  "LastAsync",
  "LastOrDefaultAsync",
  "LongCountAsync",
  "MaxAsync",
  "MinAsync",
  "SingleAsync",
  "SingleOrDefaultAsync",
  "SumAsync",
  "ToArrayAsync",
  "ToDictionaryAsync",
  "ToHashSetAsync",
  "ToListAsync",

  -- EF Core fluent
  "Include",
  "ThenInclude",
  "AsNoTracking",
  "AsNoTrackingWithIdentityResolution",
  "AsTracking",
  "AsSplitQuery",
  "AsSingleQuery",
  "IgnoreQueryFilters",
  "TagWith",
  "TagWithCallSite",
}

M.options = {
  -- 2 = rozbijaj dopiero, gdy w jednej linii są minimum 2 wywołania,
  -- np. .Where(...).Select(...)
  -- 1 = rozbijaj też pojedyncze .Any(...), .Where(...), itd.
  min_chain_calls = 2,

  -- false = rozbijaj tylko znane metody LINQ / EF z listy
  -- true = rozbijaj każde wywołanie metody po kropce, np. .Foo().Bar()
  split_all_method_chains = false,

  -- nil = użyj shiftwidth z bufora
  continuation_indent = nil,

  linq_methods = default_linq_methods,

  -- tutaj możesz dopisać własne metody fluent API
  extra_methods = {},
}

local function to_set(list)
  local set = {}

  for _, value in ipairs(list or {}) do
    set[value] = true
  end

  return set
end

local function is_ident_start(ch)
  return ch ~= nil and ch ~= "" and ch:match("[%a_]") ~= nil
end

local function is_ident_char(ch)
  return ch ~= nil and ch ~= "" and ch:match("[%w_]") ~= nil
end

local function skip_spaces(line, i)
  local len = #line

  while i <= len do
    local ch = line:sub(i, i)

    if ch ~= " " and ch ~= "\t" then
      break
    end

    i = i + 1
  end

  return i
end

local function parse_identifier(line, i)
  local len = #line

  if not is_ident_start(line:sub(i, i)) then
    return nil, i
  end

  local start = i
  i = i + 1

  while i <= len and is_ident_char(line:sub(i, i)) do
    i = i + 1
  end

  return line:sub(start, i - 1), i
end

local function skip_generic_args(line, i)
  if line:sub(i, i) ~= "<" then
    return i
  end

  local len = #line
  local depth = 0

  while i <= len do
    local ch = line:sub(i, i)

    if ch == "<" then
      depth = depth + 1
    elseif ch == ">" then
      depth = depth - 1

      if depth == 0 then
        return i + 1
      end
    elseif ch == '"' or ch == "'" then
      return nil
    end

    i = i + 1
  end

  return nil
end

local function looks_like_method_call_after_dot(line, dot_i, opts)
  local len = #line

  -- pomiń range operator: ..
  if line:sub(dot_i - 1, dot_i - 1) == "." or line:sub(dot_i + 1, dot_i + 1) == "." then
    return false
  end

  local name, i = parse_identifier(line, dot_i + 1)

  if not name then
    return false
  end

  if not opts.split_all_method_chains and not opts.method_set[name] then
    return false
  end

  i = skip_spaces(line, i)

  -- obsługa .Select<T>(...)
  if line:sub(i, i) == "<" then
    i = skip_generic_args(line, i)

    if not i then
      return false
    end

    i = skip_spaces(line, i)
  end

  if i > len then
    return false
  end

  return line:sub(i, i) == "("
end

local function find_candidates(line, opts, state)
  local candidates = {}
  local len = #line
  local i = 1
  local first_nonspace = line:find("%S") or (len + 1)

  state = state or "normal"

  while i <= len do
    local ch = line:sub(i, i)
    local next_ch = line:sub(i + 1, i + 1)

    if state == "normal" then
      if ch == "/" and next_ch == "/" then
        break
      elseif ch == "/" and next_ch == "*" then
        state = "block_comment"
        i = i + 2
      elseif ch == "$" and next_ch == "@" and line:sub(i + 2, i + 2) == '"' then
        state = "verbatim_string"
        i = i + 3
      elseif ch == "@" and next_ch == "$" and line:sub(i + 2, i + 2) == '"' then
        state = "verbatim_string"
        i = i + 3
      elseif ch == "@" and next_ch == '"' then
        state = "verbatim_string"
        i = i + 2
      elseif ch == "$" and next_ch == '"' then
        state = "string"
        i = i + 2
      elseif ch == '"' then
        state = "string"
        i = i + 1
      elseif ch == "'" then
        state = "char"
        i = i + 1
      elseif ch == "." then
        if looks_like_method_call_after_dot(line, i, opts) then
          local split_at = i

          -- null conditional:
          -- items
          --     ?.Where(...)
          if i > 1 and line:sub(i - 1, i - 1) == "?" then
            split_at = i - 1
          end

          table.insert(candidates, {
            dot = i,
            split_at = split_at,
            leading = split_at == first_nonspace,
          })
        end

        i = i + 1
      else
        i = i + 1
      end
    elseif state == "block_comment" then
      if ch == "*" and next_ch == "/" then
        state = "normal"
        i = i + 2
      else
        i = i + 1
      end
    elseif state == "string" then
      if ch == "\\" then
        i = i + 2
      elseif ch == '"' then
        state = "normal"
        i = i + 1
      else
        i = i + 1
      end
    elseif state == "verbatim_string" then
      if ch == '"' and next_ch == '"' then
        i = i + 2
      elseif ch == '"' then
        state = "normal"
        i = i + 1
      else
        i = i + 1
      end
    elseif state == "char" then
      if ch == "\\" then
        i = i + 2
      elseif ch == "'" then
        state = "normal"
        i = i + 1
      else
        i = i + 1
      end
    else
      state = "normal"
      i = i + 1
    end
  end

  return candidates, state
end

local function wrap_line(line, candidates, opts)
  if #candidates < opts.min_chain_calls then
    return line
  end

  local split_positions = {}
  local effective_splits = 0

  for _, candidate in ipairs(candidates) do
    -- nie dodawaj pustej linii, jeśli linia już zaczyna się od .Where / ?.Where
    if not candidate.leading then
      split_positions[candidate.split_at] = true
      effective_splits = effective_splits + 1
    end
  end

  if effective_splits == 0 then
    return line
  end

  local base_indent = line:match("^%s*") or ""
  local rest = line:sub(#base_indent + 1)
  local already_chain_line = rest:sub(1, 1) == "." or rest:sub(1, 2) == "?."

  local continuation_indent

  if already_chain_line then
    continuation_indent = base_indent
  else
    continuation_indent = base_indent .. opts.continuation_indent
  end

  local out = {}

  for i = 1, #line do
    if split_positions[i] then
      table.insert(out, "\n")
      table.insert(out, continuation_indent)
    end

    table.insert(out, line:sub(i, i))
  end

  return table.concat(out)
end

function M.format_range(line1, line2, runtime_opts)
  local opts = vim.tbl_deep_extend("force", vim.deepcopy(M.options), runtime_opts or {})

  if opts.force_single_call then
    opts.min_chain_calls = 1
  end

  local sw = vim.bo.shiftwidth

  if sw == 0 then
    sw = vim.bo.tabstop
  end

  if sw == 0 then
    sw = 4
  end

  opts.continuation_indent = opts.continuation_indent or string.rep(" ", sw)

  local all_methods = vim.deepcopy(opts.linq_methods or {})
  vim.list_extend(all_methods, opts.extra_methods or {})
  opts.method_set = to_set(all_methods)

  local buf = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(buf, line1 - 1, line2, false)

  local new_lines = {}
  local state = "normal"

  for _, line in ipairs(lines) do
    local candidates
    candidates, state = find_candidates(line, opts, state)

    local wrapped = wrap_line(line, candidates, opts)
    local parts = vim.split(wrapped, "\n", { plain = true })

    for _, part in ipairs(parts) do
      table.insert(new_lines, part)
    end
  end

  local view = vim.fn.winsaveview()
  vim.api.nvim_buf_set_lines(buf, line1 - 1, line2, false, new_lines)
  vim.fn.winrestview(view)
end

function M.setup(user_opts)
  M.options = vim.tbl_deep_extend("force", M.options, user_opts or {})

  pcall(vim.api.nvim_del_user_command, "CSharpWrapLinq")
  pcall(vim.keymap.del, "n", "<leader>cl")
  pcall(vim.keymap.del, "x", "<leader>cl")

  vim.api.nvim_create_user_command("CSharpWrapLinq", function(cmd)
    M.format_range(cmd.line1, cmd.line2, {
      force_single_call = cmd.bang,
    })
  end, {
    range = "%",
    bang = true,
    desc = "Wrap C# LINQ / fluent chains into separate lines",
  })

  vim.keymap.set("n", "<leader>cl", "<cmd>CSharpWrapLinq<cr>", {
    desc = "C# wrap LINQ chains",
  })

  vim.keymap.set("x", "<leader>cl", ":CSharpWrapLinq<cr>", {
    desc = "C# wrap selected LINQ chains",
  })
end

M.setup({
  -- 2 = tylko gdy są minimum dwa wywołania w chainie
  -- 1 = rozbijaj też pojedyncze .Any(...), .Where(...), itd.
  min_chain_calls = 2,

  -- false = tylko LINQ / EF z listy
  -- true = każde .Method(...)
  split_all_method_chains = false,

  extra_methods = {
    -- dopisz swoje metody, jeśli chcesz
    -- "MyCustomMethod",
  },
})

return {}
