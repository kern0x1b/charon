-- The host differential for Matter: what macOS's own Matter.framework carries, against the SDK 26.2 surface the
-- port implements, against what the port's own libMatterBackports.dylib carries.
--
-- The host's framework is in its dyld shared cache and not on disk, so the binary is written out first
-- (dyld.extract). Everything after that is read the same way the gate reads a library: the exports from the symbol
-- table, the classes and their selectors from the Objective-C metadata.
--
-- The three answers this exists to tell apart:
--
--   surface only   the SDK declares it, the host's framework has no such name, and neither does the port's. A row of
--                  the SDK 26.2 surface that no release of the framework carries, which is a row the port does not
--                  owe anything for.
--   host carries   the host's framework carries it and the port's does not: a row the port is missing, named.
--   port carries   the port's library carries it and the host's framework has no such name: either a row of a later
--                  SDK than the host's, or a name of the port's own. Both are said, not glossed.
--
-- Usage: xmake l tools/matter-host-diff.lua <corpus.tsv> <host.dylib> [port.dylib] [architecture]
import("core.base.json")
local objc = import("apple.objc", {rootdir = path.join(os.scriptdir(), "..", "modules"), anonymous = true})
local macho = import("apple.macho", {rootdir = path.join(os.scriptdir(), "..", "modules"), anonymous = true})

local FRAMEWORK = "Matter"

local function api_symbol(symbol)
    if symbol:startswith("_OBJC_METACLASS_$_") or symbol:startswith("_OBJC_IVAR_$_") or symbol:startswith("__Z")
       or symbol:startswith("___Z") or symbol:startswith("__Unwind_") or symbol:startswith("_unwind_") or symbol:startswith("$")
       or symbol:startswith("__dso_handle") or symbol:startswith("$") or symbol:startswith("__swift") or symbol:startswith("swift_") then
        return nil
    end
    return symbol:sub(2)
end

local function symbols_of(binary)
    local found = {}
    local data = macho.read(binary)
    for _, image in ipairs(macho.images(data)) do
        if image.symtab then
            local symoff, nsyms, stroff = image.symtab[1], image.symtab[2], image.symtab[3]
            local entry = image.wide and 16 or 12
            for index = 0, nsyms - 1 do
                local strx, kind, _, _, value = string.unpack(image.wide and "<I4BBI2I8" or "<I4BBI2I4", data, image.base + symoff + index * entry + 1)
                if kind & 0xE0 == 0 and kind & 0x01 ~= 0 and kind & 0x10 == 0 and value ~= 0 then
                    local finish = data:find("\0", image.base + stroff + strx + 1, true)
                    found[data:sub(image.base + stroff + strx + 1, finish - 1)] = true
                end
            end
        end
    end
    return found
end

-- The classes, their members and the symbols a binary carries.
local function surface(binary, architecture)
    local found = {classes = {}, members = {}, symbols = {}, protocols = {}}
    for symbol in pairs(symbols_of(binary)) do
        local class = symbol:match("^_OBJC_CLASS_%$_(.+)$")
        if class then
            found.classes[class] = true
        else
            local name = api_symbol(symbol)
            if name then
                found.symbols[name] = true
            end
        end
    end
    local inventory = objc.binary_inventory(binary, architecture)
    if not inventory then
        raise("%s has no %s slice", binary, architecture)
    end
    for name, class in pairs(inventory.classes) do
        found.classes[name] = true
        for kind, sign in pairs({instance = "-", class = "+"}) do
            for selector in pairs(class[kind]) do
                found.members[string.format("%s[%s %s]", sign, name, selector:sub(2))] = true
            end
        end
        for protocol in pairs(class.protocols) do
            found.protocols[protocol] = true
        end
    end
    for name in pairs(inventory.protocols) do
        found.protocols[name] = true
    end
    return found
end

