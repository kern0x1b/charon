-- metallib2es.lua: every function of a Metal library, as an OpenGL ES 2 shader of its own, into OUT with a
-- library.json naming them.
--   xmake l tools/air2es/metallib2es.lua <air2es> <LIB.metallib> <OUT>
-- A library is a run of AIR bitcode modules, each behind a wrapper of five little-endian words: the magic, the
-- version, the module's offset and its size within the wrapper, and the CPU type. Each module is written out,
-- handed to air2es, and its reflection read back; a module air2es refuses is named by its stdout and left out.
import("core.base.json")

local binary = {encoding = "binary"}

-- json.dump(..., indent=1) of this one shape, written by hand so the file is the one Python wrote: one
-- space of indentation per level, a space after each colon, no trailing newline.
local function quoted(text)
    local escapes = {['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
    return '"' .. text:gsub('[%c"\\]', function(c)
        return escapes[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

function main(tool, metallib, out)
    local data = io.readfile(metallib, binary)
    os.mkdir(out)
    local functions = {}
    local pos = 1
    local index = 0
    while true do
        local found = data:find("\xDE\xC0\x17\x0B", pos, true)
        if found == nil then
            break
        end
        local _, _, start, size = string.unpack("<I4I4I4I4I4", data, found)
        local module = path.join(out, "module" .. index .. ".bc")
        io.writefile(module, data:sub(found + start, found + start + size - 1), binary)
        local prefix = path.join(out, "module" .. index)
        local stdout = prefix .. ".out"
        local rc = os.execv(tool, {module, prefix}, {try = true, stdout = stdout, stderr = os.nuldev()})
        io.write(io.readfile(stdout, binary))
        os.rm(stdout)
        os.rm(module)
        if rc == 0 then
            local reflection = json.decode(io.readfile(prefix .. ".json"))
            local source = path.basename(prefix) .. (reflection.stage == "vertex" and ".vert" or ".frag")
            table.insert(functions, {name = reflection.entry, stage = reflection.stage, source = source,
                                     reflection = path.basename(prefix) .. ".json"})
        end
        index = index + 1
        pos = found + 4
    end

    local lines = {"{"}
    if #functions == 0 then
        table.insert(lines, ' "functions": []')
    else
        table.insert(lines, ' "functions": [')
        for i, f in ipairs(functions) do
            table.insert(lines, "  {")
            table.insert(lines, '   "name": ' .. quoted(f.name) .. ",")
            table.insert(lines, '   "stage": ' .. quoted(f.stage) .. ",")
            table.insert(lines, '   "source": ' .. quoted(f.source) .. ",")
            table.insert(lines, '   "reflection": ' .. quoted(f.reflection))
            table.insert(lines, i < #functions and "  }," or "  }")
        end
        table.insert(lines, " ]")
    end
    table.insert(lines, "}")
    io.writefile(path.join(out, "library.json"), table.concat(lines, "\n"), binary)
end
