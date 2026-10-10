-- The one writer of generated output (design-spec-driven.md D2). A file is compared with the bytes on disk and written only
-- when they differ, so an unchanged tree writes nothing and keeps its mtimes. A changed file is written to a sibling and
-- renamed over the target: a reader sees the old file or the new one, never a partial one, and the sibling never outlives
-- a failed write.

local written = 0

local function read_bytes(filepath)
    if not os.isfile(filepath) then
        return nil
    end
    local handle = io.open(filepath, "rb")
    local data = handle:read("a")
    handle:close()
    return data
end

-- Writes text to filepath when the file does not hold it already. Returns true when the file was written.
function file(filepath, text)
    assert(not string.find(text, "[\128-\255]"), "not ASCII: " .. filepath)
    if read_bytes(filepath) == text then
        return false
    end
    os.mkdir(path.directory(filepath))
    local sibling = filepath .. ".charon-new"
    try {
        function()
            local handle = assert(io.open(sibling, "wb"))
            handle:write(text)
            handle:close()
            os.mv(sibling, filepath)
        end,
        catch {
            function(err)
                os.tryrm(sibling)
                error(err)
            end
        }
    }
    written = written + 1
    return true
end

-- The number of files written since the process started.
function count()
    return written
end
