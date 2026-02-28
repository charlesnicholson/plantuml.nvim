-- Cross-platform browser launch via vim.ui.open (Neovim 0.10+).

local M = {}

function M.open(url)
  vim.ui.open(url)
end

return M
