local ok, plantuml = pcall(require, "plantuml")
if not ok then
  vim.notify("plantuml.nvim failed to load", vim.log.levels.ERROR)
  return
end

plantuml.start()

local augroup = vim.api.nvim_create_augroup("PlantUMLViewer", { clear = true })

-- Update diagram for all critical events on plantuml files (supports any file extension with filetype=plantuml)
vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "BufEnter", "TabEnter" }, {
  group = augroup,
  callback = function()
    if vim.bo.filetype == "plantuml" then
      plantuml.update_diagram()
    end
  end,
  desc = "Update PlantUML diagram on file events for plantuml files",
})

vim.api.nvim_create_user_command("PlantumlUpdate", function()
  plantuml.update_diagram()
end, { desc = "Manually trigger PlantUML update" })

vim.api.nvim_create_user_command("PlantumlOpen", function()
  plantuml.open_browser()
end, { desc = "Open PlantUML web viewer in browser" })
