-- PlantUML text → image URL encoding.
-- Pipeline: compress with LibDeflate zlib, encode with PlantUML's custom base64, build URL.

local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local LibDeflate = require("plantuml.vendor.LibDeflate.LibDeflate")

local MAP = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-_"

local function encode64(data)
  local out = {}
  local i, n = 1, #data
  while i <= n do
    local c1, c2, c3 = data:byte(i, i + 2)
    c1 = c1 or 0
    local b1 = rshift(c1, 2)
    if not c2 then
      local b2 = band(lshift(c1, 4), 0x3F)
      out[#out + 1] = MAP:sub(b1 + 1, b1 + 1)
      out[#out + 1] = MAP:sub(b2 + 1, b2 + 1)
      break
    else
      local b2 = band(bor(lshift(band(c1, 0x3), 4), rshift(c2, 4)), 0x3F)
      if not c3 then
        local b3 = band(lshift(band(c2, 0xF), 2), 0x3F)
        out[#out + 1] = MAP:sub(b1 + 1, b1 + 1)
        out[#out + 1] = MAP:sub(b2 + 1, b2 + 1)
        out[#out + 1] = MAP:sub(b3 + 1, b3 + 1)
        break
      else
        local b3 = band(bor(lshift(band(c2, 0xF), 2), rshift(c3, 6)), 0x3F)
        local b4 = band(c3, 0x3F)
        out[#out + 1] = MAP:sub(b1 + 1, b1 + 1)
        out[#out + 1] = MAP:sub(b2 + 1, b2 + 1)
        out[#out + 1] = MAP:sub(b3 + 1, b3 + 1)
        out[#out + 1] = MAP:sub(b4 + 1, b4 + 1)
        i = i + 3
      end
    end
  end
  return table.concat(out)
end

local M = {}

function M.encode(text, server_url)
  local compressed = LibDeflate:CompressZlib(text, { level = 9 })
  if not compressed then
    error("[plantuml.nvim] LibDeflate:CompressZlib failed.")
  end
  local encoded = encode64(compressed)
  return server_url .. "/png/~1" .. encoded
end

return M
