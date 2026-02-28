-- plantuml.nvim orchestrator.
-- Owns all mutable state. Coordinates server, websocket, encoder, docker, browser modules.
-- Public API: setup(), get_config(), start(), stop(), update_diagram(), open_browser().

local server = require("plantuml.server")
local ws = require("plantuml.websocket")
local encoder = require("plantuml.encoder")
local docker = require("plantuml.docker")
local browser = require("plantuml.browser")

-- Default configuration
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

-- State machine
local STATE = {
  STOPPED = "stopped",
  STARTING = "starting",
  DOCKER_PENDING = "docker_pending",
  DOCKER_UNAVAILABLE = "docker_unavailable",
  READY = "ready",
  STOPPING = "stopping",
}
local current_state = STATE.STOPPED

-- File-to-client mapping
local file_clients = {} -- filepath → { client_id = true, ... }
local client_files = {} -- client_id → filepath

-- Pending state
local pending_file = nil -- set by open_browser(), consumed by on_connect
local last_messages = {} -- filepath → last update message table
local pending_updates = {} -- filepath → true (updates waiting for READY)

-- Browser launch state
local browser_launched_this_session = false
local browser_launch_pending = false

-- Docker polling
local docker_poll_timer = nil

-- HTML content cache
local html_content = nil

local DOCKER_CONTAINER_NAME = "plantuml-nvim"

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function load_html()
  if html_content then return html_content end
  local src = debug.getinfo(1).source:sub(2)
  local dir = vim.fn.fnamemodify(src, ":h")
  local path = vim.fs.joinpath(dir, "assets", "viewer.html")
  local f = io.open(path, "r")
  if not f then error("[plantuml.nvim] Could not open: " .. path) end
  html_content = f:read("*all")
  f:close()
  if not html_content or html_content == "" then
    error("[plantuml.nvim] Empty HTML file: " .. path)
  end
  return html_content
end

local function server_url()
  if config.use_docker then
    return "http://localhost:" .. config.docker_port
  end
  return config.plantuml_server_url
end

-- Find the best update to replay for a client.
-- Try the mapped filepath first; fall back to any available message.
local function find_replay_message(fp)
  if fp and last_messages[fp] then
    return last_messages[fp]
  end
  local _, msg = next(last_messages)
  return msg
end

