local ok, plantuml = pcall(require, "plantuml")
if not ok then
  vim.notify("plantuml.nvim failed to load", vim.log.levels.ERROR)
  return
end

plantuml.start()

local augroup = vim.api.nvim_create_augroup("PlantUMLViewer", { clear = true })
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "BufEnter", "TabEnter", "FileType" }, {
  group = augroup,
  pattern = "*",
  callback = function()
    if vim.bo.filetype == "plantuml" then
      plantuml.update_diagram()
    end
  end,
  desc = "Update PlantUML diagram via WebSocket when plantuml filetype",
})

vim.api.nvim_create_user_command("PlantumlUpdate", function()
  plantuml.update_diagram()
end, { desc = "Manually trigger PlantUML update" })
