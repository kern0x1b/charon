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

local FRAMEWORKS = {"Foundation", "UIKit", "CoreLocation", "CoreGraphics", "CoreFoundation", "CoreData", "UserNotifications"}

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


-- A type the headers alone declare - an enumeration, a set of options, a structure - has no entry in the registry: the
-- backports carry nothing of it. It comes down when every API of the SDK that uses it and is above the port's release is
-- implemented, to the latest minimum among those; one that is not, or a use that cannot be told, keeps it where it is.
local function type_marks(node)
    local found = marks(node)
    for _, child in ipairs(node.inner or {}) do
        if child.kind == "EnumConstantDecl" or child.kind == "FieldDecl" then
            table.join2(found, marks(child))
        end
    end
    return found
end

local function header_files(sdk)
    local files = {}
    for _, framework in ipairs(FRAMEWORKS) do
        table.join2(files, os.files(path.join(sdk, "System", "Library", "Frameworks", framework .. ".framework", "Headers", "*.h")))
    end
    return files
end

-- The byte offsets where each line of a text starts.
local function line_starts(text)
    local starts, position = {1}, 1
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        position = position + #line + 1
        table.insert(starts, position)
    end
    return starts
end

-- The declaration among nodes whose source covers bytes [low, high) of text and names the type: by offset, which clang
-- always writes, where the file and line it leaves out when they repeat.
local function covering(nodes, text, low, high, name)
    for _, node in ipairs(nodes) do
        local range = node.range or {}
        local first = range.begin and (range.begin.expansionLoc or range.begin) or {}
        local last = range["end"] and (range["end"].expansionLoc or range["end"]) or {}
        if first.offset and last.offset then
            local from, to = first.offset + 1, last.offset + (last.tokLen or 0)
            if from < high and to >= low and text:sub(from, to + 1):find("%f[%w_]" .. name .. "%f[^%w_]") then
                return node
            end
        end
    end
end

