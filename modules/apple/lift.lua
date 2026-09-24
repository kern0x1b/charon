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
import("compat")

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

-- A framework's headers: its umbrella header where it has one, every header it has where it does not (CoreTelephony,
-- OpenGLES).
local function framework_headers(sdk, framework)
    local folder = path.join(sdk, "System", "Library", "Frameworks", framework .. ".framework", "Headers")
    local umbrella = path.join(folder, framework .. ".h")
    local files = os.isfile(umbrella) and {umbrella} or os.files(path.join(folder, "*.h"))
    table.sort(files)
    return files
end

-- The public headers of the SDK's usr/include that bring in what charon@apple-compat carries: every file that names a
-- symbol followed by a paren outside a directive, as a module map reaches it - the file itself where a module map names
-- it as a header, the umbrella header of its folder where one covers the folder (dispatch/block.h is reached through
-- dispatch/dispatch.h and refuses to be included on its own). Which of them declares the symbol is the dump's to say. A
-- symbol no public header names - a compiler-rt intrinsic - brings none; the dump then finds no declaration of it.
local function system_headers(sdk, symbols)
    local root = path.join(sdk, "usr", "include")
    local public, umbrellas = {}, {}
    for _, map in ipairs(os.files(path.join(root, "**.modulemap"))) do
        local folder = path.directory(map)
        for line in io.readfile(map):gmatch("[^\n]+") do
            local umbrella = line:match('^%s*umbrella%s+header%s+"([^"]+)"')
            local header = line:match('^%s*header%s+"([^"]+)"')
            if umbrella then
                umbrellas[path.relative(folder, root)] = path.relative(path.join(folder, umbrella), root)
            elseif header then
                public[path.relative(path.join(folder, header), root)] = true
            end
        end
    end
    local found = {}
    for _, file in ipairs(os.files(path.join(root, "**.h"))) do
        local text = io.readfile(file)
        for _, symbol in ipairs(symbols) do
            if text:find(symbol, 1, true) then
                for line in text:gmatch("[^\n]+") do
                    if not line:match("^%s*#") and line:find("%f[%w_]" .. symbol .. "%s*%(") then
                        local name = path.relative(file, root)
                        local reached = public[name] and name or umbrellas[path.directory(name)]
                        if reached then
                            found[reached] = true
                        end
                        break
                    end
                end
            end
        end
    end
    return table.orderkeys(found)
end

-- The declarations of a text dump (-ast-dump with -ast-dump-decl-types), in order: the qualified name each is headed with,
-- and every typedef its type goes through.
function listing_sections(listing)
    local starts, sections = {}, {}
    for start, heading in listing:gmatch("()Dumping ([^\n]*):\n") do
        table.insert(starts, {start = start, heading = heading})
    end
    for index, section in ipairs(starts) do
        local body = listing:sub(section.start, starts[index + 1] and starts[index + 1].start - 1 or -1)
        local typedefs = {}
        for name in body:gmatch("%f[%w]Typedef 0x%x+ '([%w_]+)'") do
            table.insert(typedefs, name)
        end
        table.insert(sections, {heading = section.heading, typedefs = typedefs})
    end
    return sections
end

local function dumper(opt, frameworks, headers)
    local umbrella = path.join(opt.outputdir, "umbrella.m")
    local lines = {}
    for _, framework in ipairs(frameworks) do
        for _, header in ipairs(framework_headers(opt.sdk, framework)) do
            table.insert(lines, string.format("#import <%s/%s>", framework, path.filename(header)))
        end
    end
    for _, header in ipairs(headers) do
        table.insert(lines, string.format("#include <%s>", header))
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
        if not text then
            raise("clang gave no dump for the filter %s", filter)
        end
        local found = objects(text)
        -- The JSON names no owner; the text dump of the same filter heads each declaration with its qualified name, in
        -- the same order. With the declaration's type written after it (-ast-dump-decl-types: a function's, a variable's,
        -- a typedef's own), it also names every typedef that type goes through - a return type, a parameter's, and the
        -- typedef a typedef names in turn (dispatch_qos_class_t, then qos_class_t) - which the JSON gives no way to follow.
        local listing = os.iorunv(opt.clang, table.join(arguments, {"-Xclang", "-ast-dump", "-Xclang", "-ast-dump-decl-types"}))
        if not listing then
            raise("clang gave no dump for the filter %s", filter)
        end
        local sections = listing_sections(listing)
        if #sections == #found then
            for index, node in ipairs(found) do
                node._qualified = sections[index].heading
                node._typedefs = sections[index].typedefs
            end
        end
        cache[key] = found
        return found
    end
end

