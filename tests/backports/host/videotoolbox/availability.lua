-- availability.lua [SDK] - which iOS release a string constant arrived in, read from the SDK's own header line.
--
--    xmake l availability.lua <an SDK directory>      (or VT_SDK=<an SDK directory> xmake l availability.lua)
--
-- VideoToolbox declares its string constants with the availability ON THE DECLARATION'S OWN LINE:
--
--    VTCompressionProperties.h:1076
--    VT_EXPORT const CFStringRef kVTAlphaChannelMode_PremultipliedAlpha	API_AVAILABLE(macos(10...
--
-- so the rule the seventeen CLASSES need - the nearest API_AVAILABLE ABOVE the declaration - matches none of them, and a
-- reader built that way reports every constant as unstated. It is the opposite order for the two subjects, and both orders
-- have to be tried: the line's own availability first, then the line below, then the lines above it.
--
-- That is why there is a control for BOTH shapes here, and a decoy: a reader that can only answer one shape is a reader
-- that will quietly say "unstated" about the other. The Python this replaces was availability.py.
--
-- The two regular expressions the Python used are written out by hand below:
--   AVAILABLE    API_AVAILABLE\((?:[^()]|\([^()]*\))*?ios\((\d+(?:\.\d+)*)\s*\)
--                a lazy run of single non-parenthesis characters and one-level (...) groups, then "ios(" wherever it
--                starts (inside "visionos(" too, as the regex found it), the version, the blanks and ")"
--   DECLARATION  ^\s*(?:VT_EXPORT\s+|extern\s+)?const\s+CFStringRef\s+(\w+)

local lib = import("vtlib", {rootdir = os.scriptdir(), anonymous = true})

-- The ios() version the macro at `pos` (just after "API_AVAILABLE(") states, or nil. Each step asks first whether
-- "ios(<version>)" starts here, and otherwise consumes one unit: a character that is not a parenthesis, or a "(" that
-- has a ")" before the next "(", which is the one-level group the regex allows.
local function ios_version_from(line, pos)
    local p = pos
    while true do
        if string.sub(line, p, p + 3) == "ios(" then
            local version = line:match("^%d+", p + 4)
            if version then
                local j = p + 4 + #version
                while true do
                    local part = line:match("^%.%d+", j)
                    if not part then
                        break
                    end
                    version = version .. part
                    j = j + #part
                end
                j = j + #line:match("^%s*", j)
                if string.sub(line, j, j) == ")" then
                    return version
                end
            end
        end
        local c = string.sub(line, p, p)
        if c == "" or c == ")" then
            return nil
        elseif c == "(" then
            local close = string.find(line, "[()]", p + 1)
            if not close or string.sub(line, close, close) ~= ")" then
                return nil
            end
            p = close + 1
        else
            p = p + 1
        end
    end
end

-- The release a line's API_AVAILABLE states for iOS, or nil: the leftmost macro that has an ios() version.
local function available(line)
    local from = 1
    while true do
        local s, e = string.find(line, "API_AVAILABLE(", from, true)
        if not s then
            return nil
        end
        local version = ios_version_from(line, e + 1)
        if version then
            return version
        end
        from = s + 1
    end
end

-- The release from a declaration at line `index` (1-based), trying the shapes in order: its own line, the line below it,
-- then up to ten lines above it. Returns the release (or nil) and the 1-based line the macro is on.
local function release_near(lines, index)
    local own = available(lines[index])
    if own then
        return own, index
    end
    if index + 1 <= #lines then
        local below = available(lines[index + 1])
        if below then
            return below, index + 1
        end
    end
    for back = index - 1, math.max(1, index - 10), -1 do
        local above = available(lines[back])
        if above then
            return above, back
        end
    end
    return nil, index
end

-- The name a line declares, as ^\s*(?:VT_EXPORT\s+|extern\s+)?const\s+CFStringRef\s+(\w+) reads it, or nil.
local function declared_name(line)
    local rest = line:match("^%s*(.*)$")
    local prefix = rest:match("^VT_EXPORT%s+") or rest:match("^extern%s+")
    if prefix then
        rest = rest:sub(#prefix + 1)
    end
    return rest:match("^const%s+CFStringRef%s+([%w_]+)")
end

local function header_texts(sdk)
    local directory = path.join(sdk, "System", "Library", "Frameworks", "VideoToolbox.framework", "Headers")
    local out = {}
    for _, file in ipairs(lib.files_matching(directory, "*.h")) do
        out[#out + 1] = { file = file, text = lib.read_text(file) }
    end
    return out
end

-- (release, file, line) for one constant, or nil when no header declares it.
local function constant_availability(sdk, name)
    for _, header in ipairs(header_texts(sdk)) do
        local lines = lib.split_text(header.text, "\n")
        for index, line in ipairs(lines) do
            if declared_name(line) == name then
                local release, lineNo = release_near(lines, index)
                return release, path.filename(header.file), lineNo
            end
        end
    end
    return nil
end

-- {name = {release, file, line}} for every constant the headers declare; release is nil where the header states none.
local function all_constants(sdk)
    local out = {}
    for _, header in ipairs(header_texts(sdk)) do
        local lines = lib.split_text(header.text, "\n")
        for index, line in ipairs(lines) do
            local name = declared_name(line)
            if name then
                local release = release_near(lines, index)
                out[name] = { release, path.filename(header.file), index }
            end
        end
    end
    return out
end

-- The two shapes, written out as text so the check does not need an SDK to have them, and a DECOY that looks like a
-- declaration and states nothing, so a reader that invents a release fails.
local SAMPLES = {
    {
        label = "own line",
        text = "VT_EXPORT const CFStringRef kVTAlphaChannelMode_PremultipliedAlpha\t"
            .. "API_AVAILABLE(macos(10.10), ios(2.0), tvos(9.0))",
        name = "kVTAlphaChannelMode_PremultipliedAlpha",
        wanted = "2.0",
    },
    {
        label = "line below",
        text = "VT_EXPORT const CFStringRef kVTCompressionPropertyKey_PreserveDynamicHDRMetadata // CFBoolean, Wr...\n"
            .. "\t\t\t\t\t\t\tAPI_AVAILABLE(macos(11.0), ios(14.0), tvos(14.0))",
        name = "kVTCompressionPropertyKey_PreserveDynamicHDRMetadata",
        wanted = "14.0",
    },
    {
        label = "line above",
        text = "API_AVAILABLE(macos(15.4), ios(26.0), tvos(26.0), visionos(26.0)) API_UNAVAILABLE(watchos)\n"
            .. "VT_EXPORT const CFStringRef kVTFrameRateConversionQualityPrioritizationNormal",
        name = "kVTFrameRateConversionQualityPrioritizationNormal",
        wanted = "26.0",
    },
}
local DECOY = {
    text = "VT_EXPORT const CFStringRef kVTCharonDecoyNameThatIsNotInAnyHeader\t",
    name = "kVTCharonDecoyNameThatIsNotInAnyHeader",
}

-- The reader the test calls: the release the text states for NAME, which is the production reader's own.
local function read_line_shape(text, name)
    local lines = lib.split_text(text, "\n")
    for index, line in ipairs(lines) do
        if declared_name(line) == name then
            return (release_near(lines, index))
        end
    end
    return nil
end

function main(...)
    local sdk = (...) or os.getenv("VT_SDK") or ""
    local bad = {}
    for _, sample in ipairs(SAMPLES) do
        local got = read_line_shape(sample.text, sample.name)
        if got == nil then
            bad[#bad + 1] = sample.label .. " shape: read nothing, so the fallback was never reached"
        end
        if got ~= sample.wanted then
            local shown = got == nil and "None" or lib.py_repr(got)
            bad[#bad + 1] = string.format("%s shape: read %s, wanted %s", sample.label, shown, lib.py_repr(sample.wanted))
        else
            print(string.format("  %-10s shape read: %s", sample.label, got))
        end
    end
    local decoy = read_line_shape(DECOY.text, DECOY.name)
    if decoy ~= nil then
        bad[#bad + 1] = "the decoy read " .. lib.py_repr(decoy)
            .. "; a reader that invents a release is the failure this is for"
    else
        print("  decoy      read: None, and it invents nothing")
    end

    if sdk ~= "" then
        local total, stated = 0, 0
        for _, entry in pairs(all_constants(sdk)) do
            total = total + 1
            if entry[1] then
                stated = stated + 1
            end
        end
        print(string.format("  %d constants declared by the headers; %d state a release", total, stated))
    end
    for _, line in ipairs(bad) do
        print("FAIL " .. line)
    end
    if #bad > 0 then
        os.exit(1)
    end
    print("constant availability: both shapes read, and the decoy invents nothing")
end
