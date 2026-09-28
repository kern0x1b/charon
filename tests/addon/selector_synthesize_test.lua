-- A property with BOTH an @synthesize binding and a hand-written accessor in the same
-- @implementation is two definitions of one method, and the compiler keeps one of them without saying
-- which. The cost is silent: the getter that survives can be the wrong one, and nothing in the build,
-- the link or the gate reports it. PHASEEngine's rootObject was exactly that, and the disassembly was
-- what named it after three rounds of measurement.
--
-- A *category* redefining a selector that the primary implementation synthesised is ordinary and is not
-- this, so the file is split into @implementation blocks and only a collision inside one of them counts.
-- That scoping is the whole check: without it the same query over the package reports 52 files rather
-- than the 5 that are in one implementation.
--
-- The Python twin of this is tests/backports/source/selector-synthesize/check.py, which proves itself
-- against two files it carries. This is the same query in the light guard's own language, and it is
-- here to run on every gate.
local function find(path)
    local handle = assert(io.open(path, "r"))
    local text = handle:read("*a")
    handle:close()
    local hits = {}
    -- each @implementation ... @end, with the category in the class name when it has one
    for name, category, body in text:gmatch("@implementation%s+([%w_]+)%s*([^%s{(]*)(.-)\n@end") do
        local flat = body:gsub("\n%s*", " ")
        for property in flat:gmatch("@synthesize%s+([%w_]+)%s*=") do
            for _, kind in ipairs({"-", "+"}) do
                local pattern = kind .. "%s*%b()%s*" .. property .. "%s*{"
                if flat:find(pattern) then
                    table.insert(hits, string.format("%s%s %s (@synthesize and a %s accessor)", name,
                                                      category == "" and " (primary)" or (" " .. category), property, kind))
                end
            end
        end
    end
    return hits
end

function failures(opt)
    local found = {}
    local root = opt.checkout
    for _, folder in ipairs({"packages", "modules"}) do
        local top = path.join(root, folder)
        if os.isdir(top) then
            -- os.files takes a glob, which is the tree walk the other suites use
            for _, file in ipairs(os.files(path.join(top, "**/*.m"))) do
                for _, hit in ipairs(find(file)) do
                    table.insert(found, string.format("%s: %s", file:sub(#root + 2), hit))
                end
            end
        end
    end
    return found
end