-- What the Swift compiler's clang importer is told beside the headers it reads: the language it reads them in, its
-- definitions (__swift__ among them) and its dialect, as the compiler itself names them (-dump-clang-diagnostics). Its
-- modules, search paths and API notes decide which files are read, which the umbrella decides here; the importer's own
-- clang is not there to preprocess with (charon@swift installs no clang driver), so the one the lift runs reads them.
local function importer_arguments(opt)
    local source = path.join(opt.outputdir, "importer.swift")
    io.writefile(source, "")
    local _, errors = os.iorunv(opt.swiftc, {"-frontend", "-typecheck", source, "-parse-stdlib", "-target", opt.triple,
                                             "-sdk", opt.sdk, "-dump-clang-diagnostics"})
    local line = (errors or ""):match("clang importer driver args: ([^\n]+)")
    if not line then
        raise("%s named no arguments of its clang importer", opt.swiftc)
    end
    local given = {}
    for argument in line:gmatch("'([^']*)'") do
        table.insert(given, argument)
    end
    local arguments = {}
    for index, argument in ipairs(given) do
        if argument == "-x" and given[index + 1] then
            table.join2(arguments, {"-x", given[index + 1]})
        elseif argument:startswith("-D") or argument:startswith("-U") or argument:startswith("-std=")
               or argument == "-fblocks" or argument == "-fobjc-arc" then
            table.insert(arguments, argument)
        end
    end
    if not table.contains(arguments, "-x") then
        raise("%s named no language for its clang importer", opt.swiftc)
    end
    return arguments
end

