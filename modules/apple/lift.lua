-- The SDK's headers as a port with the backports sees them: every API the backports registry says is implemented is
-- available from the port's release, and nothing else changes.
--
-- The headers say when an API came, and Swift refuses a call below that release, where C only warns. For what the
-- backports carry that is wrong: the class or method is there on the older release. APINotes cannot say otherwise -
-- an entry's Availability lifts an unavailable mark but keeps the release the header names - so the headers themselves
-- are copied with the release lowered, and a VFS overlay lays the copies over the SDK for the port's compile. The SDK
-- stays as it is.
--
-- What is lowered is found from the AST, not by reading the headers: clang dumps each declaration with the place its
-- availability macro was written, and the release is rewritten there. A class entry lowers the class and the members of
-- its whole surface, but a member with an entry of its own that is not implemented keeps its mark, and so does every
-- member that shares a mark with one (a property, its getter and its setter share the line). A member left out of a
-- superclass is left out of a subclass that declares it again. The result is checked both ways before it is used:
-- every implemented API the SDK declares answers the lowered release, and nothing that is not implemented moved.

import("core.base.json")
import("dyld")
import("backports")

local FRAMEWORKS = {"Foundation", "UIKit", "CoreLocation", "CoreGraphics", "CoreFoundation", "CoreData"}

local function version(text)
    return (text or ""):gsub("_", ".")
end

local function later(a, b)
    return dyld.compare_versions(version(a), version(b)) > 0
end

-- The top-level objects of a JSON dump, which clang writes one after another.
local function objects(text)
    local found, depth, start, quoted, escaped = {}, 0, nil, false, false
    for index = 1, #text do
        local char = text:sub(index, index)
        if quoted then
            if escaped then
                escaped = false
            elseif char == "\\" then
                escaped = true
            elseif char == '"' then
                quoted = false
            end
        elseif char == '"' then
            quoted = true
        elseif char == "{" then
            if depth == 0 then
                start = index
            end
            depth = depth + 1
        elseif char == "}" then
            depth = depth - 1
            if depth == 0 and start then
                table.insert(found, json.decode(text:sub(start, index)))
                start = nil
            end
        end
    end
    return found
end

local function dumper(opt)
    local umbrella = path.join(opt.outputdir, "umbrella.m")
    local lines = {}
    for _, framework in ipairs(FRAMEWORKS) do
        table.insert(lines, string.format("#import <%s/%s.h>", framework, framework))
    end
    io.writefile(umbrella, table.concat(lines, "\n") .. "\n")
    local cache = {}
    return function (filter, vfs)
        local key = filter .. "|" .. (vfs or "")
        if cache[key] then
            return cache[key]
        end
        local arguments = {"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot", "-fsyntax-only",
                           "-x", "objective-c", umbrella, "-Xclang", "-ast-dump-filter=" .. filter}
        if vfs then
            table.join2(arguments, {"-ivfsoverlay", vfs})
        end
        local text = os.iorunv(opt.clang, table.join(arguments, {"-Xclang", "-ast-dump=json"}))
        local found = objects(text)
        -- The JSON names no owner; the text dump of the same filter heads each declaration with its qualified name, in
        -- the same order.
        local headings = {}
        for heading in os.iorunv(opt.clang, table.join(arguments, {"-Xclang", "-ast-dump"})):gmatch("Dumping ([^\n]*):\n") do
            table.insert(headings, heading)
        end
        if #headings == #found then
            for index, node in ipairs(found) do
                node._qualified = headings[index]
            end
        end
        cache[key] = found
        return found
    end
end

-- Where the iOS availability of a node was written, and the release it names.
local function marks(node)
    local found = {}
    for _, child in ipairs(node.inner or {}) do
        if child.kind == "AvailabilityAttr" and child.platform == "ios" and child.introduced then
            local begin = child.range and child.range.begin or {}
            local where = begin.expansionLoc or begin
            if where.file and where.line and where.col then
                table.insert(found, {file = where.file, line = where.line, col = where.col, introduced = child.introduced})
            end
        end
    end
    return found
end

local function member_api(api)
    local sign, owner, selector = api:match("^([-+])%[([%w_]+) (.+)%]$")
    if sign then
        return {sign = sign, owner = owner, selector = selector}
    end
    local class, property = api:match("^([%w_]+)%.([%w_]+)$")
    if class then
        return {owner = class, property = property}
    end
end

local function setter_property(selector)
    local first, rest = selector:match("^set(%a)([%w_]*):$")
    return first and first:lower() .. rest
end

