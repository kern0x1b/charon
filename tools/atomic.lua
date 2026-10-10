-- The one atomic writer of the generators: tools/gen (through emit.lua) and tools/found (ir.lua) write their files through it
-- (design-spec-driven.md D2). A file is compared with the bytes on disk and written only when they differ, so an unchanged tree
-- writes nothing and keeps its mtimes. A changed file is written to a sibling in the same directory and renamed over the target: a
-- reader sees the old file or the new one, never a partial one, and the sibling never outlives a failed write. The sibling's name is
-- the target path, the process id and a counter, and a name a file already holds is skipped, so writers of one tree never share a
-- sibling. A failed write raises.

local counter = 0

local function read_bytes(filepath)
    if not os.isfile(filepath) then
        return nil
    end
    local handle = assert(io.open(filepath, "rb"))
    local data = handle:read("a")
    handle:close()
    return data
end

-- A sibling name of filepath that no file holds yet.
local function sibling_of(filepath)
    while true do
        counter = counter + 1
        local sibling = string.format("%s.charon-new.%d.%d", filepath, os.getpid(), counter)
        if not os.exists(sibling) then
            return sibling
        end
    end
end

-- Writes text to filepath when the file does not hold it already. Returns true when the file was written.
function write(filepath, text)
    if read_bytes(filepath) == text then
        return false
    end
    os.mkdir(path.directory(filepath))
    local sibling = sibling_of(filepath)
    try {
        function()
            local handle = assert(io.open(sibling, "wb"))
            handle:write(text)
            assert(handle:close())
            os.mv(sibling, filepath)
        end,
        catch {
            function(err)
                os.tryrm(sibling)
                raise("%s", err)
            end
        }
    }
    return true
end
