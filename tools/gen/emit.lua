-- The writer of generated output in tools/gen (design-spec-driven.md D2). The bytes are written by the one atomic writer,
-- tools/atomic.lua, which the declaration driver (tools/found/ir.lua) uses for its shards too: a file the tree already holds is not
-- rewritten, and a changed file is replaced whole or not at all.

local atomic = import("atomic", {rootdir = path.join(os.scriptdir(), ".."), anonymous = true})

local written = 0

-- Writes text to filepath when the file does not hold it already. Returns true when the file was written.
function file(filepath, text)
    assert(not string.find(text, "[\128-\255]"), "not ASCII: " .. filepath)
    if not atomic.write(filepath, text) then
        return false
    end
    written = written + 1
    return true
end

-- The number of files written since the process started.
function count()
    return written
end
