import("macho")

local caches = {}

local function cstring(data, at)
    local finish = data:find("\0", at + 1, true)
    return data:sub(at + 1, finish - 1)
end

local function uleb(data, at)
    local value, shift = 0, 0
    while true do
        local byte = data:byte(at + 1)
        at = at + 1
        value = value | ((byte & 0x7F) << shift)
        shift = shift + 7
        if byte < 0x80 then
            return value, at
        end
    end
end

function root()
    return path.join(os.getenv("CHARON_HOME") or path.join(os.getenv("HOME"), ".charon"), "dyld")
end

local function parts(version)
    local found = {}
    for part in tostring(version):gmatch("%d+") do
        table.insert(found, tonumber(part))
    end
    return found
end

local function compare(a, b)
    local left, right = parts(a), parts(b)
    for index = 1, math.max(#left, #right) do
        local x, y = left[index] or 0, right[index] or 0
        if x ~= y then
            return x < y and -1 or 1
        end
    end
    return 0
end

function compare_versions(a, b)
    return compare(a, b)
end

function held_source(folder, architecture)
    local cache = path.join(folder, "dyld_shared_cache_" .. architecture)
    if os.isfile(cache) then
        return cache
    end
    local libraries = path.join(folder, "libraries_" .. architecture)
    if os.isdir(libraries) then
        return libraries
    end
end

function held_releases(architecture)
    local releases = {}
    for _, folder in ipairs(os.dirs(path.join(root(), "*"))) do
        local release = path.filename(folder)
        if release:match("^%d+[%.%d]*$") and held_source(folder, architecture) then
            table.insert(releases, release)
        end
    end
    table.sort(releases, function (a, b) return compare(a, b) < 0 end)
    return releases
end

function held_cache(architecture, minimum)
    for _, release in ipairs(held_releases(architecture)) do
        if parts(release)[1] == parts(minimum)[1] and compare(release, minimum) >= 0 then
            return held_source(path.join(root(), release), architecture), release
        end
    end
    local expected = compare(minimum, "3.1") < 0 and "libraries_" or "dyld_shared_cache_"
    return path.join(root(), minimum, expected .. architecture), nil
end

local function loaded_image(found, architecture)
    local wanted = architecture == "armv7s" and {"armv7s", "armv7"} or {architecture}
    for _, candidate in ipairs(wanted) do
        for _, image in ipairs(found) do
            if image.architecture == candidate then
                return image
            end
        end
    end
end

local function defined_exports(data, image)
    local defined = {}
    if not image.symtab then
        return defined
    end
    local symoff, nsyms, stroff = image.symtab[1], image.symtab[2], image.symtab[3]
    local entry = image.wide and 16 or 12
    for index = 0, nsyms - 1 do
        local strx, kind = string.unpack("<I4B", data, image.base + symoff + index * entry + 1)
        if kind & 0xE0 == 0 and kind & 0x01 ~= 0 and kind & 0x0E ~= 0 then
            defined[cstring(data, image.base + stroff + strx)] = true
        end
    end
    return defined
end

local function load_libraries(folder)
    local architecture = path.filename(folder):match("^libraries_(.+)$")
    local exports, images, count = {}, {}, 0
    for _, binary in ipairs(macho.binaries_under(folder)) do
        local data = macho.read(binary)
        local image = loaded_image(macho.images(data), architecture)
        if image and image.identity then
            images[image.identity] = true
            for name in pairs(defined_exports(data, image)) do
                if not exports[name] then
                    exports[name] = true
                    count = count + 1
                end
            end
        end
    end
    if count == 0 then
        raise("%s holds no %s library exporting anything", folder, architecture)
    end
    return {architecture = architecture, exports = exports, images = images, count = count}
end

function load(cachefile)
    if caches[cachefile] then
        return caches[cachefile]
    end
    if os.isdir(cachefile) then
        caches[cachefile] = load_libraries(cachefile)
        return caches[cachefile]
    end
    local data = io.readfile(cachefile, {encoding = "binary"})
    if not data or not data:startswith("dyld_v1") then
        raise("%s is not a dyld shared cache", cachefile)
    end
    local architecture = data:sub(8, 16):gsub("[ %z]", "")
    local mapping_offset, mapping_count, images_offset, images_count = string.unpack("<I4I4I4I4", data, 17)
    local mappings = {}
    for index = 0, mapping_count - 1 do
        local start, size, offset = string.unpack("<I8I8I8", data, mapping_offset + index * 32 + 1)
        table.insert(mappings, {start, size, offset})
    end
    local function file_offset(address)
        for _, mapping in ipairs(mappings) do
            if mapping[1] <= address and address < mapping[1] + mapping[2] then
                return address - mapping[1] + mapping[3]
            end
        end
        raise("address %#x is outside every mapping of %s", address, cachefile)
    end
    local exports, images, count = {}, {}, 0
    local function export(name)
        if not exports[name] then
            exports[name] = true
            count = count + 1
        end
    end
    for index = 0, images_count - 1 do
        local entry = images_offset + index * 32
        local address = string.unpack("<I8", data, entry + 1)
        images[cstring(data, string.unpack("<I4", data, entry + 25))] = true
        local header = file_offset(address)
        local magic, _, _, _, command_count = string.unpack("<I4i4i4I4I4", data, header + 1)
        if magic == 0xFEEDFACE then
            local at = header + 28
            local trie, symtab
            for _ = 1, command_count do
                local command, size = string.unpack("<I4I4", data, at + 1)
                if command == 0x22 or command == 0x80000022 then
                    trie = {string.unpack("<I4I4", data, at + 8 + 32 + 1)}
                elseif command == 0x2 then
                    symtab = {string.unpack("<I4I4I4I4", data, at + 9)}
                end
                at = at + size
            end
            if trie and trie[2] ~= 0 then
                local stack = {{0, ""}}
                while #stack > 0 do
                    local node = table.remove(stack)
                    local cursor = trie[1] + node[1]
                    local terminal
                    terminal, cursor = uleb(data, cursor)
                    if terminal ~= 0 then
                        export(node[2])
                    end
                    cursor = cursor + terminal
                    local children = data:byte(cursor + 1)
                    cursor = cursor + 1
                    for _ = 1, children do
                        local finish = data:find("\0", cursor + 1, true)
                        local label = data:sub(cursor + 1, finish - 1)
                        local child
                        child, cursor = uleb(data, finish)
                        table.insert(stack, {child, node[2] .. label})
                    end
                end
            elseif symtab then
                local symbol_offset, symbol_count, string_offset = symtab[1], symtab[2], symtab[3]
                for k = 0, symbol_count - 1 do
                    local string_index, symbol_type = string.unpack("<I4B", data, symbol_offset + k * 12 + 1)
                    local kind = symbol_type & 0x0E
                    if symbol_type & 0x01 ~= 0 and (kind == 0x0A or kind == 0x0E) then
                        export(cstring(data, string_offset + string_index))
                    end
                end
            end
        end
    end
    local loaded = {architecture = architecture, exports = exports, images = images, count = count}
    caches[cachefile] = loaded
    return loaded
end

local function undefined_imports(data, image)
    local imported = {}
    if not image.symtab then
        return imported
    end
    local symoff, nsyms, stroff = image.symtab[1], image.symtab[2], image.symtab[3]
    local entry = image.wide and 16 or 12
    for index = 0, nsyms - 1 do
        local strx, kind, _, desc = string.unpack("<I4BBI2", data, image.base + symoff + index * entry + 1)
        if kind & 0xE0 == 0 and kind & 0x0E == 0 and kind & 0x01 ~= 0 then
            table.insert(imported, {name = cstring(data, image.base + stroff + strx), weak = desc & 0x40 ~= 0})
        end
    end
    return imported
end

function missing_imports(cachefile, binaries, root)
    local cache = load(cachefile)
    local missing = {}
    local found = {}
    local function named(binary)
        return root and path.relative(binary, root) or binary
    end
    for _, binary in ipairs(binaries) do
        local data = macho.read(binary)
        local image = loaded_image(macho.images(data), cache.architecture)
        if image then
            table.insert(found, {binary = binary, data = data, image = image})
        else
            table.insert(missing, {named(binary), string.format("(no slice a %s device loads)", cache.architecture)})
        end
    end
    local own, provided, provided_names = {}, {}, {}
    for _, entry in ipairs(found) do
        table.join2(own, defined_exports(entry.data, entry.image))
        if entry.image.identity then
            provided[entry.image.identity] = true
            provided_names[path.filename(entry.image.identity)] = true
        end
    end
    for _, entry in ipairs(found) do
        for index, library in ipairs(entry.image.libraries) do
            local relative = library:startswith("@")
            if entry.image.library_strength[index] and not (cache.images[library] or provided[library] or (relative and provided_names[path.filename(library)])) then
                table.insert(missing, {named(entry.binary), string.format("(loads %s, which neither the device nor this build provides)", library)})
            end
        end
        for _, symbol in ipairs(undefined_imports(entry.data, entry.image)) do
            if symbol.name:startswith("_") and not symbol.weak and not own[symbol.name] and not cache.exports[symbol.name] then
                table.insert(missing, {named(entry.binary), symbol.name})
            end
        end
    end
    table.sort(missing, function (a, b)
        return a[1] == b[1] and a[2] < b[2] or a[1] < b[1]
    end)
    return missing, #found, cache
end

function check(cachefile, binaries, folder)
    if not os.exists(cachefile) then
        raise("there is no shared cache at %s to check imports against: the check reads the cache of the oldest release of the same major version the port runs on, under a folder named after that release. Copy the dyld_shared_cache of such a device there once, or for a release before 3.1, which has no cache, its libraries as libraries_<arch> keeping their paths on the device (CHARON_HOME moves the root); a check that reports success having looked at nothing is worse than no check", cachefile)
    end
    local missing, count, cache = missing_imports(cachefile, binaries, folder)
    if #missing > 0 then
        local lines = {"these imports are not exported by the device's iOS:"}
        for _, entry in ipairs(missing) do
            table.insert(lines, "  " .. entry[1] .. "  " .. entry[2])
        end
        raise(table.concat(lines, "\n"))
    end
    cprint("imports: every non-weak import of the %s slices of %d binaries resolves against %d exports", cache.architecture, count, cache.count)
end
