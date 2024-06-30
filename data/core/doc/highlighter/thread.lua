local Object = require "core.object"

---@class core.doc.highlighter.thread : core.object
---@field doc core.doc
---@field language_plugin string
---@field thread thread.Thread?
---@field thread_in thread.Channel
---@field thread_out thread.Channel
---@overload fun(doc:core.doc):core.doc.highlighter.thread
local HighlighterThread = Object:extend()

---@type table<string,boolean?>
local threadable_languages

---Check if a language can be run on a separate thread
---@param language_plugin string
function HighlighterThread.threadable_language(language_plugin)
  if not threadable_languages then
    threadable_languages = {}
    local plugin_dirs = {
      DATADIR .. PATHSEP .. "plugins",
      USERDIR .. PATHSEP .. "plugins"
    }
    for _, plugins_dir in ipairs(plugin_dirs) do
      local plugins = system.list_dir(plugins_dir)
      if plugins then
        for _, plugin in ipairs(plugins) do
          if plugin:match("^language_.*%.lua$") then
            local file = io.open(plugins_dir .. PATHSEP .. plugin)
            if file then
              local valid = true
              for required in file:read("*a"):gmatch("local%s+([%a_][%w_]*)%s*=%s*require") do
                if required ~= "syntax" then
                  valid = false
                  break
                end
              end
              file:close()
              if valid then
                threadable_languages[plugin:gsub("%.lua$", "")] = true
              end
            end
          end
        end
      end
    end
  end
  return threadable_languages[language_plugin]
end

---Function used as a thread for file tokenization
function HighlighterThread.tokenizer(language_plugin, doc_id, lines)
  local syntax = require "core.syntax"
  local common = require "core.common"
  local tokenizer = require "core.doc.highlighter.tokenizer"

  local plugin_dirs = {
    DATADIR .. PATHSEP .. "plugins",
    USERDIR .. PATHSEP .. "plugins"
  }

  -- Load valid
  for _, plugins_dir in ipairs(plugin_dirs) do
    local plugins = system.list_dir(plugins_dir)
    if plugins then
      for _, plugin in ipairs(plugins) do
        if plugin:match("^language_.*%.lua$") then
          local file = io.open(plugins_dir .. PATHSEP .. plugin)
          if file then
            local valid = true
            for required in file:read("*a"):gmatch("local%s+([%a_][%w_]*)%s*=%s*require") do
              if required ~= "syntax" then
                valid = false
                break
              end
            end
            if valid then
              require("plugins." .. plugin:gsub("%.lua$", ""))
            end
            file:close()
          end
        end
      end
    end
  end

  local function get_syntax(language_name)
    for _, syn in ipairs(syntax.items) do
      if syn.language_plugin == language_name then
        return syn
      end
    end
    return syntax.plain_text_syntax
  end

  local input = thread.get_channel("tokenizer_in_"..doc_id)
  local output = thread.get_channel("tokenizer_out_"..doc_id)
  local current_syntax = get_syntax(language_plugin)
  local from, to, state, states = 1, 0, nil, {}

  while(true) do
    local data = input:wait()
    input:pop()

    if data and type(data) == "table" then
      if data.name == "insert_lines" then
        -- print("inserting_lines")
        local insert_lines = {}
        for line in string.gmatch(data.lines, "([^\n]+)") do
          table.insert(insert_lines, line .. "\n")
        end
        common.splice(lines, math.floor(data.from), #insert_lines, insert_lines)
        from = math.min(from, math.floor(data.from))
        to = #lines
      elseif data.name == "remove_lines" then
        -- print("remove_lines")
        local line = {data.line}
        common.splice(lines, math.floor(data.from), math.floor(data.to), line)
        from = math.min(from, math.floor(data.from))
        to = #lines
      elseif data.name == "syntax" then
        current_syntax = get_syntax(data.language_plugin)
      elseif data.name == "tokenize" then
        to = math.max(math.floor(data.to), to)
      end
    elseif data == "stop" then
      return
    end

    if #lines > 0 and to > 0 and from <= to then
      local done = true
      for idx=from, to, 1 do
        if not lines[idx] then done = false break end
        local tokens, init_state
        init_state = idx > 1 and states[idx-1]
        tokens, state = tokenizer.tokenize(current_syntax, lines[idx], init_state)
        states[idx] = state
        output:push({
          idx = idx,
          line = {
            init_state = init_state,
            state = state,
            text = lines[idx],
            tokens = tokens
          }
        })
        from = from+1
        local event = input:first()
        if event == "stop" then
          return
        elseif event then
          done = false
          break
        end
      end
      if done then output:push("done") end
    end
  end
end

function HighlighterThread:new(doc)
  self.doc = doc
  self.language_plugin = self.doc.syntax and self.doc.syntax.language_plugin or ""
  self:update_thread()
end

local doc_id = 0

---Starts, stops the current thread or sends the current document syntax.
function HighlighterThread:update_thread()
  if not self.doc.syntax then return end
  if HighlighterThread.threadable_language(self.doc.syntax.language_plugin) then
    if self.thread and self.language_plugin == self.doc.syntax.language_plugin then
      return
    elseif self.thread then
      self.language_plugin = self.doc.syntax.language_plugin
      self.thread_in:push({
        name = "syntax",
        language_plugin = self.language_plugin
      })
      return
    end
    self.language_plugin = self.doc.syntax.language_plugin
    doc_id = doc_id + 1
    local id = tostring(doc_id)
    self.thread = thread.create(
      "highlighter_thread_"..id,
      HighlighterThread.tokenizer,
      self.doc.syntax.language_plugin,
      id,
      self.doc.lines
    )
    self.thread_in = thread.get_channel("tokenizer_in_"..id)
    self.thread_out = thread.get_channel("tokenizer_out_"..id)
    if #self.doc.lines > 0 then
      self.thread_in:push({
        name = "tokenize",
        from = 1,
        to = #self.doc.lines
      })
    end
  else
    self:stop()
  end
end

function HighlighterThread:stop()
  if self.thread then
    self.thread_in:push("stop")
    self.thread:wait()
    self.thread_in:clear()
    self.thread_out:clear()
    self.thread = nil
    self.thread_in = nil
    self.thread_out = nil
  end
end

function HighlighterThread:is_active()
  self:update_thread()
  if self.thread then return true end
  return false
end

---Inserts the fresh new lines into the thread
function HighlighterThread:insert_lines(from, n)
  if not self:is_active() then return end
  local lines = ""
  for idx = from, from+n do
    lines = lines .. self.doc:get_utf8_line(idx)
  end
  self.thread_in:push({
    name = "insert_lines",
    from = from,
    lines = lines
  })
end

---Remove a range of lines from the thread.
function HighlighterThread:remove_lines(from, n)
  if not self:is_active() then return end
  self.thread_in:push({
    name = "remove_lines",
    from = from,
    to = n + 1,
    line = self.doc:get_utf8_line(from)
  })
end

---Tell the thread to tokenize a range of lines.
---@param from integer
---@param to integer
function HighlighterThread:tokenize(from, to)
  if not self:is_active() then return end
  self.thread_in:push({
    name = "tokenize",
    from = from,
    to = to
  })
end

---Returns the next tokenized line by the thread or the word "done" if the
---thread finished tokenizing the file or nil if nothing was tokenized yet.
---@return table | nil | "done"
function HighlighterThread:get_next_line()
  if not self:is_active() then return "done" end
  local line = self.thread_out:first()
  if line then self.thread_out:pop() end
  if type(line) == "table" then line.idx = math.floor(line.idx) end
  return line
end


return HighlighterThread
