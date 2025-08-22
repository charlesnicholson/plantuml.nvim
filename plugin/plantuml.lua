local ok, plantuml = pcall(require, "plantuml")
if not ok then
  vim.notify("plantuml.nvim failed to load", vim.log.levels.ERROR)
  return
end

plantuml.start()

local augroup = vim.api.nvim_create_augroup("PlantUMLViewer", { clear = true })

-- Pattern-based detection for efficiency
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "BufEnter", "TabEnter" }, {
  group = augroup,
  pattern = { "*.puml", "*.plantuml" },
  callback = plantuml.update_diagram,
  desc = "Update PlantUML diagram via WebSocket",
})

vim.api.nvim_create_user_command("PlantumlUpdate", function()
  plantuml.update_diagram()
end, { desc = "Manually trigger PlantUML update" })
