-- Count every authenticated pointer slot of a dyld shared cache -- every `__auth_ptr` and
-- `__auth_got` word of every image -- and say how many of them modules/apple/dyld.lua's own
-- pointer_at puts inside an image section of that cache and how many it puts nowhere.
--
-- Usage: CHARON_ROOT=<worktree> xmake l auth-pointer-census.lua <cache> [image substring]
--
-- Why it exists: an arm64e cache stores its authenticated pointers as chained pointers, and a
-- reader that does not decode that encoding answers a slot with a number that is not an address.
-- This is the check that says whether ours does. One slot the reader cannot place is worth chasing;
-- a census of a whole cache is what tells "cannot" apart from "this one slot holds something else".
--
-- `__auth_stubs` is deliberately not counted: it is stub *code*, twelve bytes of adrp/add/br per
-- entry, and reading it as a table of pointers reports every stub as unreadable.
function main(cachefile, wanted)
    local dyld = import("apple.dyld", {rootdir = path.join(os.getenv("CHARON_ROOT"), "modules"), anonymous = true})
    local cache = dyld.open_cache(cachefile)
    local counts = {}
    local spans = {}
    for _, loaded in ipairs(cache.images) do
        for _, section in ipairs(loaded.image.sections) do
            table.insert(spans, {loaded.install .. " " .. section.name, section.addr, section.addr + section.size})
        end
    end
    local function where(a)
        for _, hit in ipairs(spans) do
            if a >= hit[2] and a < hit[3] then return hit[1] end
        end
        return nil
    end
    for _, loaded in ipairs(cache.images) do
        if wanted == nil or wanted == "*" or loaded.install:find(wanted, 1, true) then
            for _, section in ipairs(loaded.image.sections) do
                if section.name == "__auth_ptr" or section.name == "__auth_got" then
                    local placed, lost, zero = 0, 0, 0
                    local total = section.size // 8
                    local samples = {}
                    for offset = 0, section.size - 8, 8 do
                        local at = section.addr + offset
                        local value = cache.pointer_at(at, true)
                        if value == 0 then
                            zero = zero + 1
                        elseif cache.mapped(value, 1) then
                            if where(value) then
                                placed = placed + 1
                            else
                                lost = lost + 1
                            end
                        else
                            lost = lost + 1
                            if #samples < 5 then table.insert(samples, string.format("%#x->%#x", at, value)) end
                        end
                    end
                    if lost > 0 then
                        print(string.format("%s %s slots=%d placed=%d unplaced=%d zero=%d %s", loaded.install,
                                            section.name, total, placed, lost, zero, table.concat(samples, " ")))
                    end
                    counts[#counts + 1] = {total, placed, lost, zero}
                end
            end
        end
    end
    local total, placed, lost, zero = 0, 0, 0, 0
    for _, hit in ipairs(counts) do
        total, placed, lost, zero = total + hit[1], placed + hit[2], lost + hit[3], zero + hit[4]
    end
    print(string.format("#sections=%d slots=%d placed=%d unplaced=%d zero=%d", #counts, total, placed, lost, zero))
    cache.close()
end
