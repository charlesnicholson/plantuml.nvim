-- WebSocket server on a separate TCP port.
-- Handles HTTP upgrade handshake, frame encode/decode, client ID management.
-- Communicates with init.lua via callbacks: on_connect, on_message, on_disconnect.

local sha1 = require("plantuml.sha1")
local bit = require("bit")
local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

local WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

local M = {}

local tcp = nil
local clients = {} -- client_id → { handle, buf }
local handle_to_id = {} -- uv_handle → client_id
local next_id = 1
local callbacks = nil

-- Encode a server→client text frame (unmasked).
local function encode_frame(payload)
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

-- Try to decode one complete frame from buf.
-- Returns payload, bytes_consumed on success; nil, 0 if incomplete.
local function decode_frame(buf)
  if #buf < 2 then return nil, 0 end
  local byte1, byte2 = buf:byte(1, 2)
  local opcode = band(byte1, 0x0F)
  local masked = band(byte2, 0x80) ~= 0
  local payload_len = band(byte2, 0x7F)
  local offset = 2

  if payload_len == 126 then
    if #buf < 4 then return nil, 0 end
    payload_len = bor(lshift(buf:byte(3), 8), buf:byte(4))
    offset = 4
  elseif payload_len == 127 then
    if #buf < 10 then return nil, 0 end
    -- Only use last 4 bytes (frames > 4GB not expected)
    payload_len = bor(
      lshift(buf:byte(7), 24),
      lshift(buf:byte(8), 16),
      lshift(buf:byte(9), 8),
      buf:byte(10)
    )
    offset = 10
  end

  local mask_len = masked and 4 or 0
  local total = offset + mask_len + payload_len
  if #buf < total then return nil, 0 end

  local payload
  if masked then
    local mask = buf:sub(offset + 1, offset + 4)
    local raw = buf:sub(offset + 5, offset + 4 + payload_len)
    local decoded = {}
    for i = 1, #raw do
      decoded[i] = string.char(bxor(raw:byte(i), mask:byte((i - 1) % 4 + 1)))
    end
    payload = table.concat(decoded)
  else
    payload = buf:sub(offset + 1, offset + payload_len)
  end

  return { opcode = opcode, payload = payload }, total
end

local function safe_write(handle, data)
  if handle and not handle:is_closing() then
    local ok = pcall(function() handle:write(data) end)
    return ok
  end
  return false
end

local function close_client(client_id)
  local c = clients[client_id]
  if not c then return end
  handle_to_id[c.handle] = nil
  clients[client_id] = nil
  if not c.handle:is_closing() then
    pcall(function() c.handle:close() end)
  end
  if callbacks and callbacks.on_disconnect then
    callbacks.on_disconnect(client_id)
  end
end

local function make_client_id()
  local id = "ws-" .. next_id
  next_id = next_id + 1
  return id
end

local function handle_handshake(handle, buf)
  if not buf:find("\r\n\r\n") then
    return false, buf -- incomplete headers, keep buffering
  end
  local key = buf:match("Sec%-WebSocket%-Key: ([%w%+/=]+)")
  if not key then
    if not handle:is_closing() then handle:close() end
    return true, "" -- bad handshake, discard
  end
  local accept = vim.base64.encode(sha1(key .. WS_GUID))
  local resp = "HTTP/1.1 101 Switching Protocols\r\n"
    .. "Upgrade: websocket\r\n"
    .. "Connection: Upgrade\r\n"
    .. "Sec-WebSocket-Accept: " .. accept .. "\r\n\r\n"
  handle:write(resp)

  local client_id = make_client_id()
  clients[client_id] = { handle = handle, buf = "" }
  handle_to_id[handle] = client_id

  if callbacks and callbacks.on_connect then
    callbacks.on_connect(client_id)
  end

  -- Process any data that arrived after the headers in the same chunk
  local header_end = buf:find("\r\n\r\n")
  local remainder = buf:sub(header_end + 4)
  if #remainder > 0 then
    clients[client_id].buf = remainder
  end

  return true, ""
