-- crypto.lua
-- Wrapper functions for lunatik's luacrypto.c module

-- example use:
-- local HKDF = require("hkdf")("sha256")

local crypto = require"crypto"
local hmac = crypto.hmac
local char, sp, rep, sub = string.char, string.pack, string.rep, string.sub


-- HKDF (RFC 5869)
return function (alg)
  local hash_len = #hmac(alg, "", "")  -- get hash length by running hmac with empty key/data
  local default_salt = rep("\0", hash_len)  -- default salt is zeros

  local function extract(salt, ikm)
    return hmac(alg, (salt or default_salt), ikm)
  end

  local function expand(prk, info, length)
    info = info or ""
    local n = length / hash_len  -- Lunatik division returns int
    n = (n * hash_len == length) and n or n + 1
    local okm, t = "", ""
    for i = 1, n do
      t = hmac(alg, prk, t .. info .. char(i))
      okm = okm .. t
    end
    return sub(okm, 1, length)
  end

  local function hkdf(salt, ikm, info, length)
    return expand(extract(salt, ikm), info, length)
  end

  -- TLS 1.3 HKDF-Expand-Label (RFC 8446, Section 7.1)
  local function tls13_expand_label(prk, label, context, length)
    return expand(prk, sp(">Hs1s1", length, "tls13 " .. label, context), length)
  end

  return {
    hkdf = hkdf,
    extract = extract,
    expand = expand,
    tls13_expand_label = tls13_expand_label,
  }
end
