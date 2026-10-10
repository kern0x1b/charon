-- SHA-256 (FIPS 180-4) of a string in memory, in Lua 5.4 integer arithmetic. xmake's hash.sha256 takes a file path only, and
-- the generator hashes text it has not written anywhere (design-spec-driven.md D4). The rotations are written out in place and
-- the message schedule is one table reused for every block: a function call or a table per block costs more than the rounds.

local MASK = 0xffffffff

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local W = {}

-- Hashes the 64-byte block at position pos of data into the state H (eight words, updated in place).
local function compress(H, data, pos)
    W[1], W[2], W[3], W[4], W[5], W[6], W[7], W[8], W[9], W[10], W[11], W[12], W[13], W[14], W[15], W[16] =
        string.unpack(">I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4", data, pos)
    for t = 17, 64 do
        local x, y = W[t - 15], W[t - 2]
        local s0 = (((x >> 7) | (x << 25)) ~ ((x >> 18) | (x << 14)) ~ (x >> 3)) & MASK
        local s1 = (((y >> 17) | (y << 15)) ~ ((y >> 19) | (y << 13)) ~ (y >> 10)) & MASK
        W[t] = (s1 + W[t - 7] + s0 + W[t - 16]) & MASK
    end
    local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
    for t = 1, 64 do
        local S1 = (((e >> 6) | (e << 26)) ~ ((e >> 11) | (e << 21)) ~ ((e >> 25) | (e << 7))) & MASK
        local ch = (e & f) ~ ((~e) & g)
        local t1 = (h + S1 + ch + K[t] + W[t]) & MASK
        local S0 = (((a >> 2) | (a << 30)) ~ ((a >> 13) | (a << 19)) ~ ((a >> 22) | (a << 10))) & MASK
        local maj = (a & b) ~ (a & c) ~ (b & c)
        local t2 = (S0 + maj) & MASK
        h, g, f, e = g, f, e, (d + t1) & MASK
        d, c, b, a = c, b, a, (t1 + t2) & MASK
    end
    H[1], H[2], H[3], H[4] = (H[1] + a) & MASK, (H[2] + b) & MASK, (H[3] + c) & MASK, (H[4] + d) & MASK
    H[5], H[6], H[7], H[8] = (H[5] + e) & MASK, (H[6] + f) & MASK, (H[7] + g) & MASK, (H[8] + h) & MASK
end

-- The lowercase hex digest of a string (64 digits).
function hex(message)
    local length = #message
    local padded = message .. "\128" .. string.rep("\0", (55 - length) % 64) .. string.pack(">I8", length * 8)
    local H = {0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19}
    for pos = 1, #padded, 64 do
        compress(H, padded, pos)
    end
    return string.format("%08x%08x%08x%08x%08x%08x%08x%08x", H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8])
end
