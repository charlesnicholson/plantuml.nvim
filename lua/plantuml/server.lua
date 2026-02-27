-- Minimal HTTP server using vim.uv TCP.
-- Serves two routes via callbacks: GET / and GET /health.
-- Zero dependency on other plantuml modules.

local M = {}

local tcp = nil

function M.start(port, callbacks)
  if tcp then
    return false, "HTTP server already running"
  end

  local t = vim.uv.new_tcp()
  local ok, err = pcall(function() t:bind("127.0.0.1", port) end)
  if not ok then
    t:close()
    return false, "Failed to bind HTTP server on port " .. port .. ": " .. tostring(err)
  end

  local ok2, err2 = pcall(function()
    t:listen(128, function(listen_err)
      if listen_err then return end
      local client = vim.uv.new_tcp()
      t:accept(client)
      local buf = ""
      client:read_start(function(read_err, data)
        if read_err or not data then
          if not client:is_closing() then client:close() end
          return
        end
        buf = buf .. data
        if not buf:find("\r\n\r\n") then return end
        local first_line = buf:match("^([^\r\n]+)")
        if first_line and first_line:find("/health", 1, true) then
          local body = callbacks.get_health()
          local resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
            .. "Content-Length: " .. #body .. "\r\n\r\n" .. body
          client:write(resp, function() if not client:is_closing() then client:close() end end)
        else
          local body = callbacks.get_html()
          local resp = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
            .. "Content-Length: " .. #body .. "\r\n\r\n" .. body
          client:write(resp, function() if not client:is_closing() then client:close() end end)
        end
      end)
    end)
  end)
  if not ok2 then
    t:close()
    return false, "Failed to listen on HTTP server: " .. tostring(err2)
  end

  tcp = t
  return true
end

function M.stop()
  if tcp then
    if not tcp:is_closing() then tcp:close() end
    tcp = nil
  end
end

function M.is_running()
  return tcp ~= nil
end

return M
