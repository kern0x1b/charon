import("core.base.json")
import("dyld")

local RELATIVE_METHODS = 0x80000000

local function merge(into, from)
    for key in pairs(from) do
        into[key] = true
    end
end
local SELECTOR_OFFSETS = 0x40000000

local function reader(cache)
    local wide = cache.architecture:startswith("arm64")
    local size = wide and 8 or 4
    local strings = {}
    local selector_base
    local objc_offset, objc_size = cache.field(cache.main, 0x1d0, "<I8"), cache.field(cache.main, 0x1d8, "<I8")
    if objc_offset and objc_size and objc_size >= 56 then
        local base_address = string.unpack("<I8", cache.read(cache.main, cache.main.mapping_offset, 8))
        local header = cache.read_address(base_address + objc_offset, 56)
        selector_base = base_address + string.unpack("<I8", header, 48 + 1)
    else
        for _, loaded in ipairs(cache.images) do
            if loaded.install == "/usr/lib/libobjc.A.dylib" then
                for _, section in ipairs(loaded.image.sections) do
                    if section.name == "__objc_opt_ro" and section.size >= 48 then
                        local opt = cache.read_address(section.addr, 48)
                        if string.unpack("<I4", opt, 1) >= 16 then
                            selector_base = section.addr + string.unpack("<i8", opt, 40 + 1)
                        end
                    end
                end
            end
        end
    end
    local self = {wide = wide, size = size, mapped = cache.mapped, relative_lists = cache.main.mapping_offset >= 0x138}
    function self.pointer(address)
        if not cache.mapped(address, size) then
            return 0
        end
        return cache.pointer_at(address, wide)
    end
    function self.u32(address)
        return string.unpack("<I4", cache.read_address(address, 4))
    end
    function self.i32(address)
        return string.unpack("<i4", cache.read_address(address, 4))
    end
    function self.string(address)
        if address == 0 or not cache.mapped(address) then
            return nil
        end
        local found = strings[address]
        if not found then
            found = cache.string_at(address)
            strings[address] = found
        end
        return found
    end
    function self.selector_base()
        if not selector_base then
            raise("%s lists methods by selector offsets but names no Objective-C optimization header", cache.main.path)
        end
        return selector_base
    end
    return self
end

local function method_list(read, address, names)
    local flags, count = read.u32(address), read.u32(address + 4)
    local entry_size = flags & 0xFFFC
    if entry_size == 0 or not read.mapped(address + 8, count * entry_size) then
        return names
    end
    for index = 0, count - 1 do
        local entry = address + 8 + index * entry_size
        local name
        if read.relative_lists and flags & RELATIVE_METHODS ~= 0 then
            local offset = read.i32(entry)
            if flags & SELECTOR_OFFSETS ~= 0 then
                name = read.string(read.selector_base() + offset)
            else
                name = read.string(read.pointer(entry + offset))
            end
        else
            name = read.string(read.pointer(entry))
        end
        if name then
            names["-" .. name] = true
        end
    end
end

local function lists(read, address, each)
    if address == 0 then
        return
    end
    if address & 1 ~= 0 then
        local list = address & ~1
        if not read.mapped(list, 8) then
            return
        end
        local entry_size, count = read.u32(list), read.u32(list + 4)
        for index = 0, count - 1 do
            local entry = list + 8 + index * entry_size
            if read.mapped(entry, 8) then
                local packed = string.unpack("<i8", read.raw(entry, 8))
                local offset = packed >> 16
                if offset >= 0x800000000000 then
                    offset = offset - 0x1000000000000
                end
                each(entry + offset)
            end
        end
        return
    end
    each(address)
end

local function method_names(read, address)
    local names = {}
    lists(read, address, function (list)
        if read.mapped(list, 8) then
            method_list(read, list, names)
        end
    end)
    return names
end

local function protocol_list(read, address, names)
    if not read.mapped(address, read.size) then
        return
    end
    local count = read.wide and string.unpack("<I8", read.raw(address, 8)) or read.u32(address)
    if not read.mapped(address, (count + 1) * read.size) then
        return
    end
    for index = 0, count - 1 do
        local protocol = read.pointer(address + read.size * (index + 1))
        local name = protocol ~= 0 and read.mapped(protocol, 2 * read.size) and read.string(read.pointer(protocol + read.size))
        if name then
            names[name] = true
        end
    end
end

local function protocol_names(read, address)
    local names = {}
    lists(read, address, function (list)
        protocol_list(read, list, names)
    end)
    return names
end

local function class_data(read, class)
    if class == 0 or not read.mapped(class, 5 * read.size) then
        return {methods = 0, protocols = 0}
    end
    local data = read.pointer(class + 4 * read.size) & (read.wide and ~7 or ~3)
    if not read.mapped(data, 7 * read.size) then
        return {methods = 0, protocols = 0}
    end
    local offsets = read.wide and {name = 24, methods = 32, protocols = 40} or {name = 16, methods = 20, protocols = 24}
    return {
        name = read.string(read.pointer(data + offsets.name)),
        methods = read.pointer(data + offsets.methods),
        protocols = read.pointer(data + offsets.protocols)
    }
end

local function section_entries(read, image, wanted)
    local entries = {}
    for _, section in ipairs(image.sections) do
        if section.name == wanted then
            for index = 0, section.size // read.size - 1 do
                table.insert(entries, read.pointer(section.addr + index * read.size))
            end
        end
    end
    return entries
end

function inventory(cachefile)
    local cache = dyld.open_cache(cachefile)
    local read = reader(cache)
    function read.raw(address, count)
        return cache.read_address(address, count)
    end
    local classes, protocols = {}, {}
    local function entry(name)
        local found = classes[name]
        if not found then
            found = {instance = {}, class = {}, protocols = {}}
            classes[name] = found
        end
        return found
    end
    for _, loaded in ipairs(cache.images) do
        for _, class in ipairs(section_entries(read, loaded.image, "__objc_classlist")) do
            local data = class_data(read, class)
            if data.name then
                local found = entry(data.name)
                found.image = loaded.install
                local superclass = read.pointer(class + read.size)
                found.superclass = superclass ~= 0 and class_data(read, superclass).name or nil
                merge(found.instance, method_names(read, data.methods))
                merge(found.protocols, protocol_names(read, data.protocols))
                local metaclass = read.pointer(class)
                if metaclass ~= 0 then
                    merge(found.class, method_names(read, class_data(read, metaclass).methods))
                end
            end
        end
        for _, category in ipairs(section_entries(read, loaded.image, "__objc_catlist")) do
            local class = read.pointer(category + read.size)
            local name = class ~= 0 and class_data(read, class).name
            if name then
                local found = entry(name)
                merge(found.instance, method_names(read, read.pointer(category + 2 * read.size)))
                merge(found.class, method_names(read, read.pointer(category + 3 * read.size)))
                merge(found.protocols, protocol_names(read, read.pointer(category + 4 * read.size)))
            end
        end
        for _, protocol in ipairs(section_entries(read, loaded.image, "__objc_protolist")) do
            local name = read.string(read.pointer(protocol + read.size))
            if name then
                local found = protocols[name] or {instance = {}, class = {}}
                merge(found.instance, method_names(read, read.pointer(protocol + 3 * read.size)))
                merge(found.class, method_names(read, read.pointer(protocol + 4 * read.size)))
                merge(found.instance, method_names(read, read.pointer(protocol + 5 * read.size)))
                merge(found.class, method_names(read, read.pointer(protocol + 6 * read.size)))
                protocols[name] = found
            end
        end
    end
    cache.close()
    return {architecture = cache.architecture, classes = classes, protocols = protocols}
end