local function clients_for_file(filepath)
  local ids = {}
  local map = file_clients[filepath]
  if map then
    for id in pairs(map) do
      if ws.is_connected(id) then
        ids[#ids + 1] = id
      end
    end
  end
  return ids
end

local function any_clients_for_file(filepath)
  return #clients_for_file(filepath) > 0
end

local function has_any_clients()
  return ws.client_count() > 0
end

local function map_client(client_id, filepath)
  if not file_clients[filepath] then file_clients[filepath] = {} end
  file_clients[filepath][client_id] = true
  client_files[client_id] = filepath
end

local function unmap_client(client_id)
  local fp = client_files[client_id]
  if fp and file_clients[fp] then
    file_clients[fp][client_id] = nil
    if not next(file_clients[fp]) then file_clients[fp] = nil end
  end
  client_files[client_id] = nil
end

-- ---------------------------------------------------------------------------
-- State management
-- ---------------------------------------------------------------------------

local M = {}

local function broadcast_status()
  local msg = {
    type = "status",
    state = current_state,
    has_diagram = next(last_messages) ~= nil,
  }
  if current_state == STATE.DOCKER_UNAVAILABLE then
    msg.message = "Docker daemon is not running. Start Docker to enable local rendering."
  end
  ws.broadcast(msg)
end

local function set_state(new_state)
  current_state = new_state
  broadcast_status()
end

-- When state becomes READY, replay pending updates.
local function on_state_ready()
  for filepath in pairs(pending_updates) do
    local msg = last_messages[filepath]
    if msg then
      local ids = clients_for_file(filepath)
      if #ids > 0 then
        ws.send_to(ids, msg)
      else
        -- Broadcast fallback for single-browser workflow
        ws.broadcast(msg)
      end
    end
  end
  pending_updates = {}
end

-- ---------------------------------------------------------------------------
-- Docker polling
-- ---------------------------------------------------------------------------

local function stop_docker_polling()
  if docker_poll_timer then
    docker_poll_timer:stop()
    docker_poll_timer:close()
    docker_poll_timer = nil
  end
end

local function start_docker_container(cb)
  ws.broadcast({ type = "docker_status", status = "Checking Docker availability..." })

  docker.is_docker_running(function(running)
    if not running then
      cb(false, "Docker daemon not running")
      return
    end

    ws.broadcast({ type = "docker_status", status = "Starting Docker container..." })

    docker.start_container(
      DOCKER_CONTAINER_NAME, config.docker_image, config.docker_port, 8080,
      function(ok)
        if not ok then
          ws.broadcast({ type = "docker_status", status = "Failed to start container", error = true })
          cb(false, "Failed to start Docker container")
          return
        end

        ws.broadcast({ type = "docker_status", status = "Waiting for container to be ready..." })
        docker.wait_for_ready(DOCKER_CONTAINER_NAME, 30, function(ready, err)
          if not ready then
            ws.broadcast({ type = "docker_status", status = "Container failed to be ready", error = true })
            cb(false, "Docker container not ready: " .. (err or "timeout"))
            return
          end
          vim.notify("[plantuml.nvim] PlantUML Docker container is ready", vim.log.levels.INFO)
          ws.broadcast({ type = "docker_status", status = "Docker container ready", completed = true })
          cb(true)
        end)
      end)
  end)
end

local function try_start_docker()
  if current_state == STATE.STOPPED or current_state == STATE.STOPPING then
    stop_docker_polling()
    return
  end

  docker.is_docker_running(function(running)
    if not running then return end -- keep polling

    stop_docker_polling()
    set_state(STATE.DOCKER_PENDING)

    start_docker_container(function(ok)
      set_state(STATE.READY)
      on_state_ready()
      if ok then
        M.maybe_launch_browser()
      end
    end)
  end)
end

local function start_docker_polling()
  stop_docker_polling()
  docker_poll_timer = vim.uv.new_timer()
  docker_poll_timer:start(1000, 1000, vim.schedule_wrap(function()
    if current_state == STATE.DOCKER_UNAVAILABLE then
      try_start_docker()
    else
      stop_docker_polling()
    end
  end))
end

-- ---------------------------------------------------------------------------
-- WebSocket callbacks
-- ---------------------------------------------------------------------------

local function current_filepath()
  local name = vim.api.nvim_buf_get_name(0)
  local fp = vim.fn.fnamemodify(name, ":p")
  if fp == "" then fp = "untitled.puml" end
  return fp
end

local function on_ws_connect(client_id)
  browser_launch_pending = false

  -- Determine which file this client belongs to
  local fp = pending_file or current_filepath()
  pending_file = nil
  map_client(client_id, fp)

  -- Send current status
  local status_msg = {
    type = "status",
    state = current_state,
    has_diagram = next(last_messages) ~= nil,
  }
  if current_state == STATE.DOCKER_UNAVAILABLE then
    status_msg.message = "Docker daemon is not running. Start Docker to enable local rendering."
  end
  ws.send(client_id, status_msg)

  -- Replay last message if READY
  if current_state == STATE.READY then
    local msg = find_replay_message(fp)
    if msg then
      ws.send(client_id, msg)
    end
  end
end

local function on_ws_message(client_id, raw)
  local ok, msg = pcall(vim.json.decode, raw)
  if not ok or not msg then return end

  if msg.type == "refresh" then
    local fp = client_files[client_id]
    local status_msg = {
      type = "status",
      state = current_state,
      has_diagram = next(last_messages) ~= nil,
    }
    ws.send(client_id, status_msg)
    if current_state == STATE.READY then
      local replay = find_replay_message(fp)
      if replay then
        ws.send(client_id, replay)
      end
    end
  end
end

local function on_ws_disconnect(client_id)
  unmap_client(client_id)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", default_config, user_config)
  end

  if config.use_docker and config.plantuml_server_url ~= default_config.plantuml_server_url then
    vim.notify("[plantuml.nvim] Warning: plantuml_server_url is ignored when use_docker is enabled",
      vim.log.levels.WARN)
  end

  -- Register VimLeavePre cleanup
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("PlantUMLCleanup", { clear = true }),
    callback = function()
      if current_state ~= STATE.STOPPED then
        M.stop()
      end
    end,
  })
end

function M.get_config()
  return vim.deepcopy(config)
end

