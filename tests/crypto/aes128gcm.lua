local util = require"util"
local bin2hex = util.bin2hex
local hex2bin = util.hex2bin
local c = require"crypto".new"gcm(aes)"

c:setkey"0123456789abcdef"
c:setauthsize(16)

local iv = "abcdefghijkl"  -- 12-byte nonce, must be unique per invocation
local plaintext = "plaintext"
local aad = "0123456789abcdef"


print("\n\nPlaintext: " .. plaintext)
print("iv: " .. iv)
print("aad: " .. aad)

print("IV: " .. bin2hex(iv) .. ", " .. #iv)
print("AAD: " .. bin2hex(aad) .. ", " .. #aad)


local ciphertext, tag_len = c:encrypt(iv, plaintext, aad)
print("CIHERTEXT: " .. bin2hex(ciphertext) .. ", " .. #ciphertext)
print("TAG_LEN: " .. tag_len)

c = require"crypto".new"gcm(aes)"

c:setkey"0123456789abcdef"
c:setauthsize(16)
local plaintext = c:decrypt(iv, ciphertext, aad)
print"Plaintext"
print(plaintext)