-- What the macro uses at sites of the headers expand to where they stand, for the port's triple: each header is laid
-- over the SDK's own through a VFS overlay as a copy with each use between two markers, and the umbrella is
-- preprocessed, so each use expands in its header's own context - the macros defined, redefined or undefined around it
-- (time.h undefines __CLOCK_AVAILABILITY after its last use) and the include that brings the header in
-- (dispatch/block.h refuses to be included on its own). It is preprocessed once for every language that reads the
-- lifted headers - C, Objective-C, C++, Objective-C++, and Swift through its importer - since the text written in place of
-- a use is read by all of them: UIKIT_CLASS_AVAILABLE_IOS_ONLY is extern in C and extern "C" in C++. A use two languages
-- expand differently has no one text to be replaced by; it is answered in refused, with both expansions, and not
-- lowered. A use a language does not reach (inside #ifdef __OBJC__) is not read by it either.
-- files: {file, lines, sites} each. Answers found[site] = expansion, refused[site] = why.
local function expander(opt)
    local languages = {{name = "C", arguments = {"-x", "c"}}, {name = "Objective-C", arguments = {"-x", "objective-c"}},
                       {name = "C++", arguments = {"-x", "c++"}}, {name = "Objective-C++", arguments = {"-x", "objective-c++"}},
                       {name = "Swift", arguments = importer_arguments(opt)}}
    return function (files)
        local all, roots = {}, {}
        for _, item in ipairs(files) do
            local insertions = {}
            for _, site in ipairs(item.sites) do
                table.insert(all, site)
                local last = site.line + site.count - 1
                local finish = site.count == 1 and site.col - 1 + #site.use or #site.use:match("[^\n]*$")
                table.insert(insertions, {line = site.line, col = site.col, order = 1, text = "charon_expansion_" .. #all .. " "})
                table.insert(insertions, {line = last, col = finish + 1, order = 2, text = " charon_expansion_end"})
            end
            -- last position first, so each insertion leaves the positions before it where they were
            table.sort(insertions, function (a, b)
                if a.line ~= b.line then
                    return a.line > b.line
                elseif a.col ~= b.col then
                    return a.col > b.col
                end
                return a.order < b.order
            end)
            local marked = table.join(item.lines)
            for _, insertion in ipairs(insertions) do
                local text = marked[insertion.line]
                marked[insertion.line] = text:sub(1, insertion.col - 1) .. insertion.text .. text:sub(insertion.col)
            end
            local copy = path.join(opt.outputdir, "expand", path.relative(item.file, opt.sdk))
            io.writefile(copy, table.concat(marked, "\n"))
            local folder = path.directory(item.file)
            roots[folder] = roots[folder] or {}
            table.insert(roots[folder], {type = "file", name = path.filename(item.file), ["external-contents"] = copy})
        end
        local overlay = {version = 0, ["case-sensitive"] = "false", roots = {}}
        for _, folder in ipairs(table.orderkeys(roots)) do
            table.insert(overlay.roots, {type = "directory", name = folder, contents = roots[folder]})
        end
        local vfs = path.join(opt.outputdir, "expand.yaml")
        json.savefile(vfs, overlay)
        local forms = {}
        for _, language in ipairs(languages) do
            local text = os.iorunv(opt.clang, table.join({"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot",
                                                          "-E", "-P"}, language.arguments,
                                                         {path.join(opt.outputdir, "umbrella.m"), "-ivfsoverlay", vfs}))
            for index, expansion in text:gmatch("charon_expansion_(%d+)(.-)charon_expansion_end") do
                local site = all[tonumber(index)]
                forms[site] = forms[site] or {}
                table.insert(forms[site], {language = language.name, text = expansion:trim()})
            end
        end
        local found, refused = {}, {}
        for site, expansions in pairs(forms) do
            found[site], refused[site] = one_expansion(expansions)
        end
        return found, refused
    end
end

-- The one text a use's expansions in every language that reaches it agree on, told apart by their tokens and not by the
-- spaces between them; nil and why where two of them differ. expansions: {language, text} each.
function one_expansion(expansions)
    local function tokens(text)
        return (text:gsub("%s+", " ")):trim()
    end
    local first = expansions[1]
    for _, other in ipairs(expansions) do
        if tokens(other.text) ~= tokens(first.text) then
            return nil, string.format("%s in %s, %s in %s", tokens(first.text), first.language, tokens(other.text), other.language)
        end
    end
    return first and first.text
end

-- The declarations among nodes a use reaches: one another of them redeclares (previousDecl) is not, as clang answers a use
-- from the latest - NS_ENUM's forward enum X : T X keeps a region's release its definition no longer has.
function latest(nodes)
    local superseded = {}
    for _, node in ipairs(nodes) do
        if node.previousDecl then
            superseded[node.previousDecl] = true
        end
    end
    local found = {}
    for _, node in ipairs(nodes) do
        if not superseded[node.id] then
            table.insert(found, node)
        end
    end
    return found
end

-- Where the iOS availability of a node was written, and the release it names.
local function marks(node)
    local found = {}
    for _, child in ipairs(node.inner or {}) do
        if child.kind == "AvailabilityAttr" and child.platform == "ios" and child.introduced then
            local begin = child.range and child.range.begin or {}
            local where = begin.expansionLoc or begin
            if where.file and where.line and where.col then
                -- an implicit accessor's attribute is its property's, written once for both; priority 1 is clang's
                -- AP_PragmaClangAttribute, an attribute a #pragma clang attribute region (API_AVAILABLE_BEGIN) applied.
                -- A declaration is told by where it starts, not by its id, which each dump gives anew.
                local start = node.range and node.range.begin or {}
                start = start.expansionLoc or start
                local declaration = not node.isImplicit and string.format("%s:%s:%s", tostring(start.offset), node.kind, node.name or "") or nil
                table.insert(found, {file = where.file, line = where.line, col = where.col, introduced = child.introduced,
                                     declaration = declaration, node = declaration and node or nil, region = child.priority == 1})
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
    -- A category is the class's by the class it extends, never by its own name: UIViewController (UIPresentationController)
    -- is named after a class the backports carry, and its members are UIViewController's.
    if entry.kind == "class" then
        return node.kind == "ObjCInterfaceDecl" and node.name == api
            or node.kind == "ObjCCategoryDecl" and node.interface ~= nil and node.interface.name == api
    end
    if entry.kind == "protocol" then
        return node.kind == "ObjCProtocolDecl" and node.name == api
    end
    if member then
        if (node.kind ~= "ObjCMethodDecl" and node.kind ~= "ObjCPropertyDecl") or owner_of(node) ~= member.owner then
            return false
        end
        if member.selector then
            if node.kind == "ObjCMethodDecl" then
                return node.name == member.selector and (node.instance ~= false) == (member.sign == "-")
            end
            -- a property is its getter's declaration; its setter has one of its own, implicit or written apart
            return node.name == member.selector
        end
        return node.kind == "ObjCPropertyDecl" and node.name == member.property
            or node.kind == "ObjCMethodDecl" and (node.name == member.property or setter_property(node.name) == member.property)
    end
    -- typedef enum { ... } clockid_t: the enumeration has no name of its own, and clang dumps it under the typedef's
    if entry.kind == "type" then
        return (node.kind == "TypedefDecl" or node.kind == "EnumDecl" or node.kind == "RecordDecl")
               and (node.name or node._qualified) == api
    end
    -- a constant is a variable or an enumerator
    return (node.kind == "VarDecl" or node.kind == "FunctionDecl" or node.kind == "EnumConstantDecl") and node.name == api
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

-- Every header of the frameworks read, and every header in the folders of the given system headers.
local function header_files(sdk, frameworks, headers)
    local files = {}
    for _, framework in ipairs(frameworks) do
        table.join2(files, os.files(path.join(sdk, "System", "Library", "Frameworks", framework .. ".framework", "Headers", "*.h")))
    end
    local folders = {}
    for _, header in ipairs(headers) do
        folders[path.directory(header)] = true
    end
    for _, folder in ipairs(table.orderkeys(folders)) do
        table.join2(files, os.files(path.join(folder, "*.h")))
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

-- The macro call that starts text, up to its balanced closing paren, and what follows it; nil where text does not start
-- with a call.
local function macro_call(text)
    local name, open = text:match("^([%w_]+)%s*()%(")
    if not name then
        return nil
    end
    local depth = 0
    for index = open, #text do
        local char = text:sub(index, index)
        if char == "(" then
            depth = depth + 1
        elseif char == ")" then
            depth = depth - 1
            if depth == 0 then
                return text:sub(1, index), text:sub(index + 1), name
            end
        end
    end
end

-- The use of a macro a mark's site starts: a call up to its balanced closing paren, over as many lines as it takes
-- (CADisplayLink's API_DEPRECATED_WITH_REPLACEMENT names ios(...) a line below its own name), or the name alone where no
-- paren follows it - an object-like macro, os/lock.h's OS_UNFAIR_LOCK_AVAILABILITY before a declaration or time.h's
-- __CLOCK_AVAILABILITY after an enumerator. Answers the use's text and how many lines it spans; nil where the site
-- starts no name, or a call that never closes.
function macro_use(lines, line, col)
    local text = lines[line]:sub(col)
    local name = text:match("^[%w_]+")
    if not name then
        return nil
    end
    local count = 1
    while true do
        local following = text:sub(#name + 1):match("^%s*(.?)")
        if following == "(" then
            local call = macro_call(text)
            if call then
                local _, breaks = call:gsub("\n", "")
                return call, breaks + 1
            end
        elseif following ~= "" then
            return name, 1
        end
        if not lines[line + count] then
            if following == "" then
                return name, 1
            end
            return nil
        end
        text = text .. "\n" .. lines[line + count]
        count = count + 1
    end
end

-- The declaration of a member from its AST node, as a category would repeat a protocol's requirement for a class or an
-- interface would declare a property's setter apart from it: the member's own type, and for a method its selector's
-- parts paired in order with its parameters.
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

-- What charon@apple-compat carries, in the registry's own entry shape: every symbol compat.provided() names is
-- unconditionally linked (compat.lua's own force_includes() already refuses a symbol it does not know), so none of
-- these takes a floor above opt.minimum the way a registry entry sometimes does - the whole point of asking is that
-- compat carries it all the way down. The types they take (os_unfair_lock_t, clockid_t) come down with them as any
-- type an implemented API names does, below.
-- An entry is named as C names the function: dispatch_assert_queue$V2 is the symbol of dispatch_assert_queue.
local function system_entries()
    local names = {}
    for symbol in pairs(compat.provided("iOS")) do
        names[symbol:match("^[^$]+")] = true
    end
    local entries = {}
    for _, name in ipairs(table.orderkeys(names)) do
        table.insert(entries, {api = name, status = "implemented"})
    end
    return entries
end

-- Where a declaration a #pragma clang attribute region reaches takes an availability of its own, and the text that
-- gives it one: an attribute written on a declaration replaces the region's for that platform (measured: a method, a
-- property, a protocol, a class's @interface, an extern variable, a function, a typedef, an enumeration's definition
-- and an enumerator inside API_AVAILABLE_BEGIN(ios(8)) each answer only the attribute written on it), and the region's
-- others keep theirs. After the declaration's last token (before its ";") for a method, a property and an enumeration's
-- or structure's definition, after its name for an enumerator, before its first token for the rest. A forward
-- declaration (@class, enum X : T X inside NS_ENUM) takes none - the region gives @class none either, and a use reaches
-- the definition - and a declaration whose name is not where the dump says, in this file, is left alone. 0-based offset
-- into content, or nil.
function declared_at(content, node, target)
    local function at(location)
        location = location or {}
        return location.expansionLoc or location
    end
    local function spelled(location)
        location = location or {}
        return location.spellingLoc or location
    end
    local attribute = string.format("__attribute__((availability(ios,introduced=%s)))", version(target))
    local name = (node.name or ""):match("^[%w_]+")
    -- a category is located at the name of the class it extends (@interface NSObject (ZzCat): at NSObject)
    if node.kind == "ObjCCategoryDecl" then
        name = (node.interface or {}).name
    end
    local loc = spelled(node.loc)
    local first, last = at((node.range or {}).begin), at((node.range or {})["end"])
    local kind = node.kind
    -- a method's location is its - or +, its name the first part of its selector after it
    if kind == "ObjCMethodDecl" then
        local text = first.offset and last.offset and content:sub(first.offset + 1, last.offset + (last.tokLen or 0)) or ""
        if not name or not text:find("^[-+]%s*%b()%s*" .. name .. "%f[^%w_]") then
            return nil
        end
    elseif not name or not loc.offset or content:sub(loc.offset + 1, loc.offset + #name) ~= name then
        return nil
    end
    if kind == "EnumConstantDecl" then
        return loc.offset + #name, " " .. attribute
    elseif kind == "ObjCMethodDecl" or kind == "ObjCPropertyDecl" then
        -- a method's range ends at its ";", before which the attribute goes
        if last.offset and content:sub(last.offset + 1, last.offset + 1) == ";" then
            return last.offset, " " .. attribute
        end
        return last.offset and last.offset + (last.tokLen or 0), last.offset and " " .. attribute
    elseif kind == "EnumDecl" or kind == "RecordDecl" then
        if last.offset and content:sub(last.offset + 1, last.offset + 1) == "}" then
            return last.offset + 1, " " .. attribute
        end
    elseif kind == "ObjCInterfaceDecl" or kind == "ObjCProtocolDecl" or kind == "ObjCCategoryDecl" then
        if first.offset and last.offset and content:sub(first.offset + 1, first.offset + 1) == "@"
           and content:sub(last.offset + 1, last.offset + 3) == "end" then
            return first.offset, attribute .. " "
        end
    elseif kind == "TypedefDecl" or kind == "FunctionDecl" or kind == "VarDecl" then
        return first.offset, first.offset and attribute .. " "
    end
end

-- text with its comments and the insides of its string and character literals blanked, every byte and newline kept
-- where it was: where a type's name is looked for, since a mention in a comment (a header's documentation) or in a message
-- (API_DEPRECATED_WITH_REPLACEMENT's) uses nothing.
function code_of(text)
    local parts, index = {}, 1
    while true do
        local found = text:find("[/\"']", index)
        if not found then
            table.insert(parts, text:sub(index))
            break
        end
        table.insert(parts, text:sub(index, found - 1))
        local char, following = text:sub(found, found), text:sub(found + 1, found + 1)
        local finish
        if char == "/" and following == "/" then
            finish = (text:find("\n", found, true) or #text + 1) - 1
            table.insert(parts, string.rep(" ", finish - found + 1))
        elseif char == "/" and following == "*" then
            local _, closing = text:find("*/", found + 2, true)
            finish = closing or #text
            table.insert(parts, (text:sub(found, finish):gsub("[^\n]", " ")))
        elseif char == "/" then
            finish = found
            table.insert(parts, char)
        else
            -- a literal ends at its own quote or, unclosed (an apostrophe in a #warning), at the line's end
            finish = found + 1
            while finish <= #text do
                local at = text:sub(finish, finish)
                if at == "\\" then
                    finish = finish + 2
                elseif at == char or at == "\n" then
                    break
                else
                    finish = finish + 1
                end
            end
            finish = math.min(finish, #text)
            local closing = text:sub(finish, finish)
            if closing == char then
                table.insert(parts, char .. string.rep(" ", finish - found - 1) .. char)
            else
                table.insert(parts, char .. (text:sub(found + 1, finish):gsub("[^\n]", " ")))
            end
        end
        index = finish + 1
    end
    return table.concat(parts)
end

-- The words a C declaration that takes in byte position of code could declare: the declaration runs from the end of the
-- one before it (a ";", "{" or "}", an @end, or a directive's line) to its own ";" or "{", and a word counts where it
-- stands outside every paren and bracket and a "(", ";", "=", "[" or "," follows it - a function's name, a variable's,
-- a typedef's, and the availability macros beside them, but not ios or macos inside those macros' arguments. A return
-- type on the line above its function's name (qos_class_t / qos_class_self(void);) and parameters over several lines
-- are the same declaration.
function statement_words(code, position)
    local start = 1
    for index = position - 1, 1, -1 do
        local char = code:sub(index, index)
        if char == ";" or char == "{" or char == "}" then
            start = index + 1
            break
        elseif code:sub(index, index + 3) == "@end" then
            start = index + 4
            break
        elseif char == "\n" and index + 1 < position and code:match("^[ \t]*#", index + 1) then
            start = (code:find("\n", index + 1, true) or #code) + 1
            break
        end
    end
    -- a "#" that only blanks stand before on its line
    local function directive(index)
        local back = index - 1
        while back > 0 and code:sub(back, back):match("[ \t]") do
            back = back - 1
        end
        return back == 0 or code:sub(back, back) == "\n"
    end
    local words, depth, index = {}, 0, start
    while index <= #code do
        local char = code:sub(index, index)
        if depth == 0 and (char == ";" or char == "{") and index >= position then
            break
        elseif char == "(" or char == "[" then
            depth = depth + 1
            index = index + 1
        elseif char == ")" or char == "]" then
            depth = math.max(depth - 1, 0)
            index = index + 1
        elseif char:match("%d") then
            index = index + #code:match("^[%w_%.]+", index)
        elseif char:match("[%a_]") then
            local word = code:match("^[%a_][%w_]*", index)
            if depth == 0 and code:match("^%s*[%(;=%[,]", index + #word) then
                table.insert(words, word)
            end
            index = index + #word
        elseif char == "#" and directive(index) then
            -- a directive inside the declaration (#if around a parameter) is no part of it
            index = (code:find("\n", index, true) or #code) + 1
        else
            index = index + 1
        end
    end
    return words
end

-- lift(opt): opt.clang, opt.swiftc (the Swift compiler whose importer reads the result), opt.sdk, opt.triple, opt.minimum,
-- opt.registry (the folder holding registry/), opt.outputdir.
-- Answers the VFS overlay to hand the compiler and what was done; raises when either check finds a difference.
function lift(opt)
    os.tryrm(opt.outputdir)
    os.mkdir(opt.outputdir)
    local listed, incomplete, registered = backports.registry(opt.registry)
    if #incomplete > 0 then
        raise("the backports registry is incomplete: %s", table.concat(incomplete, "; "))
    end
    -- the frameworks read: every one the registry has a file for
    local frameworks = registered
    local symbols = {}
    for _, entry in ipairs(system_entries()) do
        table.insert(symbols, entry.api)
    end
    local system = system_headers(opt.sdk, symbols)
    local dump = dumper(opt, frameworks, system)
    local expand = expander(opt)
    local kept, entries = {}, {}
    for api, entry in pairs(listed) do
        if entry.status == "implemented" then
            table.insert(entries, entry)
        else
            kept[api] = true
        end
    end
    for _, entry in ipairs(system_entries()) do
        entry.system = true
        table.insert(entries, entry)
        listed[entry.api] = listed[entry.api] or entry
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

    -- system_files: where what apple-compat carries is declared, the files a type it takes is looked for in beside the
    -- frameworks' own
    local edits, blocked, targets, unmatched, system_files = {}, {}, {}, {}, {}
    -- regional[file][id]: a declaration a region's attribute reaches, to be given its own (see declared_at)
    local regional = {}
    local function place(mark, target)
        if mark.region then
            if later(mark.introduced, target) and mark.node and mark.file:startswith(opt.sdk) then
                regional[mark.file] = regional[mark.file] or {}
                regional[mark.file][mark.declaration] = {node = mark.node, target = target}
                edits[mark.file] = edits[mark.file] or {}
            end
        elseif later(mark.introduced, target) and mark.file:startswith(opt.sdk) then
            edits[mark.file] = edits[mark.file] or {}
            local at = mark.line .. ":" .. mark.col
            local edit = edits[mark.file][at] or {line = mark.line, col = mark.col, declarations = {}}
            edit.target = target
            if mark.declaration then
                edit.declarations[mark.declaration] = true
            end
            edits[mark.file][at] = edit
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
                if entry.system then
                    system_files[mark.file] = true
                end
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
            -- a class's surface, and a protocol's, which has no superclass
            if entry.kind == "class" or entry.kind == "protocol" then
                local owners = table.join({entry.api}, entry.kind == "class" and superclasses(entry.api) or {})
                for _, child in ipairs(node.inner or {}) do
                    -- an implicit setter's mark is its property's, which the property decides below; a setter the
                    -- backports leave out of a property they carry is kept by its own declaration (see setters)
                    local implicit_setter = child.kind == "ObjCMethodDecl" and child.isImplicit and (child.name or ""):find(":$")
                    if (child.kind == "ObjCMethodDecl" or child.kind == "ObjCPropertyDecl") and not implicit_setter then
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

    -- A property the backports carry whose setter they leave out: the setter clang declares for it shares the property's
    -- mark, so lowering the mark would lower the setter too. It is declared explicitly beside the property instead, at
    -- the release the SDK gives it - Swift then answers the property from the lowered release and refuses the setter
    -- below the SDK's, as it does for any setter declared apart from its property.
    local setters = {}
    for api in pairs(kept) do
        local member = member_api(api)
        if member and member.selector and member.selector:find(":$") then
            for _, node in ipairs(dump(filter_of(listed[api]))) do
                if node.kind == "ObjCMethodDecl" and node.isImplicit and matches(listed[api], node) then
                    for _, mark in ipairs(marks(node)) do
                        local at = mark.line .. ":" .. mark.col
                        if edits[mark.file] and edits[mark.file][at] and not blocked[mark.file .. ":" .. at] then
                            setters[mark.file .. ":" .. at] = protocol_member_declaration(node, node.name, mark.introduced)
                        end
                    end
                end
            end
        end
    end

    -- The types the headers alone declare that implemented API names in its signature: the prefixed names its signature
    -- spells, every typedef its type goes through (a function's return type and parameters, a variable's type: the
    -- dump's _typedefs), every typedef a method or property names for its result, a parameter or itself, and then every
    -- typedef those name in turn - qos_class_self returns qos_class_t, dispatch_queue_attr_make_with_qos_class takes
    -- dispatch_qos_class_t, which is qos_class_t, whose enumerators are the values both mean.
    local named = {}
    local function alias(type)
        type = type or {}
        return type.typeAliasDeclId and (type.qualType or ""):gsub("%f[%w_]const%f[^%w_]", ""):match("[%a_][%w_]*") or nil
    end
    for _, entry in ipairs(entries) do
        for _, node in ipairs(dump(filter_of(entry))) do
            if matches(entry, node) then
                local signature = {(node.type or {}).qualType or "", (node.returnType or {}).qualType or ""}
                for _, name in ipairs(node._typedefs or {}) do
                    named[name] = true
                end
                for _, type in ipairs({node.type or {}, node.returnType or {}}) do
                    local name = alias(type)
                    if name then
                        named[name] = true
                    end
                end
                for _, child in ipairs(node.inner or {}) do
                    if child.kind == "ParmVarDecl" then
                        table.insert(signature, (child.type or {}).qualType or "")
                        local name = alias(child.type)
                        if name then
                            named[name] = true
                        end
                    end
                end
                for word in table.concat(signature, " "):gmatch("%f[%w_]([NUC][SIG][%w_]+)") do
                    named[word] = true
                end
            end
        end
    end
    local followed = {}
    local pending = table.keys(named)
    while #pending > 0 do
        local name = table.remove(pending)
        if not followed[name] then
            followed[name] = true
            for _, node in ipairs(dump(name)) do
                if node.kind == "TypedefDecl" and node.name == name then
                    for _, further in ipairs(node._typedefs or {}) do
                        if not named[further] then
                            named[further] = true
                            table.insert(pending, further)
                        end
                    end
                end
            end
        end
    end
    local lowered_types, kept_types = {}, {}
    local headers = header_files(opt.sdk, frameworks, table.orderkeys(system_files))
    local codes = {}
    local function code(file)
        codes[file] = codes[file] or code_of(io.readfile(file))
        return codes[file]
    end
    -- What keeps a type from coming down: every use of it in the headers read whose declaration is above the port's
    -- release and not implemented, and every use whose declaration cannot be told; and the latest minimum among the
    -- implemented ones. A typedef that names it (dispatch_qos_class_t is qos_class_t) is no use of its own: its uses
    -- are the type's. declared: the type's own declarations, which are no uses of it.
    local function users(name, declared, seen)
        seen[name] = true
        local blocking, target = {}, opt.minimum
        for _, file in ipairs(headers) do
            local text = code(file)
            if text:find("%f[%w_]" .. name .. "%f[^%w_]") then
                local starts, lines = line_starts(text), text:split("\n", {strict = true})
                for index, line in ipairs(lines) do
                    if line:find("%f[%w_]" .. name .. "%f[^%w_]") and not line:trim():startswith("#") then
                        local low, high = starts[index], starts[index + 1]
                        -- its own declaration, as the dump has it, or one in a branch the preprocessor did not take
                        -- (dispatch/object.h's typedef unsigned int dispatch_qos_class_t where sys/qos.h is missing)
                        local own = covering(declared, text, low, high, name)
                                    or table.contains(statement_words(text, low), name)
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
                            local user, api, alias
                            if owner then
                                user = covering(dump(owner .. "::"), text, low, high, name)
                                if user and user.kind == "ObjCMethodDecl" then
                                    api = string.format("%s[%s %s]", user.instance == false and "+" or "-", owner, user.name)
                                elseif user and user.kind == "ObjCPropertyDecl" then
                                    api = owner .. "." .. user.name
                                end
                            else
                                -- only a word C syntax could declare in the declaration the line is part of is looked
                                -- up (see statement_words); "int" or "in" names no declaration, and a dump of every
                                -- name containing it is the whole SDK
                                for _, word in ipairs(statement_words(text, low)) do
                                    if not user and word ~= name then
                                        for _, node in ipairs(dump(word)) do
                                            if (node.kind == "FunctionDecl" or node.kind == "VarDecl" or node.kind == "TypedefDecl")
                                               and node.name == word and covering({node}, text, low, high, name) then
                                                user, api = node, word
                                                alias = node.kind == "TypedefDecl" and node or nil
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
                            elseif alias then
                                if not seen[api] then
                                    local more, floor = users(api, {alias}, seen)
                                    table.join2(blocking, more)
                                    if later(floor, target) then
                                        target = floor
                                    end
                                end
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
        return blocking, target
    end
    local names = table.keys(named)
    table.sort(names)
    for _, name in ipairs(names) do
        local declared = {}
        for _, node in ipairs(dump(name)) do
            if (node.kind == "TypedefDecl" or node.kind == "EnumDecl" or node.kind == "RecordDecl") and (node.name or node._qualified) == name then
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
            local blocking, target = users(name, declared, {})
            if #blocking == 0 then
                lowered_types[name] = target
                for _, node in ipairs(declared) do
                    for _, mark in ipairs(type_marks(node)) do
                        place(mark, target)
                    end
                end
            else
                table.sort(blocking)
                kept_types[name] = table.unique(blocking)
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

    -- The copies: each mark rewritten where its macro was written - the release inside ios(...) or the positional argument
    -- lift_macro knows, and for any other macro its own expansion at that place, with the release lowered. Only the
    -- places our marks name change: a macro's definition, and every other place it is used, stay as the SDK wrote them.
    local roots, lifted = {}, 0
    for file, categories in pairs(redeclared) do
        edits[file] = edits[file] or {}
    end
    local sorted_files = table.keys(edits)
    table.sort(sorted_files)
    local copies, unrewritten = {}, {}
    for _, file in ipairs(sorted_files) do
        local content = io.readfile(file)
        if not content then
            raise("lift() marked an edit in %s, which cannot be read back", file)
        end
        local lines = content:split("\n", {strict = true})
        -- Rightmost column first, on every line that carries more than one edit: a rewrite only ever touches its own
        -- macro's use and passes the rest of the line through unchanged, so applying the furthest-right edit first
        -- leaves every column to its left still meaning what marks() found it to mean. The other order corrupts them
        -- both - a shorter or longer replacement at the earlier column shifts every column after it (a property, its
        -- getter and its setter sharing one line is exactly where two edits land on the same line).
        local sites = {}
        for _, edit in pairs(edits[file]) do
            if not blocked[file .. ":" .. edit.line .. ":" .. edit.col] then
                edit.use, edit.count = macro_use(lines, edit.line, edit.col)
                if edit.use then
                    table.insert(sites, edit)
                end
            end
        end
        local starts = line_starts(content)
        for _, held in pairs(regional[file] or {}) do
            local offset, text = declared_at(content, held.node, held.target)
            if offset then
                local line = 1
                while starts[line + 1] and starts[line + 1] <= offset + 1 do
                    line = line + 1
                end
                table.insert(sites, {line = line, col = offset + 2 - starts[line], insert = text})
            end
        end
        table.sort(sites, function (a, b)
            return a.line == b.line and a.col > b.col or a.line < b.line
        end)
        local expanding = {}
        for _, site in ipairs(sites) do
            if site.use and lift_macro(site.use, site.target) == site.use then
                table.insert(expanding, site)
            end
        end
        if #expanding > 0 then
            table.insert(unrewritten, {file = file, lines = lines, sites = expanding})
        end
        table.insert(copies, {file = file, lines = lines, sites = sites})
    end
    -- every file's uses at once, one preprocess for each language
    local expanded, refused = {}, {}
    if #unrewritten > 0 then
        expanded, refused = expand(unrewritten)
    end
    local refusals = {}
    for _, item in ipairs(unrewritten) do
        for _, site in ipairs(item.sites) do
            if refused[site] then
                table.insert(refusals, string.format("%s:%d %s expands differently by language (%s)",
                             path.relative(item.file, opt.sdk), site.line, (site.use:gsub("%s+", " ")), refused[site]))
            end
        end
    end
    for _, item in ipairs(copies) do
        local file, lines, sites = item.file, item.lines, item.sites
        for _, site in ipairs(sites) do
            if site.insert then
                local text = lines[site.line]
                lines[site.line] = text:sub(1, site.col - 1) .. site.insert .. text:sub(site.col)
                lifted = lifted + 1
            else
                local rewritten = lift_macro(site.use, site.target)
                if rewritten == site.use and expanded[site] then
                    rewritten = lift_expansion(expanded[site], site.target, table.getn(table.keys(site.declarations))) or site.use
                end
                local setter = setters[file .. ":" .. site.line .. ":" .. site.col]
                local last = site.line + site.count - 1
                local before = lines[site.line]:sub(1, site.col - 1)
                local finish = site.count == 1 and site.col - 1 + #site.use or #site.use:match("[^\n]*$")
                local after = lines[last]:sub(finish + 1)
                if rewritten ~= site.use and setter then
                    -- the setter's own declaration right after the property's, on its line; without the property's ";"
                    -- there to follow, the mark is not lowered at all
                    local ending = after:find(";", 1, true)
                    if ending then
                        after = after:sub(1, ending) .. " " .. setter .. after:sub(ending + 1)
                    else
                        rewritten = site.use
                    end
                end
                if rewritten ~= site.use then
                    -- back over the same lines, so every later mark's line still means what marks() found it to mean
                    local parts = (before .. rewritten .. after):split("\n", {strict = true})
                    for index = 1, site.count do
                        lines[site.line + index - 1] = parts[index] or ""
                    end
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

    -- Both ways: what is implemented answers the lowered release, and nothing else moved. A use no one text can stand
    -- for in every language fails by its own name, whatever else it would have shown.
    local failures = table.join(refusals)
    for name, target in pairs(lowered_types) do
        for _, node in ipairs(latest(dump(name, vfs))) do
            if (node.kind == "TypedefDecl" or node.kind == "EnumDecl" or node.kind == "RecordDecl") and (node.name or node._qualified) == name then
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
            for _, node in ipairs(latest(dump(filter_of(entry), vfs))) do
                local own = node.kind == "ObjCMethodDecl"
                            and listed[string.format("%s[%s %s]", node.instance == false and "+" or "-", owner_of(node) or "", node.name)]
                if matches(entry, node) and not (own and own.status ~= "implemented") then
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
    -- A plain function or type can be unmatched honestly (a compiler-rt intrinsic, a private header this dumper
    -- does not read) - lift.lua's own header comment already documents that as expected. A protocol, and a class or
    -- protocol member, cannot: a protocol is dumped by its name, and entry.kind == "class"/nil-with-member-syntax names a
    -- method or property the AST-dump filter should find
    -- directly under its owner's own qualified scope, whether or not that owner has a registry entry of its own (this
    -- lookup never consults listed[owner] - see matches()). An entry that names a real member and still matches
    -- nothing is not a gap in SDK coverage, it is filter_of()/matches() failing to find something that is really
    -- there, and reporting it only inside a count nobody is required to look at is exactly the silent loss this
    -- checks against.
    local silent = {}
    for _, api in ipairs(unmatched) do
        if member_api(api:gsub("%(%)$", "")) or (listed[api] or {}).kind == "protocol" then
            table.insert(silent, api)
        end
    end
    if #silent > 0 then
        raise("lift() found no declaration at all for %d registered class/protocol member(s), which should never be silently absent: %s",
              #silent, table.concat(silent, "; "))
    end
    return {vfs = vfs, lifted = lifted, headers = #sorted_files, implemented = #entries, unmatched = unmatched,
            types = lowered_types, kept_types = kept_types}
end

-- The release of the availability macro that starts text rewritten to target, where the text itself spells it: ios(...),
-- the platform and release API_AVAILABLE and its kin write. Any other macro - a release passed by position, pasted into a
-- name, or no argument at all - is left to its own expansion (lift_expansion).
function lift_macro(text, target)
    local call, rest = macro_call(text)
    if not call then
        return text
    end
    -- a call that carries several iOS releases (DISPATCH_OPTIONS, one per enumerator in its arguments) is not one
    -- availability macro; its expansion is lowered instead, where each release can be counted
    local _, releases = call:gsub("%f[%w]ios%s*%(", "")
    if releases > 1 then
        return text
    end
    local dotted = version(target)
    if call:find("%f[%w]ios%s*%(") then
        -- Almost every API_AVAILABLE/__API_AVAILABLE spells its release with dots (ios(14.0)), but a few of the SDK's
        -- own declarations spell the ios() argument with an underscore instead (ios(14_0), UICollectionViewListCell
        -- among them) inside an otherwise dotted macro - the character class has to accept both, or the underscored
        -- half of the token is left behind unrewritten (ios(14_0) -> ios(6.1.3_0), which is not a version clang or
        -- anything else parses).
        call = call:gsub("(%f[%w]ios%s*%(%s*)[%d%._]+", "%1" .. dotted, 1)
    end
    return call .. rest
end

-- A macro use's own expansion (expander() above) with its iOS releases rewritten to target: the form for a use no branch
-- of lift_macro can rewrite in place - CG_AVAILABLE_STARTING(mac, ios) and IMAGEIO_AVAILABLE_STARTING pick a positional
-- macro by argument count, __OSX_AVAILABLE_BUT_DEPRECATED pastes its releases into a macro name that exists only for the
-- pairs the SDK itself wrote (there is no __AVAILABILITY_INTERNAL__IPHONE_6_1_DEP__IPHONE_11_0), an object-like macro
-- has no argument at all. One release is the release of every declaration the use is written for. Several belong to one
-- declaration each (DISPATCH_OPTIONS' enumerators), and are lowered only when as many declarations are ours - the
-- count is what the caller holds a mark for. nil otherwise, and for a use with no iOS release, so nothing is guessed at.
function lift_expansion(expansion, target, declarations)
    local _, releases = expansion:gsub("availability%s*%(%s*ios%s*,%s*introduced%s*=", "")
    if releases == 0 or (releases > 1 and releases ~= declarations) then
        return nil
    end
    return (expansion:gsub("(availability%s*%(%s*ios%s*,%s*introduced%s*=%s*)[%d%._]+", "%1" .. version(target)))
end
