-- tests/e2e_spec.lua
-- End-to-end tests for BackwardForward.nvim
-- Tests multi-file navigation flows and persistence.

local bf = require("backward-forward")

-- Helper to create a named buffer with content
local function create_file_buf(name, lines)
  local buf = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = ""
  return buf
end

describe("e2e: multi-file navigation", function()
  before_each(function()
    vim.cmd("silent! %bwipeout!")
    bf._reset()
  end)

  it("navigates back through 3 files and forward again", function()
    local buf_a = create_file_buf("/tmp/e2e_a.lua", vim.fn["repeat"]({ "-- file a" }, 30))
    local buf_b = create_file_buf("/tmp/e2e_b.lua", vim.fn["repeat"]({ "-- file b" }, 30))
    local buf_c = create_file_buf("/tmp/e2e_c.lua", vim.fn["repeat"]({ "-- file c" }, 30))

    -- Simulate: open A at line 5, then B at line 10, then C at line 20
    vim.api.nvim_set_current_buf(buf_a)
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    bf._record(true)

    vim.api.nvim_set_current_buf(buf_b)
    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    bf._record(true)

    vim.api.nvim_set_current_buf(buf_c)
    vim.api.nvim_win_set_cursor(0, { 20, 0 })
    bf._record(true)

    -- Back: C -> B
    bf.go_back()
    assert.equals(buf_b, vim.api.nvim_get_current_buf())
    assert.equals(10, vim.api.nvim_win_get_cursor(0)[1])

    -- Back: B -> A
    bf.go_back()
    assert.equals(buf_a, vim.api.nvim_get_current_buf())
    assert.equals(5, vim.api.nvim_win_get_cursor(0)[1])

    -- Can't go back further
    assert.is_false(bf.can_go_back())

    -- Forward: A -> B
    bf.go_forward()
    assert.equals(buf_b, vim.api.nvim_get_current_buf())
    assert.equals(10, vim.api.nvim_win_get_cursor(0)[1])

    -- Forward: B -> C
    bf.go_forward()
    assert.equals(buf_c, vim.api.nvim_get_current_buf())
    assert.equals(20, vim.api.nvim_win_get_cursor(0)[1])

    -- Can't go forward further
    assert.is_false(bf.can_go_forward())
  end)

  it("handles mixed in-file jumps and buffer switches", function()
    local buf_a = create_file_buf("/tmp/e2e_mix_a.lua", vim.fn["repeat"]({ "code" }, 100))
    local buf_b = create_file_buf("/tmp/e2e_mix_b.lua", vim.fn["repeat"]({ "code" }, 100))

    -- A line 1
    vim.api.nvim_set_current_buf(buf_a)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    bf._record(true)

    -- A line 50 (large jump within same file)
    vim.api.nvim_win_set_cursor(0, { 50, 0 })
    bf._record(true)

    -- Switch to B line 20
    vim.api.nvim_set_current_buf(buf_b)
    vim.api.nvim_win_set_cursor(0, { 20, 0 })
    bf._record(true)

    -- B line 80 (large jump)
    vim.api.nvim_win_set_cursor(0, { 80, 0 })
    bf._record(true)

    -- Now go back through all 4 positions
    bf.go_back()
    assert.equals(buf_b, vim.api.nvim_get_current_buf())
    assert.equals(20, vim.api.nvim_win_get_cursor(0)[1])

    bf.go_back()
    assert.equals(buf_a, vim.api.nvim_get_current_buf())
    assert.equals(50, vim.api.nvim_win_get_cursor(0)[1])

    bf.go_back()
    assert.equals(buf_a, vim.api.nvim_get_current_buf())
    assert.equals(1, vim.api.nvim_win_get_cursor(0)[1])

    -- Forward all the way
    bf.go_forward()
    bf.go_forward()
    bf.go_forward()
    assert.equals(buf_b, vim.api.nvim_get_current_buf())
    assert.equals(80, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("new navigation after going back truncates forward history", function()
    local buf_a = create_file_buf("/tmp/e2e_trunc_a.lua", vim.fn["repeat"]({ "x" }, 50))
    local buf_b = create_file_buf("/tmp/e2e_trunc_b.lua", vim.fn["repeat"]({ "y" }, 50))
    local buf_c = create_file_buf("/tmp/e2e_trunc_c.lua", vim.fn["repeat"]({ "z" }, 50))

    vim.api.nvim_set_current_buf(buf_a)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    bf._record(true)

    vim.api.nvim_set_current_buf(buf_b)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    bf._record(true)

    vim.api.nvim_set_current_buf(buf_c)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    bf._record(true)

    -- Go back to B
    bf.go_back()
    assert.equals(buf_b, vim.api.nvim_get_current_buf())

    -- Now navigate to a new place (A line 30) — forward to C should be gone
    vim.api.nvim_set_current_buf(buf_a)
    vim.api.nvim_win_set_cursor(0, { 30, 0 })
    bf._record(true)

    assert.is_false(bf.can_go_forward())

    -- Back should go to B, then A(1)
    bf.go_back()
    assert.equals(buf_b, vim.api.nvim_get_current_buf())
    bf.go_back()
    assert.equals(buf_a, vim.api.nvim_get_current_buf())
    assert.equals(1, vim.api.nvim_win_get_cursor(0)[1])
  end)

  it("skips deleted buffers gracefully", function()
    local buf_a = create_file_buf("/tmp/e2e_del_a.lua", { "aa" })
    local buf_b = create_file_buf("/tmp/e2e_del_b.lua", { "bb" })
    local buf_c = create_file_buf("/tmp/e2e_del_c.lua", { "cc" })

    vim.api.nvim_set_current_buf(buf_a)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    bf._record(true)

    vim.api.nvim_set_current_buf(buf_b)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    bf._record(true)

    vim.api.nvim_set_current_buf(buf_c)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    bf._record(true)

    -- Delete buf_b
    vim.api.nvim_buf_delete(buf_b, { force = true })

    -- Going back should skip B and land on A
    bf.go_back()
    -- Might land on the file if it exists on disk, or skip it
    -- Since /tmp/e2e_del_b.lua doesn't exist on disk, it should skip
    local cur_buf = vim.api.nvim_get_current_buf()
    assert.not_equals(buf_b, cur_buf)
  end)

  it("handles rapid back-forward without corruption", function()
    local buf_a = create_file_buf("/tmp/e2e_rapid_a.lua", vim.fn["repeat"]({ "a" }, 50))
    local buf_b = create_file_buf("/tmp/e2e_rapid_b.lua", vim.fn["repeat"]({ "b" }, 50))

    vim.api.nvim_set_current_buf(buf_a)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    bf._record(true)

    vim.api.nvim_set_current_buf(buf_b)
    vim.api.nvim_win_set_cursor(0, { 25, 0 })
    bf._record(true)

    -- Rapid back-forward 10 times
    for _ = 1, 10 do
      bf.go_back()
      bf.go_forward()
    end

    -- Should still be at B:25
    assert.equals(buf_b, vim.api.nvim_get_current_buf())
    assert.equals(25, vim.api.nvim_win_get_cursor(0)[1])

    -- History should not have grown
    local state = bf._get_state()
    assert.equals(2, #state.history)
  end)
end)

describe("e2e: persistence", function()
  local persist_dir = vim.fn.stdpath("data") .. "/backward-forward"
  local test_persist_file

  before_each(function()
    vim.cmd("silent! %bwipeout!")
    bf._reset()
    -- Clean up any existing persist files for this cwd
    local cwd = vim.fn.getcwd()
    local hash = vim.fn.sha256(cwd):sub(1, 16)
    test_persist_file = persist_dir .. "/" .. hash .. ".json"
    vim.fn.delete(test_persist_file)
  end)

  after_each(function()
    if test_persist_file then
      vim.fn.delete(test_persist_file)
    end
  end)

  it("saves history to disk and restores it", function()
    -- Setup plugin with persist enabled
    bf.setup({ persist = true, persist_max = 50 })

    -- Create some history with real temp files
    local tmp_a = "/tmp/e2e_persist_a_" .. os.time() .. ".lua"
    local tmp_b = "/tmp/e2e_persist_b_" .. os.time() .. ".lua"

    -- Write actual files to disk so they can be restored
    local f = io.open(tmp_a, "w")
    f:write("-- file a\n" .. ("line\n"):rep(30))
    f:close()
    f = io.open(tmp_b, "w")
    f:write("-- file b\n" .. ("line\n"):rep(30))
    f:close()

    -- Open and record positions
    vim.cmd("edit " .. vim.fn.fnameescape(tmp_a))
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    bf._record(true)

    vim.cmd("edit " .. vim.fn.fnameescape(tmp_b))
    vim.api.nvim_win_set_cursor(0, { 15, 0 })
    bf._record(true)

    -- Verify history exists
    assert.is_true(bf.can_go_back())
    local state_before = bf._get_state()
    assert.equals(2, #state_before.history)

    -- Simulate VimLeavePre (trigger save)
    vim.api.nvim_exec_autocmds("VimLeavePre", {})

    -- Verify file was written
    local pf = io.open(test_persist_file, "r")
    assert.is_not_nil(pf, "Persist file should exist")
    local content = pf:read("*a")
    pf:close()
    assert.is_not_nil(content:find(tmp_a), "Should contain file a path")
    assert.is_not_nil(content:find(tmp_b), "Should contain file b path")

    -- Reset and reload
    bf._reset()
    assert.is_false(bf.can_go_back())

    -- Re-setup (which loads persisted history)
    bf.setup({ persist = true, persist_max = 50 })

    -- History should be restored
    local state_after = bf._get_state()
    assert.equals(2, #state_after.history)
    assert.is_true(bf.can_go_back())

    -- Navigate back should work with restored history
    bf.go_back()
    local cur_file = vim.fn.resolve(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))
    assert.equals(vim.fn.resolve(tmp_a), cur_file)
    assert.equals(5, vim.api.nvim_win_get_cursor(0)[1])

    -- Cleanup temp files
    os.remove(tmp_a)
    os.remove(tmp_b)
  end)

  it("handles missing files gracefully on restore", function()
    bf.setup({ persist = true, persist_max = 50 })

    -- Write a persist file referencing a non-existent file
    vim.fn.mkdir(persist_dir, "p")
    local data = vim.fn.json_encode({
      history = {
        { file = "/tmp/e2e_nonexistent_xyz.lua", lnum = 10, col = 0 },
        { file = "/tmp/e2e_nonexistent_abc.lua", lnum = 5, col = 0 },
      },
      pos = 2,
      cwd = vim.fn.getcwd(),
    })
    local pf = io.open(test_persist_file, "w")
    pf:write(data)
    pf:close()

    -- Reset and reload
    bf._reset()
    bf.setup({ persist = true })

    -- History loaded but navigating should skip invalid entries
    local state = bf._get_state()
    assert.equals(2, #state.history)

    -- Trying to go back should not error (entries will be skipped)
    assert.has_no.errors(function()
      bf.go_back()
    end)
  end)

  it("persists history scoped per cwd", function()
    bf.setup({ persist = true, persist_max = 50 })

    local tmp = "/tmp/e2e_persist_scoped_" .. os.time() .. ".lua"
    local f = io.open(tmp, "w")
    f:write("content\n")
    f:close()

    vim.cmd("edit " .. vim.fn.fnameescape(tmp))
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    bf._record(true)

    -- Save
    vim.api.nvim_exec_autocmds("VimLeavePre", {})

    -- The persist file should be named based on cwd hash
    local cwd = vim.fn.getcwd()
    local hash = vim.fn.sha256(cwd):sub(1, 16)
    local expected_path = persist_dir .. "/" .. hash .. ".json"
    local pf = io.open(expected_path, "r")
    assert.is_not_nil(pf, "Persist file should be at cwd-hashed path")
    pf:close()

    os.remove(tmp)
  end)

  it("respects persist_max limit", function()
    bf.setup({ persist = true, persist_max = 5, max_history = 100 })

    -- Create a real file with many lines
    local tmp = "/tmp/e2e_persist_limit_" .. os.time() .. ".lua"
    local f = io.open(tmp, "w")
    for i = 1, 200 do
      f:write("line " .. i .. "\n")
    end
    f:close()

    vim.cmd("edit " .. vim.fn.fnameescape(tmp))

    -- Record 20 positions
    for i = 1, 20 do
      vim.api.nvim_win_set_cursor(0, { i * 10, 0 })
      bf._record(true)
    end

    -- Save
    vim.api.nvim_exec_autocmds("VimLeavePre", {})

    -- Read the persist file and check entry count
    local pf = io.open(test_persist_file, "r")
    assert.is_not_nil(pf)
    local content = pf:read("*a")
    pf:close()

    local ok, data = pcall(vim.fn.json_decode, content)
    assert.is_true(ok)
    assert.is_true(#data.history <= 5, "Persisted entries should respect persist_max")

    os.remove(tmp)
  end)
end)
