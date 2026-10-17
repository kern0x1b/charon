-- The modules a module's headers reach, read the way the compiler reads them for the SDK's own target. The module's own headers (the list
-- decls reads: sdk_modules.headers_of) are included, one after another, in one translation unit that is only preprocessed (clang -E -M,
-- the compiler's own #if evaluation: a macOS-only import under an #if is not reached). Each header the preprocessor reaches is owned by
-- the module it sits in: a framework (a nested one, Outer/Inner, is inside its outer one's Frameworks/ folder) by its folder, a usr module
-- by the module map that names the header (sdk_modules.usr_owner_of). closure() is the module first, then each module that owns a header
-- it reaches, in the order the preprocessor reaches them. Nothing is named in this file: the modules and their headers come from the SDK,
-- and the target is the SDK's own version (the extractor's target, decls --target).

local sdk_info = import("sdk", {anonymous = true})
local sdk_modules = import("sdk_modules", {anonymous = true})

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

-- The module that owns a header the preprocessor reached: the framework (nested ones as Outer/Inner) whose folder holds it, or the usr
-- module whose map names it. Nil for a file outside the SDK's modules.
local function owner_of(sdk, file)
    local prefix = sdk .. "/"
    if string.sub(file, 1, #prefix) ~= prefix then
        return nil
    end
    local seg = segments_of(string.sub(file, #prefix + 1))
    local frameworks = seg[1] == "System" and seg[2] == "Library" and (seg[3] == "Frameworks" or seg[3] == "SubFrameworks")
    local developer = seg[1] == "Developer" and seg[2] == "Library" and seg[3] == "Frameworks"
    if frameworks or developer then
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
    if seg[1] == "usr" and seg[2] == "include" then
        return sdk_modules.usr_owner_of(sdk, file)
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
                  "-F", path.join(sdk, "Developer", "Library", "Frameworks"),
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
-- order they are reached in, each once). A module with no C header has the closure of itself alone.
function closure(sdk, name)
    local key = sdk .. "\t" .. name
    if closure_memo[key] ~= nil then
        return closure_memo[key]
    end
    local reached, seen = {name}, {[name] = true}
    local headers = sdk_modules.headers_of(sdk, name)
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

-- The umbrella imports of the frameworks a module reaches (closure: each top-level framework among them, the module first), as the
-- "#import" lines a source that names the module's types needs. The module's own import is included only when with_self is set. Nothing
-- is named here: the frameworks are the closure's, read from the SDK.
function umbrella_imports(sdk, name, with_self)
    local out = {}
    for _, module in ipairs(closure(sdk, name)) do
        if with_self or module ~= name then
            local line = sdk_modules.umbrella_import(sdk, module)
            if line then
                table.insert(out, "#import " .. line)
            end
        end
    end
    return out
end
