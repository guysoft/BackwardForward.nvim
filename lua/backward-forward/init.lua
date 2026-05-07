-- backward-forward/init.lua
-- VS Code-style navigation history (back/forward) for Neovim.
--
-- Features:
--   - Custom position stack (records on buffer switch, large jumps, cursor idle)
--   - Mouse back/forward button support (X1Mouse/X2Mouse)
--   - Persistence across sessions (per-project, JSON file)
--   - Optional bufferline.nvim GUI buttons
--   - Quickui Jumps menu integration

local M = {}

-- Internal state
local history = {}       -- list of {file, lnum, col}
local history_pos = 0    -- current position in history (1-indexed, 0 = empty)
local max_history = 100  -- max entries
local navigating = false -- flag to prevent recording while navigating
local min_jump_lines = 10 -- minimum line delta to auto-record
local persist = true     -- save/restore history across sessions
local persist_max = 50   -- max entries to persist

--- Get the persistence file path (per-project based on cwd)
---@return string
local function get_persist_path()
  local data_dir = vim.fn.stdpath("data") .. "/backward-forward"
  -- Hash the cwd to create a unique filename per project
  local cwd = vim.fn.getcwd()
  local hash = vim.fn.sha256(cwd):sub(1, 16)
  return data_dir .. "/" .. hash .. ".json"
end