local function answered(found, row)
    local api, kind = row.api, row.kind
    local class, selector = api:match("^([-+])\\[([%w_]+) (.+)%]$")
    local owner, name = api:match("^([%u][%w_]*)%.(.+)$")
    if kind == "class" then
        return found.classes[api]
    elseif kind == "protocol" then
        return found.protocols[api]
    elseif kind == "method" then
        if class then
            return found.members[api]
        end
        return owner and (found.members["-[" .. owner .. " " .. name .. "]"] or found.members["+[" .. owner .. " " .. name .. "]"])
    elseif kind == "property" then
        if not owner then
            return nil
        end
        if found.members["-[" .. owner .. " " .. name .. "]"] or found.members["-[" .. owner .. " set" .. name:sub(1, 1):upper() .. name:sub(2) .. ":]"] then
            return true
        end
        for _, prefix in ipairs({"is", "has", "as", "can", "should", "will", "did"}) do
            if found.members["-[" .. owner .. " " .. prefix .. name:sub(1, 1):upper() .. name:sub(2) .. "]"] then
                return true
            end
        end
        return nil
    elseif kind == "constant" or kind == "function" then
        return found.symbols[api:gsub("%(%)$", "")]
    end
    return nil
end

local function rows_of(corpus)
    local rows, seen = {}, {}
    for line in io.lines(corpus) do
        local fields = {}
        for field in (line .. "\t"):gmatch("([^\t]*)\t") do
            table.insert(fields, field)
        end
        if fields[1] == FRAMEWORK and fields[4] ~= "" and fields[2] ~= "framework" and not seen[fields[4]] then
            seen[fields[4]] = true
            table.insert(rows, {kind = fields[2], api = fields[4], introduced = fields[5]})
        end
    end
    return rows
end

function main(corpus, host, port, architecture)
    architecture = architecture or "arm64e"
    local rows = rows_of(corpus)
    local theirs = surface(host, architecture)
    -- With no port library to compare, the third column is the host's alone, which is still worth having: it says which
    -- rows of the SDK 26.2 surface this host's own framework carries.
    local ours, haveport
    if port and os.isfile(port) then
        ours = surface(port, port:find("libMatterBackports", 1, true) and "armv7" or architecture)
        haveport = true
    else
        ours = {classes = {}, members = {}, symbols = {}, protocols = {}}
    end
    local bykind, tally = {}, {}
    local function count(kind, answer)
        bykind[kind] = bykind[kind] or {surface_only = 0, host_carries = 0, port_carries = 0, both = 0, neither = 0}
        bykind[kind][answer] = bykind[kind][answer] + 1
        tally[answer] = (tally[answer] or 0) + 1
    end
    local lines = {}
    for _, row in ipairs(rows) do
        local here, there = answered(ours, row), answered(theirs, row)
        local answer
        if haveport then
            if here and there then
                answer = "both"
            elseif here then
                answer = "port_carries"
            elseif there then
                answer = "host_carries"
            else
                answer = "surface_only"
            end
        else
            answer = there and "host_carries" or "surface_only"
        end
        count(row.kind, answer)
        if answer == "host_carries" or answer == "port_carries" then
            table.insert(lines, string.format("%s\t%s\t%s\t%s", answer, row.kind, row.api, row.introduced or ""))
        end
    end
    table.sort(lines)
    print("Matter: %d rows of the SDK 26.2 surface", #rows)
    for _, answer in ipairs({"both", "host_carries", "port_carries", "surface_only"}) do
        print("  %-13s %d", answer, tally[answer] or 0)
    end
    print("  by kind:")
    for _, kind in ipairs(table.orderkeys(bykind)) do
        local counts = bykind[kind]
        print("    %-10s both %-6d host only %-6d port only %-6d neither %d", kind, counts.both, counts.host_carries,
              counts.port_carries, counts.surface_only)
    end
    local out = path.join(os.curdir(), "matter-host-diff.tsv")
    io.writefile(out, table.concat(lines, "\n") .. "\n")
    print("wrote %d rows of difference to %s", #lines, out)
end