local function filter_of(entry)
    local api = entry.api:gsub("%(%)$", "")
    local member = member_api(api)
    return member and member.owner .. "::" or api
end

local function owner_of(node)
    local qualified = node._qualified or ""
    return qualified:match("^([%w_]+)::")
end

local function matches(entry, node)
    local api = entry.api:gsub("%(%)$", "")
    local member = member_api(api)
    if entry.kind == "class" then
        return (node.kind == "ObjCInterfaceDecl" or node.kind == "ObjCCategoryDecl")
               and (node.name == api or (node.interface and node.interface.name == api))
    end
    if member then
        if (node.kind ~= "ObjCMethodDecl" and node.kind ~= "ObjCPropertyDecl") or owner_of(node) ~= member.owner then
            return false
        end
        if member.selector then
            if node.kind == "ObjCMethodDecl" then
                return node.name == member.selector and (node.instance ~= false) == (member.sign == "-")
            end
            return node.name == (setter_property(member.selector) or member.selector)
        end
        return node.kind == "ObjCPropertyDecl" and node.name == member.property
            or node.kind == "ObjCMethodDecl" and (node.name == member.property or setter_property(node.name) == member.property)
    end
    if entry.kind == "type" then
        return (node.kind == "TypedefDecl" or node.kind == "EnumDecl" or node.kind == "RecordDecl") and node.name == api
    end
    return (node.kind == "VarDecl" or node.kind == "FunctionDecl") and node.name == api
end

