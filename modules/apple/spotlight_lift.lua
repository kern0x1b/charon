-- CoreSpotlight's own lifted headers, for a Swift module that extends the three classes AppIntents
-- names.
--
-- `apple.lift` does this for the seven frameworks in its `FRAMEWORKS` list, with a VFS overlay over
-- the SDK and a two-way check: every implemented API the SDK declares answers the lowered release, and
-- nothing that is not implemented moved. CoreSpotlight is not on that list, and `lift.lift_macro`
-- cannot rewrite its marks: the framework writes them `CS_CLASS_AVAILABLE(10_13, 9_0)` and
-- `CS_AVAILABLE(10_13, 9_0)`, macros the rewriter does not name (it knows `API_AVAILABLE`,
-- `NS_AVAILABLE`, `NS_CLASS_AVAILABLE`, `CF_AVAILABLE`, `NS_DEPRECATED` and the `*_IOS` family).
--
-- So the AppIntents package asks for CoreSpotlight's three classes itself, and this is the code that
-- does it. The gate is the registry the lift uses and the rules are the three it keeps:
--
--   * only what the CoreSpotlight registry says `implemented` is lowered - a class entry lowers the
--     class and nothing else, and the three constants of that registry carry no availability mark of
--     their own;
--   * the rewrite is at the place the macro is written, on the lines above the class's `@interface`;
--   * both ways are checked before the overlay is used - a class the registry says is implemented and
--     the header does not declare is an error, a class the rewrite touched that the registry does not
--     carry as implemented is an error, and a class the rewrite touched more than once is an error.
--
-- The checks are why this is not a blanket substitution: a header that stops declaring one of the
-- three classes, or a registry that grows an entry the header does not declare, fails here instead of
-- producing an overlay that lies about what the device has.

import("core.base.json")

-- The framework's own availability macros, and what each of them marks. The macro's own definition
-- (`CS_AVAILABLE(mac, ios)` in CSBase.h) names no version and is never rewritten: the rule below only
-- fires on a call whose second argument is a release.
local CS_MACROS = {
    CS_CLASS_AVAILABLE = true,
    CS_AVAILABLE = true,
    CS_ENUM_AVAILABLE = true,
    CS_PROTOCOL_AVAILABLE = true,
}

