local ok, plantuml = pcall(require, "plantuml")
if not ok then
  vim.notify("plantuml.nvim failed to load", vim.log.levels.ERROR)
  return
end

local augroup = vim.api.nvim_create_augroup("PlantUMLViewer", { clear = true })

vim.api.nvim_create_autocmd({ "BufWritePost", "BufReadPost", "BufEnter", "TabEnter" }, {
  group = augroup,
  callback = function()
    if vim.bo.filetype == "plantuml" then
      local current_config = plantuml.get_config()
      if current_config.auto_update then
        plantuml.update_diagram()
      end
    end
  end,
  desc = "Update PlantUML diagram on file events for plantuml files",
})

vim.api.nvim_create_user_command("PlantumlUpdate", function()
  plantuml.update_diagram()
end, { desc = "Manually trigger PlantUML update" })

vim.api.nvim_create_user_command("PlantumlLaunchBrowser", function()
  plantuml.open_browser()
end, { desc = "Launch browser to view PlantUML diagrams" })

vim.api.nvim_create_user_command("PlantumlServerStart", function()
  plantuml.start()
end, { desc = "Start the PlantUML server" })

vim.api.nvim_create_user_command("PlantumlServerStop", function()
  plantuml.stop()
end, { desc = "Stop the PlantUML server" })