end

local function process_frames(client_id)
  local c = clients[client_id]
  if not c then return end

  while true do
    local frame, consumed = decode_frame(c.buf)
    if not frame then break end
    c.buf = c.buf:sub(consumed + 1)

    if frame.opcode == 0x8 then
      -- Close frame: send close back then disconnect
      safe_write(c.handle, string.char(0x88, 0))
      close_client(client_id)
      return
    elseif frame.opcode == 0x9 then
      -- Ping: respond with pong
      safe_write(c.handle, string.char(0x8A, #frame.payload) .. frame.payload)
    elseif frame.opcode == 0xA then
      -- Pong: ignore
    elseif frame.opcode == 0x1 then
      -- Text frame
      if callbacks and callbacks.on_message then
        callbacks.on_message(client_id, frame.payload)
      end
    end
  end
end

function M.start(port, cbs)
  if tcp then
    return false, "WebSocket server already running"
  end

  callbacks = cbs
  next_id = 1

  local t = vim.uv.new_tcp()
  local ok, err = pcall(function() t:bind("127.0.0.1", port) end)
  if not ok then
    t:close()
    return false, "Failed to bind WebSocket server on port " .. port .. ": " .. tostring(err)
  end

  local ok2, err2 = pcall(function()
    t:listen(128, function(listen_err)
      if listen_err then return end
      local handle = vim.uv.new_tcp()
      t:accept(handle)
      local handshake_done = false
      local handshake_buf = ""

      handle:read_start(function(read_err, data)
        if read_err or not data then
          local cid = handle_to_id[handle]
          if cid then
            close_client(cid)
          else
            if not handle:is_closing() then handle:close() end
          end
          return
        end

        vim.schedule(function()
          if not handshake_done then
            handshake_buf = handshake_buf .. data
            local done, remainder = handle_handshake(handle, handshake_buf)
            if done then
              handshake_done = true
              handshake_buf = nil
              -- Process any leftover frames
              local cid = handle_to_id[handle]
              if cid and clients[cid] and #clients[cid].buf > 0 then
                process_frames(cid)
              end
            else
              handshake_buf = remainder
            end
          else
            local cid = handle_to_id[handle]
            if cid and clients[cid] then
              clients[cid].buf = clients[cid].buf .. data
              process_frames(cid)
            end
          end
        end)
      end)
    end)
  end)
  if not ok2 then
    t:close()
    return false, "Failed to listen on WebSocket server: " .. tostring(err2)
  end

  tcp = t
  return true
end

function M.stop()
  -- Close all client connections
  local ids = {}
  for id in pairs(clients) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do
    close_client(id)
  end
  clients = {}
  handle_to_id = {}

  if tcp then
    if not tcp:is_closing() then tcp:close() end
    tcp = nil
  end
  callbacks = nil
end

function M.send(client_id, tbl)
  local c = clients[client_id]
  if not c then return end
  safe_write(c.handle, encode_frame(vim.json.encode(tbl)))
end

function M.broadcast(tbl)
  local frame = encode_frame(vim.json.encode(tbl))
  local dead = {}
  for id, c in pairs(clients) do
    if not safe_write(c.handle, frame) then
      dead[#dead + 1] = id
    end
  end
  for _, id in ipairs(dead) do
    close_client(id)
  end
end

function M.send_to(client_ids, tbl)
  local frame = encode_frame(vim.json.encode(tbl))
  for _, id in ipairs(client_ids) do
    local c = clients[id]
    if c then
      safe_write(c.handle, frame)
    end
  end
end

function M.client_count()
  local n = 0
  for _ in pairs(clients) do n = n + 1 end
  return n
end

function M.is_connected(client_id)
  return clients[client_id] ~= nil
end

return M