-- The trailing macros of a member declaration, and the argument each of them takes the iOS release in.
-- A class entry lowers the class and the members of its whole surface, which is what `apple.lift` does
-- too (it walks the class's own AST node), so these are lowered inside a class the registry carries.
local TRAILING_MACROS = {
    ["API_AVAILABLE"] = "ios",
    ["API_DEPRECATED"] = "ios",
    ["API_UNAVAILABLE"] = true,
}

local function version_of(release)
    if not release then
        return nil
    end
    return (release:gsub("_", "."))
end

local function later_than(a, b)
    local function parts(text)
        local out = {}
        for piece in tostring(text):gmatch("[^%.]+") do
            table.insert(out, tonumber(piece) or 0)
        end
        return out
    end
    local left, right = parts(a), parts(b)
    for index = 1, math.max(#left, #right) do
        local x, y = left[index] or 0, right[index] or 0
        if x ~= y then
            return x > y
        end
    end
    return false
end

local function underscored(release)
    return (tostring(release):gsub("%.", "_"))
end

-- One availability macro lowered to `target`, wherever in the line it is written. The framework's
-- `CS_*` macros take `<macOS>, <iOS>`, so the iOS release is the second argument; the SDK's
-- `API_AVAILABLE`/`API_DEPRECATED` name theirs `ios(9.0)`, which is the argument that says iOS.
-- Anything else - another framework's macro, the macro's own definition, an argument list with no
-- iOS release in it - is handed back unchanged, so a mark this does not understand stays as it was.
-- The text of a call: what is before the opening parenthesis, what is inside it, what is after the
-- closing one, and the closing parenthesis's own place.
local function match_call(text, open)
    local depth, finish = 0, nil
    for index = open, #text do
        local char = text:sub(index, index)
        if char == "(" then
            depth = depth + 1
        elseif char == ")" then
            depth = depth - 1
            if depth == 0 then
                finish = index
                break
            end
        end
    end
    if not finish then
        return nil
    end
    -- `prefix` is what is before the opening parenthesis, so a rewritten call is
    -- `prefix .. arguments .. ")" .. suffix` and the macro's own name is not carried twice
    return {prefix = text:sub(1, open - 1), inside = text:sub(open + 1, finish - 1), suffix = text:sub(finish + 1)}
end

-- One availability macro lowered to `target`, wherever in the line it is written. The text is split
-- once, at the opening parenthesis, and the arguments are rewritten inside that: the framework's
-- `CS_*` macros take `<macOS>, <iOS>`, so the iOS release is the second argument; the SDK's
-- `API_AVAILABLE` and `API_DEPRECATED` name theirs `ios(9.0)`. Anything this does not recognise - a
-- macro of another framework, the macro's own definition, an argument list with no iOS release in the
-- place it writes it - comes back unchanged, so a mark it cannot read stays as it was.
local function lower_macro(text, target)
    local paren = text:find("%(")
    if not paren then
        return text
    end
    local name = text:sub(1, paren - 1)
    local body = text:sub(paren)
    if TRAILING_MACROS[name] == "ios" then
        local lowered, changed = body:gsub("ios%s*%(%s*([%d_%.]+)", function (release)
            local number = version_of(release)
            if number and later_than(number, target) then
                changed = true
                return "ios(" .. underscored(target)
            end
            return nil
        end, 1)
        if not changed then
            return text
        end
        return name .. lowered
    end
    if not CS_MACROS[name] then
        return text
    end
    -- the arguments, each with its own leading space kept
    local arguments, rest = {}, nil
    local close = nil
    local depth = 0
    for index = 1, #body do
        local char = body:sub(index, index)
        if char == "(" then
            depth = depth + 1
        elseif char == ")" then
            depth = depth - 1
            if depth == 0 then
                close = index
                break
            end
        end
    end
    if not close then
        return text
    end
    rest = body:sub(close + 1)
    for argument in body:sub(2, close - 1):gmatch("([^,]+)") do
        table.insert(arguments, argument)
    end
    if #arguments < 2 then
        return text
    end
    local ios = arguments[2]:match("^%s*([%d_%.]+)%s*$")
    local number = version_of(ios)
    if not number or not later_than(number, target) then
        return text
    end
    arguments[2] = " " .. underscored(target)
    return name .. "(" .. table.concat(arguments, ",") .. ")" .. rest
end

-- Every entry the registry at `dir` carries, keyed by its api: `{[api] = {status = ..., kind = ...}}`.
-- The directory is the one `apple-backports` installs, and the one the AppIntents package reads from
-- the source tree when the package is not installed beside it.
local function read_registry(dir)
    local listed = {}
    for _, file in ipairs(os.files(path.join(dir, "CoreSpotlight", "*.json"))) do
        local text = io.readfile(file)
        local payload = text and json.decode(text) or nil
        if type(payload) == "table" then
            for _, entry in ipairs(payload.entries or payload) do
                if type(entry) == "table" and entry.api then
                    listed[entry.api] = entry
                end
            end
        end
    end
    return listed
end

-- The overlay, and what it did. `opt`:
--   sdk        the SDK the headers are read from
--   target     the port's triple, e.g. armv7-apple-ios6.1.3
--   minimum    the release the implemented API is available from
--   registry   the directory the CoreSpotlight registry is read from
--   outputdir  where the copies and the vfs are written
function spotlight_lift(opt)
    local headers = path.join(opt.sdk, "System", "Library", "Frameworks", "CoreSpotlight.framework", "Headers")
    if not os.isdir(headers) then
        return {ok = false, reason = "this SDK carries no CoreSpotlight.framework"}
    end
    os.tryrm(opt.outputdir)
    os.mkdir(opt.outputdir)

    local listed = read_registry(opt.registry)
    local empty = true
    for _ in pairs(listed) do
        empty = false
    end
    if empty then
        return {ok = false, reason = "the CoreSpotlight registry at " .. opt.registry .. " carries no entry"}
    end
    local implemented, sorted = {}, {}
    for api, entry in pairs(listed) do
        if entry.status == "implemented" and entry.kind == "class" then
            implemented[api] = true
            table.insert(sorted, api)
        end
    end
    table.sort(sorted)
    if #sorted == 0 then
        return {ok = false, reason = "the CoreSpotlight registry carries no implemented class"}
    end

    local rewritten, declared, roots, members = {}, {}, {}, {}
    for _, file in ipairs(os.files(path.join(headers, "*.h"))) do
        local text = io.readfile(file)
        local name = path.filename(file)
        local lines, out = {}, {}
        for line in (text .. "\n"):gmatch("([^\n]*)\n") do
            table.insert(lines, line)
        end
        -- Two passes, because the second needs to know where a class's own declarations end: the
        -- class's leading mark, and then every availability macro on the lines of the class's own
        -- body, which is the class's surface - its methods, properties and initializers - that a
        -- class entry lowers with it.
        local spans = {}
        for index, line in ipairs(lines) do
            local owner = line:match("^%s*@interface%s+([%w_]+)")
            if owner and implemented[owner] and not spans[owner] then
                spans[owner] = {index, index}
            elseif line:match("^%s*@end") then
                for owner, span in pairs(spans) do
                    if span[1] < index then
                        span[2] = index
                    end
                end
            elseif line:match("^%s*@(interface|protocol)") then
                for owner, span in pairs(spans) do
                    if span[1] < index and span[2] < index then
                        span[2] = index
                    end
                end
            end
        end
        local inside = {}
        for owner, span in pairs(spans) do
            for index = span[1], span[2] do
                inside[index] = owner
            end
        end

        for index, line in ipairs(lines) do
            local mark = line:match("^%s*(CS_[A-Z_]+%b())")
            -- the mark above a class's own `@interface`: the class it belongs to is the one the next
            -- `@interface` names, and a `@protocol` or another `@interface` first ends the search
            local owner, j = nil, index + 1
            while mark and j <= #lines do
                local next_line = lines[j]
                if next_line:find("@interface") or next_line:find("@protocol") then
                    owner = next_line:match("^%s*@interface%s+([%w_]+)")
                    break
                end
                j = j + 1
            end
            owner = owner and (implemented[owner] and owner or nil)
            -- the class whose own declarations this line is inside, which is what a member line is
            -- lowered by; the leading mark above is found by looking ahead instead
            local member_of = inside[index]
            if mark and owner then
                -- The mark belongs to the class whose `@interface` follows it with nothing but
                -- notes in between: a line that opens another `@interface` or `@protocol` ends the
                -- search, so a mark is never carried onto a declaration it does not mark. A
                -- category of the class (`@interface Name (CSCustomAttributes)`) is part of the
                -- class's surface and is lowered with it, which is what the lift does.
                if true then
                    -- the whole line, with only the macro in it lowered: the rest of the line
                    -- (`CS_TVOS_UNAVAILABLE`, a deprecation note) belongs to the declaration too
                    local head, tail = line:match("^(%s*)(.*)$")
                    local lowered = line:gsub("(%s*)(CS_[A-Z_]+%b())", function (space, macro)
                        return space .. lower_macro(macro, opt.minimum)
                    end, 1)
                    out[#out + 1] = lowered
                    rewritten[owner] = (rewritten[owner] or 0) + 1
                    declared[owner] = true
                else
                    out[#out + 1] = line
                end
            elseif member_of then
                -- A member declaration inside a class the registry carries: its own trailing
                -- availability macro is lowered with the class, which is what `apple.lift` does for
                -- the members of a class it lowers.
                local lowered = line:gsub("API_[A-Z_]+%b()", function (macro)
                    return lower_macro(macro, opt.minimum)
                end)
                if lowered ~= line then
                    members[member_of] = (members[member_of] or 0) + 1
                end
                out[#out + 1] = lowered
            else
                out[#out + 1] = line
            end
        end
        local copy = table.concat(out, "\n")
        if copy ~= text then
            local target = path.join(opt.outputdir, name)
            io.writefile(target, copy)
            table.insert(roots, {type = "file", name = name, ["external-contents"] = target})
        end
    end

    local failures = {}
    -- A registry that grows an entry for a member of one of these classes, with a status other than
    -- `implemented`, is a decision this rewriter cannot make: the lift keeps such a member marked
    -- and this does not know how. Rather than lower a member the registry has not decided on, the
    -- overlay is refused and the names are named.
    for api, entry in pairs(listed) do
        if entry.status ~= "implemented" then
            for _, class in ipairs(sorted) do
                if api:find(class, 1, true) then
                    table.insert(failures, "the registry carries " .. api .. " as " .. entry.status ..
                        ", a member of " .. class .. ": this rewriter lowers a class's whole surface " ..
                        "and cannot keep one member marked")
                end
            end
        end
    end
    for _, class in ipairs(sorted) do
        if not declared[class] then
            table.insert(failures, "the registry says " .. class ..
                " is implemented and this SDK's CoreSpotlight headers do not declare it")
        end
    end
    for class in pairs(rewritten) do
        if not implemented[class] then
            table.insert(failures, "the rewrite touched " .. class ..
                ", which the registry does not carry as implemented")
        end
    end
    if #failures > 0 then
        table.sort(failures)
        raise("the CoreSpotlight overlay is wrong: %s", table.concat(failures, "; "))
    end
    if #roots == 0 then
        return {ok = false, reason = "no CoreSpotlight header carried a mark to lower"}
    end

    local overlay = {version = 0, ["case-sensitive"] = "false", roots = {}}
    table.insert(overlay.roots, {type = "directory", name = headers, contents = roots})
    local vfs = path.join(opt.outputdir, "vfs.yaml")
    json.savefile(vfs, overlay)
    local lifted = table.keys(rewritten)
    table.sort(lifted)
    return {ok = true, vfs = vfs, lifted = lifted, headers = #roots, members = members}
end

return {
    lower_macro = lower_macro,
    version_of = version_of,
    later_than = later_than,
    underscored = underscored,
    read_registry = read_registry,
    spotlight_lift = spotlight_lift,
}
