-- Pure Lua SHA-1 using LuaJIT bit library.
-- Returns raw 20-byte binary digest.

local bit = require("bit")
local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local lshift, rshift, rol, tobit = bit.lshift, bit.rshift, bit.rol, bit.tobit

local function to_be(n)
  return string.char(
    band(rshift(n, 24), 255),
    band(rshift(n, 16), 255),
    band(rshift(n, 8), 255),
    band(n, 255)
  )
end

local function sha1(s)
  local h0, h1, h2, h3, h4 = 0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0
  local len = #s
  s = s .. "\128" .. string.rep("\0", (55 - len) % 64) .. to_be(0) .. to_be(len * 8)
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
    for j = 16, 79 do
      w[j] = rol(bxor(w[j - 3], w[j - 8], w[j - 14], w[j - 16]), 1)
    end
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

return sha1
