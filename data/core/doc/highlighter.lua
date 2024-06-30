local core = require "core"
local config = require "core.config"
local common = require "core.common"
local tokenizer = require "core.tokenizer"
local Object = require "core.object"
local HighlighterThread = require "core.doc.highlighter.thread"


local Highlighter = Object:extend()


function Highlighter:new(doc)
  self.doc = doc
  self.running = false
  self.thread = HighlighterThread(self.doc)
  self:reset()
end

-- init incremental syntax highlighting
function Highlighter:start()
  if self.running then return end
  self.running = true
  self.thread:tokenize(self.first_invalid_line, self.max_wanted_line)
  print("wanted", self.first_invalid_line, self.max_wanted_line)
  core.add_thread(function()
    if self.thread:is_active() then
      print "running"
      local tokenized, valid_lines = 0, true
      local start_time = system.get_time()
      while true do
        local output = self.thread:get_next_line()
        if type(output) == "table" then
          if output.line.text == self.doc:get_utf8_line(output.idx) then
            tokenized = output.idx
            self.first_invalid_line = output.idx + 1
            self.lines[output.idx] = output.line
            self:update_notify(output.idx, 0)
          else
            valid_lines = false
            print("not updating line", output.idx, self.doc.abs_filename)
          end
        elseif output == "done" then
          if valid_lines then
            if tokenized >= self.max_wanted_line then
              print("stop")
              self.max_wanted_line = 0
              self.running = false
              return
            end
          else
            valid_lines = true
          end
        end
        if system.get_time() - start_time > 0.5 / config.fps then
          coroutine.yield()
          start_time = system.get_time()
        end
      end
    end
    local views = #core.get_views_referencing_doc(self.doc)
    while self.first_invalid_line <= self.max_wanted_line do
      local max = math.min(self.first_invalid_line + 40, self.max_wanted_line)
      local retokenized_from
      for i = self.first_invalid_line, max do
        local state = (i > 1) and self.lines[i - 1].state
        local line = self.lines[i]
        if line and line.resume and (line.init_state ~= state or line.text ~= self.doc:get_utf8_line(i)) then
          -- Reset the progress if no longer valid
          line.resume = nil
        end
        if not (line and line.init_state == state and line.text == self.doc:get_utf8_line(i) and not line.resume) then
          retokenized_from = retokenized_from or i
          self.lines[i] = self:tokenize_line(i, state, line and line.resume)
          if self.lines[i].resume then
            self.first_invalid_line = i
            goto yield
          end
        elseif retokenized_from then
          self:update_notify(retokenized_from, i - retokenized_from - 1)
          retokenized_from = nil
        end
      end

      self.first_invalid_line = max + 1
      ::yield::
      if retokenized_from then
        self:update_notify(retokenized_from, max - retokenized_from)
      end
      core.redraw = true
      coroutine.yield()

      -- stop tokenizer if the doc was originally referenced by a docview
      -- but it was closed, helps when closing files that have huge lines
      -- and tokenization is taking a long time
      if views > 0 and #core.get_views_referencing_doc(self.doc) == 0 then
        break
      end
    end
    self.max_wanted_line = 0
    self.running = false
  end, self)
end

local function set_max_wanted_lines(self, amount)
  self.max_wanted_line = amount
  if self.first_invalid_line <= self.max_wanted_line then
    self:start()
  end
end


function Highlighter:reset()
  self.lines = {}
  self:soft_reset()
end

function Highlighter:soft_reset()
  for i=1,#self.lines do
    self.lines[i] = false
  end
  self.first_invalid_line = 1
  self.max_wanted_line = 0
end

function Highlighter:invalidate(idx)
  self.first_invalid_line = math.min(self.first_invalid_line, idx)
  set_max_wanted_lines(self, math.min(self.max_wanted_line, #self.doc.lines))
end

function Highlighter:insert_notify(line, n)
  local blanks = { }
  for i = 1, n do
    blanks[i] = false
  end
  common.splice(self.lines, line, 0, blanks)
  self.thread:insert_lines(line, n)
  self:invalidate(line)
end

function Highlighter:remove_notify(line, n)
  common.splice(self.lines, line, n)
  self.thread:remove_lines(line, n)
  self:invalidate(line)
end

function Highlighter:update_notify(line, n)
  -- plugins can hook here to be notified that lines have been retokenized
  self.doc:clear_cache(line, n)
end


function Highlighter:tokenize_line(idx, state, resume)
  local res = {}
  res.init_state = state
  res.text = self.doc:get_utf8_line(idx)
  res.tokens, res.state, res.resume = tokenizer.tokenize(self.doc.syntax, res.text, state, resume)
  return res
end


function Highlighter:get_line(idx)
  local line = self.lines[idx]
  if not line or line.text ~= self.doc:get_utf8_line(idx) then
    local prev = self.lines[idx - 1]
    line = self:tokenize_line(idx, prev and prev.state)
    self.lines[idx] = line
    self:update_notify(idx, 0)
  end
  set_max_wanted_lines(self, math.max(self.max_wanted_line, idx))
  return line
end


function Highlighter:each_token(idx, scol)
  return tokenizer.each_token(self:get_line(idx).tokens, scol)
end


return Highlighter