-- The declaration of a member the SDK gives only as a requirement of a protocol, as a category would repeat it for a class:
-- the protocol's own type, and for a method its selector's parts paired in order with its parameters, from the AST node.
function protocol_member_declaration(member, name, target)
    -- API_AVAILABLE(...) may nest parens (ios(8.0)), so the balanced match %b() is stripped, not [^)]*
    local function typed(field)
        return ((field or {}).qualType or "void"):gsub("^API_AVAILABLE%b()%s*", "")
    end
    if member.kind == "ObjCPropertyDecl" then
        return string.format("@property (nonatomic, readonly) %s %s API_AVAILABLE(ios(%s));", typed(member.type), name, target)
    end
    local parameters, parts = {}, {}
    for _, child in ipairs(member.inner or {}) do
        if child.kind == "ParmVarDecl" then
            table.insert(parameters, child)
        end
    end
    local index = 1
    for part in (name .. ""):gmatch("[^:]*:?") do
        if part ~= "" then
            local parameter = parameters[index]
            if parameter then
                table.insert(parts, string.format("%s:(%s)%s", part:sub(1, -2), typed(parameter.type), parameter.name or "value"))
                index = index + 1
            else
                table.insert(parts, part)
            end
        end
    end
    return string.format("- (%s)%s API_AVAILABLE(ios(%s));", typed(member.returnType), table.concat(parts, " "), target)
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

    -- The types the headers alone declare that implemented API names in its signature.
    local named = {}
    for _, entry in ipairs(entries) do
        for _, node in ipairs(dump(filter_of(entry))) do
            if matches(entry, node) then
                local signature = {(node.type or {}).qualType or ""}
                for _, child in ipairs(node.inner or {}) do
                    if child.kind == "ParmVarDecl" then
                        table.insert(signature, (child.type or {}).qualType or "")
                    end
                end
                for word in table.concat(signature, " "):gmatch("%f[%w_]([NUC][SIG][%w_]+)") do
                    named[word] = true
                end
            end
        end
    end
    local lowered_types, kept_types = {}, {}
    local headers = header_files(opt.sdk)
    local names = table.keys(named)
    table.sort(names)
    for _, name in ipairs(names) do
        local declared = {}
        for _, node in ipairs(dump(name)) do
            if (node.kind == "TypedefDecl" or node.kind == "EnumDecl" or node.kind == "RecordDecl") and node.name == name then
                table.insert(declared, node)
            end
        end
        local above = false
        for _, node in ipairs(declared) do
            for _, mark in ipairs(type_marks(node)) do
                above = above or later(mark.introduced, opt.minimum)
            end
        end
        if above then
            local blocking, target = {}, opt.minimum
            for _, file in ipairs(headers) do
                local text = io.readfile(file)
                if text:find("%f[%w_]" .. name .. "%f[^%w_]") then
                    local starts, lines = line_starts(text), text:split("\n", {strict = true})
                    for index, line in ipairs(lines) do
                        local trimmed = line:trim()
                        if line:find("%f[%w_]" .. name .. "%f[^%w_]") and not trimmed:startswith("//") and not trimmed:startswith("*")
                           and not trimmed:startswith("/*") and not trimmed:startswith("#") then
                            local low, high = starts[index], starts[index + 1]
                            local own = covering(declared, text, low, high, name)
                            if not own then
                                -- the class or protocol the line is inside, read back to its @interface or @protocol
                                local owner
                                for back = index, 1, -1 do
                                    local kind, found = lines[back]:match("^%s*@(%a+)%s+([%w_]+)")
                                    if kind == "interface" or kind == "protocol" then
                                        owner = found
                                        break
                                    elseif lines[back]:match("^%s*@end") then
                                        break
                                    end
                                end
                                local user, api
                                if owner then
                                    user = covering(dump(owner .. "::"), text, low, high, name)
                                    if user and user.kind == "ObjCMethodDecl" then
                                        api = string.format("%s[%s %s]", user.instance == false and "+" or "-", owner, user.name)
                                    elseif user and user.kind == "ObjCPropertyDecl" then
                                        api = owner .. "." .. user.name
                                    end
                                else
                                    for word in line:gmatch("([%a_][%w_]*)") do
                                        if not user and word ~= name then
                                            for _, node in ipairs(dump(word)) do
                                                if (node.kind == "FunctionDecl" or node.kind == "VarDecl") and node.name == word
                                                   and covering({node}, text, low, high, name) then
                                                    user, api = node, word
                                                end
                                            end
                                        end
                                    end
                                end
                                local release
                                for _, mark in ipairs(user and marks(user) or {}) do
                                    release = (not release or later(mark.introduced, release)) and mark.introduced or release
                                end
                                if not user then
                                    table.insert(blocking, string.format("%s:%d", path.filename(file), index))
                                elseif release and later(release, opt.minimum) then
                                    local spellings = {api, api .. "()"}
                                    local class, property = api:match("^([%w_]+)%.([%w_]+)$")
                                    if class then
                                        table.join2(spellings, {string.format("-[%s %s]", class, property),
                                                                string.format("-[%s set%s%s:]", class, property:sub(1, 1):upper(), property:sub(2))})
                                    end
                                    local implemented, told = true, false
                                    for _, spelling in ipairs(spellings) do
                                        if listed[spelling] then
                                            told = true
                                            implemented = implemented and listed[spelling].status == "implemented"
                                            if listed[spelling].minimum and later(listed[spelling].minimum, target) then
                                                target = listed[spelling].minimum
                                            end
                                        end
                                    end
                                    if not told then
                                        local whole = owner and listed[owner]
                                        implemented = whole and whole.kind == "class" and whole.status == "implemented" or false
                                    end
                                    if not implemented then
                                        table.insert(blocking, api)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if #blocking == 0 then
                lowered_types[name] = target
                for _, node in ipairs(declared) do
                    for _, mark in ipairs(type_marks(node)) do
                        place(mark, target)
                    end
                end
            else
                table.sort(blocking)
                kept_types[name] = blocking
            end
        end
    end

    -- A member the SDK declares only as a requirement of a protocol, never on the class itself: lowering the protocol
    -- would reach every type that conforms to it, including ones with no backport (checked and rejected: see the README
    -- and 7-10's answer). Instead, for exactly the registry's entries that name a class and a member of this protocol,
    -- the member is redeclared as a category on that class, appended to the class's own header - which a Swift port
    -- reads whichever branch of the header's own `#if` it takes, because the category comes after both. The signature
    -- is the protocol's own, read from its AST, so this does not guess one.
    local PROTOCOL_ONLY = {{protocol = "UITraitEnvironment", members = {"traitCollection", "traitCollectionDidChange:"},
                            owners = {"UIView", "UIScreen", "UIViewController"}}}
    local redeclared = {}
    for _, rule in ipairs(PROTOCOL_ONLY) do
        local requirements = {}
        for _, node in ipairs(dump(rule.protocol)) do
            if node.kind == "ObjCProtocolDecl" and node.name == rule.protocol then
                for _, member in ipairs(node.inner or {}) do
                    if member.kind == "ObjCMethodDecl" or member.kind == "ObjCPropertyDecl" then
                        for _, name in ipairs(rule.members) do
                                    if member.name == name and (member.kind == "ObjCPropertyDecl" or not requirements[name]) then
                                requirements[name] = member
                            end
                        end
                    end
                end
            end
        end
        for _, owner in ipairs(rule.owners) do
            local declaration, target = {}, opt.minimum
            for _, name in ipairs(rule.members) do
                local api = string.format("-[%s %s]", owner, name)
                local entry = listed[api]
                local member = requirements[name]
                if entry and entry.status == "implemented" and member then
                    if entry.minimum and later(entry.minimum, target) then
                        target = entry.minimum
                    end
                    table.insert(declaration, protocol_member_declaration(member, name, target))
                end
            end
            if #declaration == #rule.members then
                -- dump(owner) answers one entry per file that names the class, most a forward declaration
                -- (@class UIView;); the class's own header is the one whose entry carries its members.
                local file
                for _, node in ipairs(dump(owner)) do
                    if node.kind == "ObjCInterfaceDecl" and node.name == owner then
                        for _, member in ipairs(node.inner or {}) do
                            if member.kind == "ObjCMethodDecl" or member.kind == "ObjCPropertyDecl" or member.kind == "ObjCIvarDecl" then
                                file = (node.loc or {}).file
                                break
                            end
                        end
                    end
                end
                if file then
                    redeclared[file] = redeclared[file] or {}
                    table.insert(redeclared[file], string.format("\n@interface %s (CharonBackports%s)\n%s\n@end\n",
                                 owner, rule.protocol, table.concat(declaration, "\n")))
                end
            end
        end
    end

    -- The copies: each mark rewritten where its macro was written, the release inside ios(...) or, for the macros that
    -- take the iOS release as a positional argument, that argument.
    local roots, lifted = {}, 0
    for file, categories in pairs(redeclared) do
        edits[file] = edits[file] or {}
    end
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
        local text = table.concat(lines, "\n")
        for _, category in ipairs(redeclared[file] or {}) do
            text = text .. category
        end
        io.writefile(copy, text)
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
    for name, target in pairs(lowered_types) do
        for _, node in ipairs(dump(name, vfs)) do
            if (node.kind == "TypedefDecl" or node.kind == "EnumDecl" or node.kind == "RecordDecl") and node.name == name then
                for _, mark in ipairs(type_marks(node)) do
                    if later(mark.introduced, target) then
                        table.insert(failures, string.format("the type %s still says iOS %s", name, mark.introduced))
                    end
                end
            end
        end
    end
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
    return {vfs = vfs, lifted = lifted, headers = #sorted_files, implemented = #entries, unmatched = unmatched,
            types = lowered_types, kept_types = kept_types}
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
