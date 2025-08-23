local default_config = {
  auto_start = true,
  auto_update = true,
  http_port = 8764,
  plantuml_server_url = "http://www.plantuml.com/plantuml",
  auto_launch_browser = "never",
}

local config = vim.deepcopy(default_config)

assert(pcall(require, "bit"), "[plantuml.nvim] Requires LuaJIT 'bit' library.")
local bit = require "bit"

local LibDeflate = require("plantuml.vendor.LibDeflate.LibDeflate")

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
    local b1 = bit.rshift(c1, 2)
    if not c2 then
      local b2 = bit.band(bit.lshift(c1, 4), 0x3F)
      out[#out + 1] = map:sub(b1 + 1, b1 + 1)
      out[#out + 1] = map:sub(b2 + 1, b2 + 1)
      break
    else
      local b2 = bit.band(bit.bor(bit.lshift(bit.band(c1, 0x3), 4), bit.rshift(c2, 4)), 0x3F)
      if not c3 then
        local b3 = bit.band(bit.lshift(bit.band(c2, 0xF), 2), 0x3F)
        out[#out + 1] = map:sub(b1 + 1, b1 + 1)
        out[#out + 1] = map:sub(b2 + 1, b2 + 1)
        out[#out + 1] = map:sub(b3 + 1, b3 + 1)
        break
      else
        local b3 = bit.band(bit.bor(bit.lshift(bit.band(c2, 0xF), 2), bit.rshift(c3, 6)), 0x3F)
        local b4 = bit.band(c3, 0x3F)
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
  local band, bor, bxor = bit.band, bit.bor, bit.bxor
  local lshift, rshift, rol, tobit = bit.lshift, bit.rshift, bit.rol, bit.tobit

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
          f, k = bor(band(b, c), band(bit.bnot(b), d)), 0x5A827999
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

local html_content = [[
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>PlantUML Viewer</title>
<style>
  :root{--bg:#0b0c0e;--fg:#d7d7db;--muted:#8b8d94;--pill-bg:#1a1b1e;--ok:#2ea043;--warn:#b8821f;--err:#be3431;--panel:#0f1013}
  *{box-sizing:border-box} html,body{height:100%;overflow:hidden;}
  body{margin:0;background:var(--bg);color:var(--fg);font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;display:flex;flex-direction:column}
  .top{display:flex;flex-direction:column;padding:.5rem .75rem;border-bottom:1px solid #111318;background:var(--panel)}
  .status-row{display:flex;align-items:center;gap:.75rem;margin-bottom:.5rem}
  .file-info{display:flex;flex-direction:column;gap:.25rem}
  .dot{width:.5rem;height:.5rem;border-radius:999px;display:inline-block;vertical-align:middle}
  .pill{display:inline-flex;align-items:center;gap:.35rem;padding:.15rem .45rem;border-radius:999px;background:var(--pill-bg);color:var(--muted);font-size:.75rem;font-weight:500}
  .pill .dot{background:var(--warn)}
  .pill.ok .dot{background:var(--ok)}
  .pill.err .dot{background:var(--err)}
  .pill.warn .dot{background:var(--warn)}
  .file{color:var(--fg);font-weight:600;font-size:1rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .server-link{color:var(--muted);font-size:.75rem;text-decoration:none;white-space:nowrap;overflow:hidden;text-overflow:ellipsis;display:block}
  .server-link:hover{color:var(--fg);text-decoration:underline}
  .timestamp{color:var(--muted);font-size:.75rem;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
  .wrap{flex:1;min-height:0;padding:0.75rem}
  .board{position:relative;width:100%;height:100%;display:flex;align-items:center;justify-content:center;border-radius:8px;background:#0c0d10;outline:1px solid #111318;overflow-y:auto;overflow-x:hidden;cursor:pointer}
  .board.has-diagram{align-items:flex-start}
  #img{display:none;opacity:0;transition:opacity .2s ease-in-out;height:auto;max-width:none;max-height:none}
  .board.has-diagram #img{display:block;width:100%}
  #ph{color:var(--muted);font-size:.9rem;text-align:center;}
  .board.fit-to-page{align-items:center;overflow:hidden}
  .board.has-diagram.fit-to-page{align-items:center}
  .board.fit-to-page #img{width:auto;height:auto;max-width:100%;max-height:100%}
</style>
</head>
<body>
  <div class="top">
    <div class="status-row">
      <span id="status" class="pill"><span class="dot"></span><span id="status-text">connecting</span></span>
    </div>
    <div class="file-info">
      <span class="file" id="file" title="filename"></span>
      <a class="server-link" id="server-url" href="#" target="_blank" title="PlantUML server URL"></a>
      <span class="timestamp" id="timestamp"></span>
    </div>
  </div>
  <div class="wrap">
    <div class="board fit-to-page" id="board">
      <img id="img" alt="PlantUML diagram">
      <p id="ph">Ready for a diagram.<br>Save a PlantUML file in Neovim to view it here.</p>
    </div>
  </div>
<script>
  const statusEl=document.getElementById("status"), statusText=document.getElementById("status-text");
  const fileEl=document.getElementById("file"), ph=document.getElementById("ph");
  const timestampEl=document.getElementById("timestamp"), serverUrlEl=document.getElementById("server-url");
  const img=document.getElementById("img"), board=document.getElementById("board");
  let isFitToPage = true;
  let hasLoadedDiagram = false;

  function setStatus(kind,text){
    statusEl.className = 'pill';
    if(kind) statusEl.classList.add(kind);
    statusText.textContent=text;
  }

  function isImageAtNaturalSize() {
    if (!img.naturalWidth || !img.naturalHeight) return false;
    const rect = img.getBoundingClientRect();
    return Math.abs(rect.width - img.naturalWidth) < 1 && Math.abs(rect.height - img.naturalHeight) < 1;
  }

  function doesImageFitVertically() {
    if (!img.naturalWidth || !img.naturalHeight) return false;
    const boardRect = board.getBoundingClientRect();
    return img.naturalHeight <= boardRect.height;
  }

  board.addEventListener('click', () => {
    if (!hasLoadedDiagram) return;
    if (isFitToPage && isImageAtNaturalSize()) return;
    if (isFitToPage && !isImageAtNaturalSize() && doesImageFitVertically() && img.naturalWidth > img.naturalHeight) return;
    isFitToPage = !isFitToPage;
    board.classList.toggle('fit-to-page', isFitToPage);
  });

  function wsPort() {
    const p = parseInt(location.port || "0", 10);
    return (p > 0) ? String(p + 1) : "8765";
  }

  function connect(){
    const host = location.hostname || "127.0.0.1";
    const wsUrl = "ws://" + host + ":" + wsPort();
    const ws = new WebSocket(wsUrl);

    ws.onopen = () => {
      setStatus("ok","Live");
      ws.send(JSON.stringify({type: "refresh"}));
    };

    ws.onmessage = e => {
      try{
        const data=JSON.parse(e.data);
        if(data.type==="update"&&data.url){
          // Reset to fit-to-page view on every update
          isFitToPage = true;
          board.classList.add('fit-to-page');

          if (!hasLoadedDiagram) {
            board.classList.add('has-diagram');
            hasLoadedDiagram = true;
          }
          setStatus("warn", "Reloading...");
          img.style.opacity = 0;
          if(data.filename){fileEl.textContent=data.filename; fileEl.title=data.filename;}
          if(data.timestamp){timestampEl.textContent="Updated: " + data.timestamp; timestampEl.title="Last update time";}
          if(data.url){serverUrlEl.textContent=data.url.length > 70 ? data.url.substring(0, 70) + "..." : data.url; serverUrlEl.href=data.url; serverUrlEl.title="Click to open PlantUML diagram"; serverUrlEl.style.display="block";}
          ph.style.display="none";
          img.src=data.url;
        }
      }catch(err){console.error(err);}
    };

    ws.onclose = () => { setStatus("err", "Reconnecting..."); setTimeout(connect, 1000); };
    ws.onerror = () => setStatus("err","Error");
  }

  img.onload = () => {
    img.style.opacity = 1;
    setStatus("ok", "Live");
  };

  setStatus("warn", "Connecting...");
  connect();
</script>
</body>
</html>
]]

local server = {}
local connected_clients = {}
local started = false
local browser_launched_this_session = false
local last_message = nil
local http_server = nil
local ws_server = nil

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
  local fin = bit.band(byte1, 0x80) ~= 0
  local opcode = bit.band(byte1, 0x0F)
  local masked = bit.band(byte2, 0x80) ~= 0
  local payload_len = bit.band(byte2, 0x7F)
  
  if not fin or opcode ~= 1 then return nil end
  
  local offset = 2
  if payload_len == 126 then
    if #data < 4 then return nil end
    payload_len = bit.bor(bit.lshift(data:byte(3), 8), data:byte(4))
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
      decoded[i] = string.char(bit.bxor(payload:byte(i), mask:byte((i - 1) % 4 + 1)))
    end
    return table.concat(decoded)
  else
    if #data < offset + payload_len then return nil end
    return data:sub(offset + 1, offset + payload_len)
  end
end

function server.broadcast(tbl)
  last_message = tbl
  local frame = encode_ws_frame(vim.json.encode(tbl))
  for client, _ in pairs(connected_clients) do
    if client and not client:is_closing() then
      client:write(frame)
    else
      connected_clients[client] = nil
    end
  end
end

local function has_connected_clients()
  for client, _ in pairs(connected_clients) do
    if client and not client:is_closing() then
      return true
    else
      connected_clients[client] = nil
    end
  end
  return false
end

function server.start()
  if started then return end
  started = true

  http_server = vim.loop.new_tcp()
  http_server:bind("127.0.0.1", config.http_port)
  http_server:listen(128, function(err)
    assert(not err, err)
    local client = vim.loop.new_tcp()
    http_server:accept(client)
    client:read_start(function(_, data)
      if data then
        local response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: " ..
          #html_content .. "\r\n\r\n" .. html_content
        client:write(response, function() client:close() end)
      end
    end)
  end)

  ws_server = vim.loop.new_tcp()
  ws_server:bind("127.0.0.1", config.http_port + 1)
  ws_server:listen(128, function(err)
    assert(not err, err)
    local client = vim.loop.new_tcp()
    ws_server:accept(client)
    local handshake_done = false
    client:read_start(function(err2, data)
      if err2 or not data then
        connected_clients[client] = nil; client:close(); return
      end
      vim.schedule(function()
        if not handshake_done then
          local key = data:match("Sec%-WebSocket%-Key: ([%w%+/=]+)")
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
            handshake_done = true
          end
        else
          local payload = decode_ws_frame(data)
          if payload then
            local ok, message = pcall(vim.json.decode, payload)
            if ok and message and message.type == "refresh" and last_message then
              local frame = encode_ws_frame(vim.json.encode(last_message))
              client:write(frame)
            end
          end
        end
      end)
    end)
  end)
end

local M = {}

function M.update_diagram()
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
  local plantuml_url = config.plantuml_server_url .. "/png/~1" .. encoded_data

  if #plantuml_url > 8000 then
    vim.notify("PlantUML: Resulting URL is very long and may be rejected by the server.", vim.log.levels.WARN)
  end

  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local server_url = config.plantuml_server_url

  server.broadcast({ 
    type = "update", 
    url = plantuml_url, 
    filename = filename,
    timestamp = timestamp,
    server_url = server_url
  })

  if not has_connected_clients() and started then
    if config.auto_launch_browser == "always" then
      M.open_browser()
    elseif config.auto_launch_browser == "once" and not browser_launched_this_session then
      M.open_browser()
      browser_launched_this_session = true
    end
  end
end

function M.start()
  server.start()
end

function M.is_running()
  return started
end

function M.open_browser()
  if not started then
    vim.notify("[plantuml.nvim] Server is not running.", vim.log.levels.WARN)
    return
  end
  
  local url = "http://127.0.0.1:" .. config.http_port
  vim.ui.open(url)
end

function M.stop()
  if not started then
    vim.notify("[plantuml.nvim] Server is not running.", vim.log.levels.WARN)
    return
  end
  started = false
  
  for client, _ in pairs(connected_clients) do
    if client and not client:is_closing() then
      client:close()
    end
  end
  connected_clients = {}
  
  if http_server and not http_server:is_closing() then
    http_server:close()
  end
  if ws_server and not ws_server:is_closing() then
    ws_server:close()
  end
  
  vim.notify("[plantuml.nvim] Server stopped.", vim.log.levels.INFO)
end

function M.setup(user_config)
  if user_config then
    config = vim.tbl_deep_extend("force", default_config, user_config)
  end
end

function M.get_config()
  return vim.deepcopy(config)
end

return M
