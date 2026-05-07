-- tests/minimal_init.lua
-- Minimal init for running tests with plenary.nvim

-- Add the plugin to runtimepath
vim.opt.runtimepath:prepend(vim.fn.getcwd())

-- Add plenary to runtimepath
local plenary_path = vim.fn.stdpath("data") .. "/site/pack/vendor/start/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.runtimepath:prepend(plenary_path)
end

-- Disable swap files for tests
vim.opt.swapfile = false