function M.start()
  if current_state ~= STATE.STOPPED then
    return false, "Server already running"
  end
  set_state(STATE.STARTING)

  -- Start HTTP server
  local ok, err = server.start(config.http_port, {
    get_html = load_html,
    get_health = function()
      return vim.json.encode({
        state = current_state,
        has_diagram = next(last_messages) ~= nil,
        connected_clients = ws.client_count(),
      })
    end,
  })
  if not ok then
    set_state(STATE.STOPPED)
    vim.notify("[plantuml.nvim] " .. (err or "Failed to start HTTP server"), vim.log.levels.ERROR)
    return false, err
  end

  -- Start WebSocket server
  local ok2, err2 = ws.start(config.http_port + 1, {
    on_connect = on_ws_connect,
    on_message = on_ws_message,
    on_disconnect = on_ws_disconnect,
  })
  if not ok2 then
    server.stop()
    set_state(STATE.STOPPED)
    vim.notify("[plantuml.nvim] " .. (err2 or "Failed to start WS server"), vim.log.levels.ERROR)
    return false, err2
  end

  -- Docker or direct
  if config.use_docker then
    docker.is_docker_running(function(running)
      if not running then
        set_state(STATE.DOCKER_UNAVAILABLE)
        start_docker_polling()
        return
      end
      set_state(STATE.DOCKER_PENDING)
      start_docker_container(function(ok)
        set_state(STATE.READY)
        on_state_ready()
        if ok then
          M.maybe_launch_browser()
        end
      end)
    end)
  else
    set_state(STATE.READY)
  end

  return true
end

function M.stop()
  if current_state == STATE.STOPPED then
    return
  end
  set_state(STATE.STOPPING)

  stop_docker_polling()
  ws.stop()
  server.stop()

  if config.use_docker then
    docker.stop_container(DOCKER_CONTAINER_NAME, function()
      if config.docker_remove_on_stop then
        docker.remove_container(DOCKER_CONTAINER_NAME, function() end)
      end
    end)
  end

  -- Reset state
  file_clients = {}
  client_files = {}
  pending_file = nil
  last_messages = {}
  pending_updates = {}
  html_content = nil

  set_state(STATE.STOPPED)
  vim.notify("[plantuml.nvim] Server stopped.", vim.log.levels.INFO)
end

function M.update_diagram()
  -- Lazy start: if auto_start and stopped, start now
  if config.auto_start and current_state == STATE.STOPPED then
    M.start()
  end

  -- Don't try to encode if fully stopped
  if current_state == STATE.STOPPED or current_state == STATE.STOPPING then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local text = table.concat(lines, "\n")
  if text:match("^%s*$") then return end

  local filepath = current_filepath()
  local url = encoder.encode(text, server_url())

  if #url > 8000 then
    vim.notify("PlantUML: Resulting URL is very long and may be rejected by the server.", vim.log.levels.WARN)
  end

  local msg = {
    type = "update",
    url = url,
    filename = filepath,
    timestamp = os.date("%Y-%m-%d %H:%M:%S"),
    server_url = server_url(),
  }

  -- Always store
  last_messages[filepath] = msg

  if current_state == STATE.READY then
    -- Send to clients mapped to this file
    local ids = clients_for_file(filepath)
    if #ids > 0 then
      ws.send_to(ids, msg)
    else
      -- Broadcast fallback: single-browser workflow
      ws.broadcast(msg)
    end
  else
    -- Mark for replay when READY
    pending_updates[filepath] = true
  end

  M.maybe_launch_browser()
end

function M.maybe_launch_browser()
  if current_state == STATE.STOPPED then return end
  if browser_launch_pending then return end

  -- Check if current file already has clients
  local fp = current_filepath()
  if any_clients_for_file(fp) then return end
  -- If any clients at all are connected, don't auto-launch
  if has_any_clients() then return end

  local should_launch = false
  if config.auto_launch_browser == "always" then
    should_launch = true
  elseif config.auto_launch_browser == "once" and not browser_launched_this_session then
    should_launch = true
  end

  if should_launch then
    browser_launch_pending = true
    pending_file = fp
    browser.open("http://127.0.0.1:" .. config.http_port)
    browser_launched_this_session = true
  end
end

function M.open_browser()
  if current_state == STATE.STOPPED then
    vim.notify("[plantuml.nvim] Server is not running.", vim.log.levels.WARN)
    return
  end
  pending_file = current_filepath()
  browser.open("http://127.0.0.1:" .. config.http_port)
end

return M