--- Save history to disk
local function save_history()
  if not persist then
    return
  end

  local data_dir = vim.fn.stdpath("data") .. "/backward-forward"
  vim.fn.mkdir(data_dir, "p")

  -- Convert to persistable format (file paths instead of bufnr)
  local entries = {}
  local count = 0
  -- Save the most recent entries up to persist_max
  local start = math.max(1, #history - persist_max + 1)
  for i = start, #history do
    local entry = history[i]
    local file = entry.file
    if not file and entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then
      file = vim.api.nvim_buf_get_name(entry.bufnr)
    end
    if file and file ~= "" then
      count = count + 1
      entries[count] = { file = file, lnum = entry.lnum, col = entry.col }
    end
  end

  -- Adjust pos relative to what we saved
  local adjusted_pos = history_pos - (start - 1)
  adjusted_pos = math.max(1, math.min(adjusted_pos, count))

  local data = vim.fn.json_encode({ history = entries, pos = adjusted_pos, cwd = vim.fn.getcwd() })
  local path = get_persist_path()
  local f = io.open(path, "w")
  if f then
    f:write(data)
    f:close()
  end
end

--- Load history from disk
local function load_history()
  if not persist then
    return
  end

  local path = get_persist_path()
  local f = io.open(path, "r")
  if not f then
    return
  end

  local content = f:read("*a")
  f:close()

  local ok, data = pcall(vim.fn.json_decode, content)
  if not ok or type(data) ~= "table" or not data.history then
    return
  end

  history = {}
  for _, entry in ipairs(data.history) do
    if entry.file and entry.lnum then
      table.insert(history, {
        file = entry.file,
        bufnr = nil, -- resolved lazily
        lnum = entry.lnum,
        col = entry.col or 0,
      })
    end
  end

  history_pos = data.pos or #history
  history_pos = math.max(0, math.min(history_pos, #history))
end

--- Resolve a history entry to a valid bufnr, opening the file if needed
---@param entry table
---@return boolean success
local function resolve_entry(entry)
  if entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then
    return true
  end

  if not entry.file or entry.file == "" then
    return false
  end

  -- Check if the file is already open in a buffer
  local bufnr = vim.fn.bufnr(entry.file)
  if bufnr ~= -1 then
    entry.bufnr = bufnr
    return true
  end

  -- Check if the file exists on disk
  if vim.fn.filereadable(entry.file) ~= 1 then
    return false
  end

  -- Open the file
  vim.cmd("edit " .. vim.fn.fnameescape(entry.file))
  entry.bufnr = vim.api.nvim_get_current_buf()
  return true
end

--- Record current position into history stack
---@param force boolean|nil Force recording even if position hasn't changed much
function M._record(force)
  if navigating then
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  -- Skip non-file buffers
  local buftype = vim.bo[bufnr].buftype
  if buftype ~= "" then
    return
  end

  local file = vim.api.nvim_buf_get_name(bufnr)
  if file == "" then
    return
  end

  local pos = vim.api.nvim_win_get_cursor(0)
  local lnum, col = pos[1], pos[2]

  -- Deduplicate: don't record if same file+line as current position
  if history_pos > 0 and history_pos <= #history then
    local last = history[history_pos]
    local last_file = last.file or (last.bufnr and vim.api.nvim_buf_is_valid(last.bufnr) and vim.api.nvim_buf_get_name(last.bufnr) or "")
    if last_file == file and last.lnum == lnum then
      last.col = col
      return
    end
    -- If not forced, check minimum jump distance (within same file)
    if not force and last_file == file then
      if math.abs(lnum - last.lnum) < min_jump_lines then
        return
      end
    end
  end

  -- Truncate forward history
  if history_pos < #history then
    for i = #history, history_pos + 1, -1 do
      table.remove(history, i)
    end
  end

  -- Add new entry
  table.insert(history, { bufnr = bufnr, file = file, lnum = lnum, col = col })

  -- Trim if over max
  if #history > max_history then
    table.remove(history, 1)
  end

  history_pos = #history
end

--- Check if we can navigate backward
---@return boolean
function M.can_go_back()
  return history_pos > 1
end

--- Check if we can navigate forward
---@return boolean
function M.can_go_forward()
  return history_pos < #history
end

--- Navigate backward in history
function M.go_back()
  if not M.can_go_back() then
    return
  end

  navigating = true
  history_pos = history_pos - 1
  local entry = history[history_pos]

  if resolve_entry(entry) then
    if vim.api.nvim_get_current_buf() ~= entry.bufnr then
      vim.api.nvim_set_current_buf(entry.bufnr)
    end
    local line_count = vim.api.nvim_buf_line_count(entry.bufnr)
    local lnum = math.min(entry.lnum, line_count)
    local line = vim.api.nvim_buf_get_lines(entry.bufnr, lnum - 1, lnum, false)[1] or ""
    local col = math.min(entry.col, math.max(0, #line - 1))
    vim.api.nvim_win_set_cursor(0, { lnum, col })
  else
    -- Entry invalid, remove and try again
    table.remove(history, history_pos)
    if history_pos > #history then
      history_pos = #history
    end
    navigating = false
    M.go_back()
    return
  end

  navigating = false
end

--- Navigate forward in history
function M.go_forward()
  if not M.can_go_forward() then
    return
  end

  navigating = true
  history_pos = history_pos + 1
  local entry = history[history_pos]

  if resolve_entry(entry) then
    if vim.api.nvim_get_current_buf() ~= entry.bufnr then
      vim.api.nvim_set_current_buf(entry.bufnr)
    end
    local line_count = vim.api.nvim_buf_line_count(entry.bufnr)
    local lnum = math.min(entry.lnum, line_count)
    local line = vim.api.nvim_buf_get_lines(entry.bufnr, lnum - 1, lnum, false)[1] or ""
    local col = math.min(entry.col, math.max(0, #line - 1))
    vim.api.nvim_win_set_cursor(0, { lnum, col })
  else
    table.remove(history, history_pos)
    if history_pos > #history then
      history_pos = #history
    end
    navigating = false
    M.go_forward()
    return
  end

  navigating = false
end

--- Setup autocmds to record position history
local function setup_recording()
  local augroup = vim.api.nvim_create_augroup("BackwardForwardRecording", { clear = true })

  -- Record on buffer switch (always significant)
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      vim.defer_fn(function()
        M._record(true)
      end, 10)
    end,
  })

  -- Record on large jumps
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    callback = function()
      M._record(false)
    end,
  })

  -- Record on idle
  vim.api.nvim_create_autocmd("CursorHold", {
    group = augroup,
    callback = function()
      M._record(true)
    end,
  })
end

--- Setup persistence (save on exit)
local function setup_persistence()
  if not persist then
    return
  end

  -- Load history on setup
  load_history()

  -- Save on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("BackwardForwardPersist", { clear = true }),
    callback = function()
      save_history()
    end,
  })
end

--- Setup mouse button mappings
---@param opts table
local function setup_mouse(opts)
  if not opts.mouse_buttons then
    return
  end

  local modes = { "n", "i", "v" }

  vim.keymap.set(modes, "<X1Mouse>", function()
    M.go_back()
  end, { desc = "Navigate Back (mouse)", silent = true, nowait = true })

  vim.keymap.set(modes, "<X2Mouse>", function()
    M.go_forward()
  end, { desc = "Navigate Forward (mouse)", silent = true, nowait = true })

  -- Suppress release events
  vim.keymap.set(modes, "<X1Release>", "<Nop>", { silent = true })
  vim.keymap.set(modes, "<X2Release>", "<Nop>", { silent = true })
end

--- Setup keyboard shortcuts
---@param opts table
local function setup_keys(opts)
  if not opts.keys then
    return
  end

  if opts.keys.back then
    vim.keymap.set("n", opts.keys.back, function()
      M.go_back()
    end, { desc = "Navigate Back", silent = true })
  end

  if opts.keys.forward then
    vim.keymap.set("n", opts.keys.forward, function()
      M.go_forward()
    end, { desc = "Navigate Forward", silent = true })
  end
end

--- Get bufferline custom_areas components (optional integration)
---@return table[]
function M.get_bufferline_components()
  local back_hl = M.can_go_back() and "BackwardForwardActive" or "BackwardForwardInactive"
  local fwd_hl = M.can_go_forward() and "BackwardForwardActive" or "BackwardForwardInactive"

  return {
    { text = " ◀ ", link = back_hl },
    { text = " ▶ ", link = fwd_hl },
  }
end

--- Get current history state (for debugging/testing)
---@return table
function M._get_state()
  return { history = history, pos = history_pos }
end

--- Reset history (for testing)
function M._reset()
  history = {}
  history_pos = 0
  navigating = false
end

--- Main setup function
---@param opts table|nil Configuration options
function M.setup(opts)
  opts = vim.tbl_deep_extend("force", {
    enabled = true,
    mouse_buttons = true,
    bufferline_buttons = false,
    persist = true,
    persist_max = 50,
    max_history = 100,
    min_jump_lines = 10,
    keys = {
      back = nil,
      forward = nil,
    },
  }, opts or {})

  if not opts.enabled then
    return
  end

  -- Apply config
  min_jump_lines = opts.min_jump_lines
  max_history = opts.max_history
  persist = opts.persist
  persist_max = opts.persist_max

  -- Setup highlight groups for bufferline integration
  vim.api.nvim_set_hl(0, "BackwardForwardActive", { fg = "#ffffff", bg = "#3c3c3c", bold = true })
  vim.api.nvim_set_hl(0, "BackwardForwardInactive", { fg = "#5c5c5c", bg = "#3c3c3c" })

  setup_persistence()
  setup_recording()
  setup_mouse(opts)
  setup_keys(opts)

  -- Register user commands
  vim.api.nvim_create_user_command("NavigateBack", function()
    M.go_back()
  end, { desc = "Navigate back in cursor history" })

  vim.api.nvim_create_user_command("NavigateForward", function()
    M.go_forward()
  end, { desc = "Navigate forward in cursor history" })
end

return M
