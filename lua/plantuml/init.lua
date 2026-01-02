local default_config = {
  auto_start = true,
  auto_update = true,
  http_port = 8764,
  plantuml_server_url = "http://www.plantuml.com/plantuml",
  auto_launch_browser = "never",
  use_docker = false,
  docker_image = "plantuml/plantuml-server:jetty",
  docker_port = 8080,
  docker_remove_on_stop = false,
}

local config = vim.deepcopy(default_config)

assert(pcall(require, "bit"), "[plantuml.nvim] Requires LuaJIT 'bit' library.")
local bit = require "bit"

local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, rol, tobit = bit.lshift, bit.rshift, bit.rol, bit.tobit

local LibDeflate = require("plantuml.vendor.LibDeflate.LibDeflate")
local docker = require("plantuml.docker")

local zlib = {}
function zlib.deflate(buf)
  local out = LibDeflate:CompressZlib(buf, { level = 9 })
  if not out then
    error("[plantuml.nvim] LibDeflate:CompressZlib failed.")
  end
  return out
end

local function encode64_plantuml(data)
  local map = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_'
  local out = {}
  local i, n = 1, #data
  while i <= n do
    local c1, c2, c3 = data:byte(i, i + 2)
    c1 = c1 or 0
    local b1 = rshift(c1, 2)
    if not c2 then
      local b2 = band(lshift(c1, 4), 0x3F)
      out[#out + 1] = map:sub(b1 + 1, b1 + 1)
      out[#out + 1] = map:sub(b2 + 1, b2 + 1)
      break
    else
      local b2 = band(bor(lshift(band(c1, 0x3), 4), rshift(c2, 4)), 0x3F)
      if not c3 then
        local b3 = band(lshift(band(c2, 0xF), 2), 0x3F)
        out[#out + 1] = map:sub(b1 + 1, b1 + 1)
        out[#out + 1] = map:sub(b2 + 1, b2 + 1)
        out[#out + 1] = map:sub(b3 + 1, b3 + 1)
        break
      else
        local b3 = band(bor(lshift(band(c2, 0xF), 2), rshift(c3, 6)), 0x3F)
        local b4 = band(c3, 0x3F)
        out[#out + 1] = map:sub(b1 + 1, b1 + 1)
        out[#out + 1] = map:sub(b2 + 1, b2 + 1)
        out[#out + 1] = map:sub(b3 + 1, b3 + 1)
        out[#out + 1] = map:sub(b4 + 1, b4 + 1)
        i = i + 3
      end
    end
  end
  return table.concat(out)
end

local sha1, b64
do
  local function to_be(n)
    return string.char(
      band(rshift(n, 24), 255),
      band(rshift(n, 16), 255),
      band(rshift(n, 8), 255),
      band(n, 255)
    )
  end

  function sha1(s)
    local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
    local len = #s
    s = s .. '\128' .. string.rep('\0', (55 - len) % 64) .. to_be(0) .. to_be(len * 8)
    for i = 1, #s, 64 do
      local chunk = s:sub(i, i + 63)
      local w = {}
      for j = 0, 15 do
        w[j] = bor(
          lshift(chunk:byte(j * 4 + 1), 24),
          lshift(chunk:byte(j * 4 + 2), 16),
          lshift(chunk:byte(j * 4 + 3), 8),
          chunk:byte(j * 4 + 4)
        )
      end
      for j = 16, 79 do w[j] = rol(bxor(w[j - 3], w[j - 8], w[j - 14], w[j - 16]), 1) end
      local a, b, c, d, e = h0, h1, h2, h3, h4
      for j = 0, 79 do
        local f, k
        if j < 20 then
          f, k = bor(band(b, c), band(bnot(b), d)), 0x5A827999
        elseif j < 40 then
          f, k = bxor(b, c, d), 0x6ED9EBA1
        elseif j < 60 then
          f, k = bor(band(b, c), band(b, d), band(c, d)), 0x8F1BBCDC
        else
          f, k = bxor(b, c, d), 0xCA62C1D6
        end
        local temp = tobit(rol(a, 5) + f + e + w[j] + k)
        e, d, c, b, a = d, c, rol(b, 30), a, temp
      end
      h0, h1, h2, h3, h4 = tobit(h0 + a), tobit(h1 + b), tobit(h2 + c), tobit(h3 + d), tobit(h4 + e)
    end
    return to_be(h0) .. to_be(h1) .. to_be(h2) .. to_be(h3) .. to_be(h4)
  end

  local map = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

  function b64(data)
    return ((data:gsub('.', function(x)
      local r, b = '', x:byte()
      for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
      return r
    end) .. '0000'):gsub('(%d%d%d?%d?%d?%d?)', function(x)
      if (#x < 6) then return '' end
      local c = 0
      for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
      return map:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
  end
end

local html_content = nil

local function load_html_content()
  local current_file = debug.getinfo(1).source:sub(2)
  local plugin_dir = vim.fn.fnamemodify(current_file, ":h")
  local html_file = vim.fs.joinpath(plugin_dir, "assets", "viewer.html")

  local file = io.open(html_file, "r")
  if not file then
    error("[plantuml.nvim] Could not open HTML file: " .. html_file)
  end

  html_content = file:read("*all")
  file:close()

  if not html_content or html_content == "" then
    error("[plantuml.nvim] HTML file is empty or could not be read: " .. html_file)
  end

  return html_content
end

local server = {}
local connected_clients = {}
local browser_launched_this_session = false
local browser_launch_pending = false
local last_message = nil
local http_server = nil
local ws_server = nil
local docker_container_name = "plantuml-nvim"

-- State machine: STOPPED -> STARTING -> DOCKER_PENDING -> READY
-- Also: STOPPING -> STOPPED
-- Also: DOCKER_UNAVAILABLE (Docker daemon not running, polling for it)
local STATE = {
  STOPPED = "stopped",
  STARTING = "starting",
  DOCKER_PENDING = "docker_pending",
  DOCKER_UNAVAILABLE = "docker_unavailable",
  READY = "ready",
  STOPPING = "stopping",
}
local current_state = STATE.STOPPED
local docker_poll_timer = nil

local function set_state(new_state)
  current_state = new_state
  -- Broadcast state change to all clients
  server.broadcast_status()
end

local function is_ready()
  return current_state == STATE.READY
end

local function stop_docker_polling()
  if docker_poll_timer then
    docker_poll_timer:stop()
    docker_poll_timer:close()
    docker_poll_timer = nil
  end
end

local function encode_ws_frame(payload)
  local len = #payload
  if len <= 125 then
    return string.char(0x81, len) .. payload
  elseif len <= 65535 then
    return string.char(0x81, 126, math.floor(len / 256), len % 256) .. payload
  else
    local b7 = len % 256
    local b6 = math.floor(len / 256) % 256
    local b5 = math.floor(len / 65536) % 256
    local b4 = math.floor(len / 16777216) % 256
    return string.char(0x81, 127, 0, 0, 0, 0, b4, b5, b6, b7) .. payload
  end
end

local function decode_ws_frame(data)
  if #data < 2 then return nil end
  local byte1, byte2 = data:byte(1, 2)
  local fin = band(byte1, 0x80) ~= 0
  local opcode = band(byte1, 0x0F)
  local masked = band(byte2, 0x80) ~= 0
  local payload_len = band(byte2, 0x7F)

  if not fin or opcode ~= 1 then return nil end

  local offset = 2
  if payload_len == 126 then
    if #data < 4 then return nil end
    payload_len = bor(lshift(data:byte(3), 8), data:byte(4))
    offset = 4
  elseif payload_len == 127 then
    if #data < 10 then return nil end
    offset = 10
  end

  if masked then
    if #data < offset + 4 then return nil end
    local mask = data:sub(offset + 1, offset + 4)
    offset = offset + 4
    if #data < offset + payload_len then return nil end
    local payload = data:sub(offset + 1, offset + payload_len)
    local decoded = {}
    for i = 1, #payload do
      decoded[i] = string.char(bxor(payload:byte(i), mask:byte((i - 1) % 4 + 1)))
    end
    return table.concat(decoded)
  else
    if #data < offset + payload_len then return nil end
    return data:sub(offset + 1, offset + payload_len)
  end
end

local function safe_client_write(client, frame)
  if client and not client:is_closing() then
    local ok, err = pcall(function() client:write(frame) end)
    if not ok then
      return false
    end
    return true
  end
  return false
end

local function collect_dead_clients()
  local dead = {}
  for client, _ in pairs(connected_clients) do
    if not client or client:is_closing() then
      dead[#dead + 1] = client
    end
  end
  return dead
end

local function remove_dead_clients()
  for _, client in ipairs(collect_dead_clients()) do
    connected_clients[client] = nil
  end
end

function server.broadcast(tbl)
  if tbl.type == "update" then
    last_message = tbl
  end
  local frame = encode_ws_frame(vim.json.encode(tbl))
  local dead = {}
  for client, _ in pairs(connected_clients) do
    if not safe_client_write(client, frame) then
      dead[#dead + 1] = client
    end
  end
  for _, client in ipairs(dead) do
    connected_clients[client] = nil
  end
end

function server.broadcast_status()
  local status_msg = {
    type = "status",
    state = current_state,
    has_diagram = last_message ~= nil,
  }
  -- Add helpful message for docker_unavailable state
  if current_state == STATE.DOCKER_UNAVAILABLE then
    status_msg.message = "Docker daemon is not running. Start Docker to enable local rendering."
  end
  local frame = encode_ws_frame(vim.json.encode(status_msg))
  local dead = {}
  for client, _ in pairs(connected_clients) do
    if not safe_client_write(client, frame) then
      dead[#dead + 1] = client
    end
  end
  for _, client in ipairs(dead) do
    connected_clients[client] = nil
  end
end

local function send_current_state(client)
  -- Always respond to refresh with current state
  local response
  if last_message then
    response = last_message
  else
    response = {
      type = "status",
      state = current_state,
      has_diagram = false,
    }
  end
  local frame = encode_ws_frame(vim.json.encode(response))
  safe_client_write(client, frame)
end

local function has_connected_clients()
  remove_dead_clients()
  return next(connected_clients) ~= nil
end

local function handle_health_request(client)
  local health = {
    state = current_state,
    has_diagram = last_message ~= nil,
    connected_clients = 0,
  }
  for _ in pairs(connected_clients) do
    health.connected_clients = health.connected_clients + 1
  end
  local json = vim.json.encode(health)
  local response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " ..
      #json .. "\r\n\r\n" .. json
  client:write(response, function() client:close() end)
end

function server.start()
  if current_state ~= STATE.STOPPED then return false, "Server already running" end
  set_state(STATE.STARTING)

  http_server = vim.loop.new_tcp()
  local ok, err = pcall(function()
    http_server:bind("127.0.0.1", config.http_port)
  end)
  if not ok then
    set_state(STATE.STOPPED)
    return false, "Failed to bind HTTP server: " .. tostring(err)
  end

  local ok2, err2 = pcall(function()
    http_server:listen(128, function(listen_err)
      if listen_err then return end
      local client = vim.loop.new_tcp()
      http_server:accept(client)
      local http_buffer = ""
      client:read_start(function(_, data)
        if data then
          http_buffer = http_buffer .. data
          -- Check if we have complete HTTP request
          if http_buffer:find("\r\n\r\n") then
            -- Check for health endpoint - simple string search in first line
            local first_line = http_buffer:match("^([^\r\n]+)")
            local is_health = first_line and first_line:find("/health", 1, true)
            if is_health then
              handle_health_request(client)
            else
              local content = load_html_content()
              local response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: " ..
                  #content .. "\r\n\r\n" .. content
              client:write(response, function() client:close() end)
            end
          end
        end
      end)
    end)
  end)
  if not ok2 then
    set_state(STATE.STOPPED)
    return false, "Failed to start HTTP server: " .. tostring(err2)
  end

  ws_server = vim.loop.new_tcp()
  local ok3, err3 = pcall(function()
    ws_server:bind("127.0.0.1", config.http_port + 1)
  end)
  if not ok3 then
    http_server:close()
    set_state(STATE.STOPPED)
    return false, "Failed to bind WebSocket server: " .. tostring(err3)
  end

  local ok4, err4 = pcall(function()
    ws_server:listen(128, function(listen_err)
      if listen_err then return end
      local client = vim.loop.new_tcp()
      ws_server:accept(client)
      local handshake_done = false
      local handshake_buffer = ""
      client:read_start(function(read_err, data)
        if read_err or not data then
          connected_clients[client] = nil
          pcall(function() client:close() end)
          return
        end
        vim.schedule(function()
          if not handshake_done then
            -- Buffer handshake data until we have complete headers
            handshake_buffer = handshake_buffer .. data
            if not handshake_buffer:find("\r\n\r\n") then
              return -- Wait for more data
            end
            local key = handshake_buffer:match("Sec%-WebSocket%-Key: ([%w%+/=]+)")
            if key then
              local guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
              local accept_key_b64 = b64(sha1(key .. guid))
              local response =
                  "HTTP/1.1 101 Switching Protocols\r\n" ..
                  "Upgrade: websocket\r\n" ..
                  "Connection: Upgrade\r\n" ..
                  "Sec-WebSocket-Accept: " .. accept_key_b64 .. "\r\n\r\n"
              client:write(response)
              connected_clients[client] = true
              browser_launch_pending = false -- Client connected, clear the lock
              handshake_done = true
              handshake_buffer = nil -- Free memory
            end
          else
            local payload = decode_ws_frame(data)
            if payload then
              local ok, message = pcall(vim.json.decode, payload)
              if ok and message and message.type == "refresh" then
                send_current_state(client)
              end
            end
          end
        end)
      end)
    end)
  end)
  if not ok4 then
    http_server:close()
    ws_server:close()
    set_state(STATE.STOPPED)
    return false, "Failed to start WebSocket server: " .. tostring(err4)
  end

  return true
end

local function start_docker_server(callback)
  if not config.use_docker then
    if callback then callback(true, nil) else return true, nil end
  end

  server.broadcast({
    type = "docker_status",
    operation = "docker_check",
    status = "Checking Docker availability..."
  })

  if callback then
    docker.is_docker_available(function(available, err)
      if not available then
        server.broadcast({
          type = "docker_status",
          operation = "docker_check",
          status = "Docker not available",
          error = true
        })
        callback(false, "[plantuml.nvim] Docker is not available: " .. (err or "unknown error"))
        return
      end

      docker.is_docker_running(function(running, err)
        if not running then
          server.broadcast({
            type = "docker_status",
            operation = "docker_check",
            status = "Docker daemon not running",
            error = true
          })
          callback(false, "[plantuml.nvim] Docker daemon is not running: " .. (err or "unknown error"))
          return
        end

        docker.get_container_status(docker_container_name, function(status, _)
          if status == "running" then
            vim.notify("[plantuml.nvim] Using existing PlantUML Docker container", vim.log.levels.INFO)
            server.broadcast({
              type = "docker_status",
              operation = "container_reuse",
              status = "Using existing Docker container",
              completed = true
            })
            callback(true, nil)
            return
          elseif status == "stopped" then
            vim.notify("[plantuml.nvim] Restarting PlantUML Docker container...", vim.log.levels.INFO)
            server.broadcast({
              type = "docker_status",
              operation = "container_start",
              status = "Restarting Docker container..."
            })
          else
            vim.notify("[plantuml.nvim] Starting PlantUML Docker container...", vim.log.levels.INFO)
            server.broadcast({
              type = "docker_status",
              operation = "container_start",
              status = "Starting Docker container..."
            })
          end

          docker.start_container(
            docker_container_name,
            config.docker_image,
            config.docker_port,
            8080,
            function(success, err)
              if not success then
                server.broadcast({
                  type = "docker_status",
                  operation = "container_start",
                  status = "Failed to start container",
                  error = true
                })
                callback(false, "[plantuml.nvim] Failed to start Docker container: " .. (err or "unknown error"))
                return
              end

              if status ~= "running" then
                server.broadcast({
                  type = "docker_status",
                  operation = "container_ready",
                  status = "Waiting for container to be ready..."
                })

                docker.wait_for_container_ready(docker_container_name, 30, function(ready, err)
                  if not ready then
                    server.broadcast({
                      type = "docker_status",
                      operation = "container_ready",
                      status = "Container failed to be ready",
                      error = true
                    })
                    callback(false, "[plantuml.nvim] Docker container failed to be ready: " .. (err or "timeout"))
                    return
                  end

                  vim.notify("[plantuml.nvim] PlantUML Docker container is ready", vim.log.levels.INFO)
                  server.broadcast({
                    type = "docker_status",
                    operation = "container_ready",
                    status = "Docker container ready",
                    completed = true
                  })

                  callback(true, nil)
                end)
              else
                vim.notify("[plantuml.nvim] PlantUML Docker container is ready", vim.log.levels.INFO)
                server.broadcast({
                  type = "docker_status",
                  operation = "container_ready",
                  status = "Docker container ready",
                  completed = true
                })

                callback(true, nil)
              end
            end
          )
        end)
      end)
    end)
  else
    local available, err = docker.is_docker_available()
    if not available then
      server.broadcast({
        type = "docker_status",
        operation = "docker_check",
        status = "Docker not available",
        error = true
      })
      return false, "[plantuml.nvim] Docker is not available: " .. (err or "unknown error")
    end

    local running, err = docker.is_docker_running()
    if not running then
      server.broadcast({
        type = "docker_status",
        operation = "docker_check",
        status = "Docker daemon not running",
        error = true
      })
      return false, "[plantuml.nvim] Docker daemon is not running: " .. (err or "unknown error")
    end

    local status, _ = docker.get_container_status(docker_container_name)

    if status == "running" then
      vim.notify("[plantuml.nvim] Using existing PlantUML Docker container", vim.log.levels.INFO)
      server.broadcast({
        type = "docker_status",
        operation = "container_reuse",
        status = "Using existing Docker container",
        completed = true
      })
    elseif status == "stopped" then
      vim.notify("[plantuml.nvim] Restarting PlantUML Docker container...", vim.log.levels.INFO)
      server.broadcast({
        type = "docker_status",
        operation = "container_start",
        status = "Restarting Docker container..."
      })
    else
      vim.notify("[plantuml.nvim] Starting PlantUML Docker container...", vim.log.levels.INFO)
      server.broadcast({
        type = "docker_status",
        operation = "container_start",
        status = "Starting Docker container..."
      })
    end

    local success, err = docker.start_container(
      docker_container_name,
      config.docker_image,
      config.docker_port,
      8080
    )

    if not success then
      server.broadcast({
        type = "docker_status",
        operation = "container_start",
        status = "Failed to start container",
        error = true
      })
      return false, "[plantuml.nvim] Failed to start Docker container: " .. (err or "unknown error")
    end

    if status ~= "running" then
      server.broadcast({
        type = "docker_status",
        operation = "container_ready",
        status = "Waiting for container to be ready..."
      })

      local ready, err = docker.wait_for_container_ready(docker_container_name, 30)
      if not ready then
        server.broadcast({
          type = "docker_status",
          operation = "container_ready",
          status = "Container failed to be ready",
          error = true
        })
        return false, "[plantuml.nvim] Docker container failed to be ready: " .. (err or "timeout")
      end
    end

    vim.notify("[plantuml.nvim] PlantUML Docker container is ready", vim.log.levels.INFO)
    server.broadcast({
      type = "docker_status",
      operation = "container_ready",
      status = "Docker container ready",
      completed = true
    })

    return true, nil
  end
end

local function stop_docker_server()
  if not config.use_docker then
    return true, nil
  end

  server.broadcast({
    type = "docker_status",
    operation = "container_stop",
    status = "Stopping Docker container..."
  })

  local success, err = docker.stop_container(docker_container_name)
  if not success then
    vim.notify("[plantuml.nvim] Warning: Failed to stop Docker container: " .. (err or "unknown error"),
      vim.log.levels.WARN)
    server.broadcast({
      type = "docker_status",
      operation = "container_stop",
      status = "Failed to stop container",
      error = true
    })
  else
    server.broadcast({
      type = "docker_status",
      operation = "container_stop",
      status = "Container stopped"
    })
  end

  if config.docker_remove_on_stop then
    server.broadcast({
      type = "docker_status",
      operation = "container_remove",
      status = "Removing Docker container..."
    })

    local success, err = docker.remove_container(docker_container_name)
    if not success then
      vim.notify("[plantuml.nvim] Warning: Failed to remove Docker container: " .. (err or "unknown error"),
        vim.log.levels.WARN)
      server.broadcast({
        type = "docker_status",
        operation = "container_remove",
        status = "Failed to remove container",
        error = true
      })
    else
      server.broadcast({
        type = "docker_status",
        operation = "container_remove",
        status = "Container removed"
      })
    end
  end

  return true, nil
end

local function get_plantuml_server_url()
  if config.use_docker then
    return "http://localhost:" .. config.docker_port
  else
    return config.plantuml_server_url
  end
end

local M = {}

function M.update_diagram()
  -- Only broadcast updates when ready (or if not using Docker)
  if current_state ~= STATE.READY and current_state ~= STATE.STARTING then
    return
  end

  local buf = 0
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local buffer_content = table.concat(lines, '\n')
  if buffer_content:match("^%s*$") then
    return
  end
  local filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ":p")
  if filename == "" then filename = "untitled.puml" end

  local compressed_data = zlib.deflate(buffer_content)
  local encoded_data = encode64_plantuml(compressed_data)
  local server_url = get_plantuml_server_url()
  local plantuml_url = server_url .. "/png/~1" .. encoded_data

  if #plantuml_url > 8000 then
    vim.notify("PlantUML: Resulting URL is very long and may be rejected by the server.", vim.log.levels.WARN)
  end

  local timestamp = os.date("%Y-%m-%d %H:%M:%S")

  server.broadcast({
    type = "update",
    url = plantuml_url,
    filename = filename,
    timestamp = timestamp,
    server_url = server_url
  })

  M.maybe_launch_browser()
end

-- Helper to check and launch browser with lock to prevent duplicates
function M.maybe_launch_browser()
  if has_connected_clients() or current_state == STATE.STOPPED then
    return
  end
  if browser_launch_pending then
    return -- Browser launch in progress, waiting for connection
  end

  local should_launch = false
  if config.auto_launch_browser == "always" then
    should_launch = true
  elseif config.auto_launch_browser == "once" and not browser_launched_this_session then
    should_launch = true
  end

  if should_launch then
    browser_launch_pending = true
    M.open_browser()
    browser_launched_this_session = true
  end
end

-- Try to start Docker, called from polling or initial startup
local function try_start_docker()
  if current_state == STATE.STOPPED or current_state == STATE.STOPPING then
    stop_docker_polling()
    return
  end

  -- Check if Docker daemon is running
  docker.is_docker_running(function(running, _)
    if not running then
      -- Docker still not running, keep polling (state already DOCKER_UNAVAILABLE)
      return
    end

    -- Docker is now running! Stop polling and start the container
    stop_docker_polling()
    set_state(STATE.DOCKER_PENDING)

    -- Now try to start the container
    start_docker_server(function(success, _)
      if success then
        set_state(STATE.READY)
      else
        -- Container failed but Docker is running - still go to READY
        -- (user can use remote server)
        set_state(STATE.READY)
      end
      -- Docker just became ready - check if we should open a browser
      M.maybe_launch_browser()
    end)
  end)
end

-- Start polling for Docker daemon at 1Hz
local function start_docker_polling()
  stop_docker_polling() -- Clean up any existing timer

  docker_poll_timer = vim.loop.new_timer()
  docker_poll_timer:start(1000, 1000, vim.schedule_wrap(function()
    if current_state == STATE.DOCKER_UNAVAILABLE then
      try_start_docker()
    else
      stop_docker_polling()
    end
  end))
end

function M.start()
  local ok, err = server.start()
  if not ok then
    vim.notify("[plantuml.nvim] " .. (err or "Failed to start server"), vim.log.levels.ERROR)
    return false
  end

  if config.use_docker then
    -- First check if Docker daemon is even running (synchronously for quick feedback)
    docker.is_docker_running(function(running, _)
      if not running then
        -- Docker daemon not running - go to DOCKER_UNAVAILABLE state and poll
        set_state(STATE.DOCKER_UNAVAILABLE)
        start_docker_polling()
        return
      end

      -- Docker is running, proceed with normal startup
      set_state(STATE.DOCKER_PENDING)
      start_docker_server(function(success, _)
        if success then
          set_state(STATE.READY)
        else
          -- Container start failed but daemon is running
          -- Go to READY so plugin is usable with remote server
          set_state(STATE.READY)
        end
      end)
    end)
  else
    set_state(STATE.READY)
  end

  return true
end

function M.is_running()
  return current_state ~= STATE.STOPPED
end

function M.get_state()
  return current_state
end

function M.open_browser()
  if current_state == STATE.STOPPED then
    vim.notify("[plantuml.nvim] Server is not running.", vim.log.levels.WARN)
    return
  end

  local url = "http://127.0.0.1:" .. config.http_port
  vim.ui.open(url)
end

function M.stop()
  if current_state == STATE.STOPPED then
    vim.notify("[plantuml.nvim] Server is not running.", vim.log.levels.WARN)
    return
  end
  set_state(STATE.STOPPING)

  -- Stop Docker polling if active
  stop_docker_polling()

  -- Collect clients to close (don't modify during iteration)
  local clients_to_close = {}
  for client, _ in pairs(connected_clients) do
    clients_to_close[#clients_to_close + 1] = client
  end
  for _, client in ipairs(clients_to_close) do
    if client and not client:is_closing() then
      pcall(function() client:close() end)
    end
  end
  connected_clients = {}

  if http_server and not http_server:is_closing() then
    pcall(function() http_server:close() end)
  end
  if ws_server and not ws_server:is_closing() then
    pcall(function() ws_server:close() end)
  end

  if config.use_docker then
    stop_docker_server()
  end

  set_state(STATE.STOPPED)
  last_message = nil
  vim.notify("[plantuml.nvim] Server stopped.", vim.log.levels.INFO)
end

function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", default_config, user_config)
  end

  if config.use_docker then
    if config.plantuml_server_url ~= default_config.plantuml_server_url then
      vim.notify("[plantuml.nvim] Warning: plantuml_server_url is ignored when use_docker is enabled",
        vim.log.levels.WARN)
    end
  end

  if config.auto_start then
    M.start()
  end
end

function M.get_config()
  return vim.deepcopy(config)
end

return M