-- lift(opt): opt.clang, opt.sdk, opt.triple, opt.minimum, opt.registry (the folder holding registry/), opt.outputdir.
-- Answers the VFS overlay to hand the compiler and what was done; raises when either check finds a difference.
function lift(opt)
    os.tryrm(opt.outputdir)
    os.mkdir(opt.outputdir)
    local dump = dumper(opt)
    local listed, incomplete = backports.registry(opt.registry)
    if #incomplete > 0 then
        raise("the backports registry is incomplete: %s", table.concat(incomplete, "; "))
    end
    local kept, entries = {}, {}
    for api, entry in pairs(listed) do
        if entry.status == "implemented" then
            table.insert(entries, entry)
        else
            kept[api] = true
        end
    end
    table.sort(entries, function (a, b) return a.api < b.api end)

    local supers = {}
    local function superclasses(name)
        local chain, seen = {}, {}
        while name and not seen[name] do
            seen[name] = true
            if supers[name] == nil then
                supers[name] = false
                for _, node in ipairs(dump(name)) do
                    if node.kind == "ObjCInterfaceDecl" and node.name == name and node.super then
                        supers[name] = node.super.name
                    end
                end
            end
            name = supers[name] or nil
            if name then
                table.insert(chain, name)
            end
        end
        return chain
    end

    local edits, blocked, targets, unmatched = {}, {}, {}, {}
    local function place(mark, target)
        if later(mark.introduced, target) and mark.file:startswith(opt.sdk) then
            edits[mark.file] = edits[mark.file] or {}
            edits[mark.file][mark.line .. ":" .. mark.col] = {line = mark.line, col = mark.col, target = target}
        end
    end
    for _, entry in ipairs(entries) do
        local target = opt.minimum
        if entry.minimum and later(entry.minimum, target) then
            target = entry.minimum
        end
        local found = {}
        for _, node in ipairs(dump(filter_of(entry))) do
            if matches(entry, node) then
                table.insert(found, node)
            end
        end
        if #found == 0 then
            table.insert(unmatched, entry.api)
        else
            targets[entry.api] = target
        end
        for _, node in ipairs(found) do
            for _, mark in ipairs(marks(node)) do
                place(mark, target)
            end
            if entry.kind == "type" then
                -- a type from the header alone: the type and every value it names
                for _, child in ipairs(node.inner or {}) do
                    if child.kind == "EnumConstantDecl" or child.kind == "FieldDecl" then
                        for _, mark in ipairs(marks(child)) do
                            place(mark, target)
                        end
                    end
                end
            end
            if entry.kind == "class" then
                local owners = table.join({entry.api}, superclasses(entry.api))
                for _, child in ipairs(node.inner or {}) do
                    if child.kind == "ObjCMethodDecl" or child.kind == "ObjCPropertyDecl" then
                        local names = {child.name, setter_property(child.name or "")}
                        local left = false
                        for _, owner in ipairs(owners) do
                            for _, name in ipairs(names) do
                                if kept[owner .. "." .. name] or kept[string.format("%s[%s %s]", child.instance == false and "+" or "-", owner, child.name)] then
                                    left = true
                                end
                            end
                        end
                        for _, mark in ipairs(marks(child)) do
                            if left then
                                blocked[mark.file .. ":" .. mark.line .. ":" .. mark.col] = true
                            else
                                place(mark, target)
                            end
                        end
                    end
                end
            end
        end
    end

    -- The copies: each mark rewritten where its macro was written, the release inside ios(...) or, for the macros that
    -- take the iOS release as a positional argument, that argument.
    local roots, lifted = {}, 0
    local sorted_files = table.keys(edits)
    table.sort(sorted_files)
    for _, file in ipairs(sorted_files) do
        local lines = io.readfile(file):split("\n", {strict = true})
        for _, edit in pairs(edits[file]) do
            if not blocked[file .. ":" .. edit.line .. ":" .. edit.col] then
                local text = lines[edit.line]
                local head, tail = text:sub(1, edit.col - 1), text:sub(edit.col)
                local rewritten = lift_macro(tail, edit.target)
                if rewritten ~= tail then
                    lines[edit.line] = head .. rewritten
                    lifted = lifted + 1
                end
            end
        end
        local copy = path.join(opt.outputdir, "headers", path.relative(file, opt.sdk))
        io.writefile(copy, table.concat(lines, "\n"))
        local folder = path.directory(file)
        roots[folder] = roots[folder] or {}
        table.insert(roots[folder], {type = "file", name = path.filename(file), ["external-contents"] = copy})
    end
    local overlay = {version = 0, ["case-sensitive"] = "false", roots = {}}
    local folders = table.keys(roots)
    table.sort(folders)
    for _, folder in ipairs(folders) do
        table.insert(overlay.roots, {type = "directory", name = folder, contents = roots[folder]})
    end
    local vfs = path.join(opt.outputdir, "vfs.yaml")
    json.savefile(vfs, overlay)

    -- Both ways: what is implemented answers the lowered release, and nothing else moved.
    local failures = {}
    for _, entry in ipairs(entries) do
        if targets[entry.api] then
            for _, node in ipairs(dump(filter_of(entry), vfs)) do
                if matches(entry, node) then
                    for _, mark in ipairs(marks(node)) do
                        if later(mark.introduced, targets[entry.api]) then
                            table.insert(failures, string.format("%s still says iOS %s", entry.api, mark.introduced))
                        end
                    end
                end
            end
        end
    end
    for api in pairs(kept) do
        local entry = listed[api]
        local before, after
        for _, node in ipairs(dump(filter_of(entry))) do
            if matches(entry, node) then
                for _, mark in ipairs(marks(node)) do
                    before = (not before or later(before, mark.introduced)) and mark.introduced or before
                end
            end
        end
        for _, node in ipairs(dump(filter_of(entry), vfs)) do
            if matches(entry, node) then
                for _, mark in ipairs(marks(node)) do
                    after = (not after or later(after, mark.introduced)) and mark.introduced or after
                end
            end
        end
        if before and after and later(before, after) then
            table.insert(failures, string.format("%s is %s and was lowered from iOS %s to %s", api, entry.status, before, after))
        end
    end
    if #failures > 0 then
        table.sort(failures)
        raise("the lifted headers are wrong: %s", table.concat(failures, "; "))
    end
    table.sort(unmatched)
    return {vfs = vfs, lifted = lifted, headers = #sorted_files, implemented = #entries, unmatched = unmatched}
end

-- The release of the availability macro that starts text rewritten to target.
function lift_macro(text, target)
    local name, open = text:match("^([%w_]+)%s*()%(")
    if not name then
        return text
    end
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
        return text
    end
    local call, rest = text:sub(1, finish), text:sub(finish + 1)
    local dotted = version(target)
    local underscored = dotted:gsub("%.", "_")
    if call:find("%f[%w]ios%s*%(") then
        call = call:gsub("(%f[%w]ios%s*%(%s*)[%d%.]+", "%1" .. dotted, 1)
    elseif name == "NS_AVAILABLE" or name == "NS_CLASS_AVAILABLE" or name == "NS_ENUM_AVAILABLE" or name == "CF_AVAILABLE"
           or name == "NS_DEPRECATED" then
        call = call:gsub("^([%w_]+%s*%(%s*[^,]+,%s*)[%d_]+", "%1" .. underscored, 1)
    elseif name:find("IOS") then
        call = call:gsub("^([%w_]+%s*%(%s*)([%d_%.]+)", function (head, release)
            return head .. (release:find("_") and underscored or dotted)
        end, 1)
    end
    return call .. rest
end
