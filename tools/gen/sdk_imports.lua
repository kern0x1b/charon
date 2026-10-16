-- The modules a module's headers reach, read the way the compiler reads them for the SDK's own target. The module's own headers (a
-- framework's Headers/ folder, or a usr/include module's folder or header) are included, one after another, in one translation unit that
-- is only preprocessed (clang -E -M, the compiler's own #if evaluation: a macOS-only import under an #if is not reached). Each header the
-- preprocessor reaches is owned by the module it sits in: a framework (a nested one, Outer/Inner, is inside its outer one's Frameworks/
-- folder) or a usr/include module (its folder, or its header in usr/include). closure() is the module first, then each module that owns a
-- header it reaches, in the order the preprocessor reaches them. Nothing is named in this file: the modules and their headers are the
-- SDK's own folders, and the target is the SDK's own version (the extractor's target, decls --target).

local sdk_info = import("sdk", {anonymous = true})

local CLANG = "/usr/bin/clang"

-- (sdk, name) -> the closure (the module first), read once per run.
local closure_memo = {}

-- The segments of a path below the SDK, as a list.
local function segments_of(path_text)
    local out = {}
    for segment in string.gmatch(path_text, "[^/]+") do
        table.insert(out, segment)
    end
    return out
end

-- The folder a framework is in: System/Library/Frameworks or SubFrameworks, nested ones (Outer/Inner) under their outer one's Frameworks/.
local function framework_folder(sdk, library, name)
    local base = path.join(sdk, "System", "Library", library)
    local names = segments_of(name)
    for i, segment in ipairs(names) do
        base = path.join(base, segment .. ".framework")
        if i < #names then
            base = path.join(base, "Frameworks")
        end
    end
    return base
end

-- The headers of one folder a module is entered through: its umbrella header (the one named as the module), when the folder has it, else
-- every header of the folder (the module's headers are then read one by one, as decls reads a module with no umbrella).
local function entry_headers(folder, name)
    local last = string.match(name, "([^/]+)$")
    local umbrella = path.join(folder, last .. ".h")
    if os.isfile(umbrella) then
        return {umbrella}
    end
    return os.files(path.join(folder, "**.h"))
end

-- The headers a module's translation unit includes: its entry headers in each of its framework folders (Headers/), or in its usr/include
-- folder, or its own header in usr/include. Nil when the SDK holds no such module.
local function own_headers(sdk, name)
    local out = {}
    for _, library in ipairs({"Frameworks", "SubFrameworks"}) do
        local headers = path.join(framework_folder(sdk, library, name), "Headers")
        if os.isdir(headers) then
            for _, file in ipairs(entry_headers(headers, name)) do
                table.insert(out, file)
            end
        end
    end
    local include = path.join(sdk, "usr", "include", name)
    if os.isdir(include) then
        for _, file in ipairs(entry_headers(include, name)) do
            table.insert(out, file)
        end
    elseif os.isfile(include .. ".h") then
        table.insert(out, include .. ".h")
    end
    table.sort(out)
    return #out > 0 and out or nil
end

-- The module that owns a header the preprocessor reached: the framework (nested ones as Outer/Inner) whose folder holds it, or the
-- usr/include module whose folder or header it is. Nil for a file outside the SDK's modules.
local function owner_of(sdk, file)
    local prefix = sdk .. "/"
    if string.sub(file, 1, #prefix) ~= prefix then
        return nil
    end
    local seg = segments_of(string.sub(file, #prefix + 1))
    if seg[1] == "System" and seg[2] == "Library" and (seg[3] == "Frameworks" or seg[3] == "SubFrameworks") then
        local names = {}
        local i = 4
        while seg[i] ~= nil and string.sub(seg[i], -10) == ".framework" do
            table.insert(names, string.sub(seg[i], 1, -11))
            if seg[i + 1] == "Frameworks" and seg[i + 2] ~= nil and string.sub(seg[i + 2], -10) == ".framework" then
                i = i + 2
            else
                break
            end
        end
        return #names > 0 and table.concat(names, "/") or nil
    end
    if seg[1] == "usr" and seg[2] == "include" and seg[3] ~= nil then
        if seg[4] ~= nil then
            return seg[3]
        end
        return string.match(seg[3], "^(.-)%.h$")
    end
    return nil
end

-- The headers a module's translation unit reaches, as clang -E -M lists them (the target line dropped). The unit includes each of the
-- module's own headers with -include, over an empty input: the compiler reads the same headers the extractor reads, for the SDK's target.
local function reached_files(sdk, name, headers)
    local target = "arm64-apple-ios" .. sdk_info.discover(sdk).version
    local argv = {"-E", "-M", "-x", "objective-c", "-target", target, "-isysroot", sdk,
                  "-F", path.join(sdk, "System", "Library", "Frameworks"),
                  "-F", path.join(sdk, "System", "Library", "SubFrameworks"),
                  "-I", path.join(sdk, "usr", "include")}
    for _, header in ipairs(headers) do
        table.insert(argv, "-include")
        table.insert(argv, header)
    end
    table.insert(argv, "/dev/null")
    local out, failure = nil, nil
    try {
        function()
            out = os.iorunv(CLANG, argv)
        end,
        catch {
            function(e)
                failure = e
            end
        }
    }
    assert(failure == nil, string.format("sdk_imports: clang could not preprocess %s: %s", name, tostring(failure)))
    local deps = string.gsub(out, "\\\n", " ")
    local list = {}
    for item in string.gmatch(string.sub(deps, (string.find(deps, ":", 1, true) or 0) + 1), "%S+") do
        table.insert(list, item)
    end
    return list
end

-- The modules a module reaches through its headers, the module first, then each module that owns a header the preprocessor reaches (the
-- order they are reached in, each once). A module the SDK does not hold has the closure of itself alone.
function closure(sdk, name)
    local key = sdk .. "\t" .. name
    if closure_memo[key] ~= nil then
        return closure_memo[key]
    end
    local reached, seen = {name}, {[name] = true}
    local headers = own_headers(sdk, name)
    if headers ~= nil then
        for _, file in ipairs(reached_files(sdk, name, headers)) do
            local owner = owner_of(sdk, file)
            if owner ~= nil and not seen[owner] then
                seen[owner] = true
                table.insert(reached, owner)
            end
        end
    end
    closure_memo[key] = reached
    return reached
end
