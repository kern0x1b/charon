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
-- superclass is left out of a subclass that declares it again. A member the SDK declares for a class only in a
-- superclass or a protocol the class conforms to is redeclared on the class itself, at the lowered release, rather than
-- lowered where every other heir would see it. The result is checked both ways before it is used:
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
-- dispatch/dispatch.h and refuses to be included on its own). A header a module map lists that another header of the same
-- map includes is left to that header when standalone(name) says it cannot be included alone: SDK 16.4's dispatch map names
-- an umbrella, 26.2's lists every dispatch header, block.h among them. Which of them declares the symbol is the dump's to
-- say. A symbol no public header names - a compiler-rt intrinsic - brings none; the dump then finds no declaration of it.
function system_headers(sdk, symbols, standalone)
    local root = path.join(sdk, "usr", "include")
    local public, umbrellas = {}, {}
    for _, map in ipairs(os.files(path.join(root, "**.modulemap"))) do
        local folder = path.directory(map)
        local listed = {}
        for line in io.readfile(map):gmatch("[^\n]+") do
            local umbrella = line:match('^%s*umbrella%s+header%s+"([^"]+)"')
            local header = line:match('^%s*header%s+"([^"]+)"')
            if umbrella then
                umbrellas[path.relative(folder, root)] = path.relative(path.join(folder, umbrella), root)
            elseif header then
                table.insert(listed, path.relative(path.join(folder, header), root))
            end
        end
        local included = {}
        for _, name in ipairs(listed) do
            local file = path.join(root, name)
            if os.isfile(file) then
                for target in ("\n" .. io.readfile(file)):gmatch('\n%s*#%s*include%s*[<"]([^>"\n]+)[>"]') do
                    included[target] = true
                    included[path.relative(path.join(path.directory(file), target), root)] = true
                end
            end
        end
        for _, name in ipairs(listed) do
            if not included[name] or standalone(name) then
                public[name] = true
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
    end, umbrella
end

-- Which receivers conform to which protocols, as clang answers it: a receiver converts to id<P> without a diagnostic
-- only where it conforms - through its class, a superclass, any category the umbrella reaches or a protocol it inherits,
-- which no dump by name lists. A pair that conforms (NSObject to NSObject) and one that does not (NSObject to NSCopying)
-- are asked beside the others, and a probe that tells either wrongly fails rather than answer the rest.
local function conformer(opt, umbrella)
    return function (questions)
        local asked = table.join({{receiver = "NSObject *", protocol = "NSObject"}, {receiver = "NSObject *", protocol = "NSCopying"}},
                                 questions)
        local text = io.readfile(umbrella)
        local _, base = text:gsub("\n", "")
        local lines = {}
        for index, question in ipairs(asked) do
            table.insert(lines, string.format("static id<%s> charon_conforms_%d(%s x) { return x; }", question.protocol, index,
                                              question.receiver))
        end
        local probe = path.join(opt.outputdir, "conforms.m")
        io.writefile(probe, text .. table.concat(lines, "\n") .. "\n")
        local _, diagnostics = os.iorunv(opt.clang, {"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot",
                                                     "-fsyntax-only", "-x", "objective-c", "-fno-caret-diagnostics",
                                                     "-fno-color-diagnostics", "-Wno-unguarded-availability",
                                                     "-Wno-unguarded-availability-new", "-Wno-unused-function", probe})
        local refused = {}
        for line in (diagnostics or ""):gmatch("[^\n]+") do
            local at = line:match("conforms%.m:(%d+):%d+: warning: returning .* from a function with incompatible result type")
            if at then
                refused[tonumber(at) - base] = true
            end
        end
        if refused[1] or not refused[2] then
            raise("the conformance probe %s tells NSObject's conformance to NSObject or to NSCopying wrongly: %s", probe,
                  diagnostics or "")
        end
        local answers = {}
        for index = 3, #asked do
            answers[index - 2] = not refused[index]
        end
        return answers
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

-- The languages that read the lifted headers, and what each tells the compiler.
local function languages_of(opt)
    return {{name = "C", arguments = {"-x", "c"}}, {name = "Objective-C", arguments = {"-x", "objective-c"}},
            {name = "C++", arguments = {"-x", "c++"}}, {name = "Objective-C++", arguments = {"-x", "objective-c++"}},
            {name = "Swift", arguments = importer_arguments(opt)}}
end

-- Where the preprocessor keeps each of names as a token, in any of the languages: kept[file][line][name], for the lines
-- of every file the umbrella reaches (reached[file]), read back through the line markers of clang -E. A name a line
-- spells that no language keeps there is no use of it: a branch no language takes (OSSpinLockDeprecated.h's
-- OSSPINLOCK_USE_INLINED), or a macro that makes a message of it (OSSPINLOCK_DEPRECATED_REPLACE_WITH(os_unfair_lock)).
-- A file the umbrella does not reach is not told. For the names of apart, each language's own is told as well:
-- own[language name] = {kept = ..., reached = ...}.
local function preprocessed(opt, languages, names, apart)
    local wanted, own = {}, {}
    for _, name in ipairs(names) do
        wanted[name] = true
    end
    local kept, reached = {}, {}
    for _, language in ipairs(languages) do
        local text = os.iorunv(opt.clang, table.join({"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot", "-E"},
                                                     language.arguments, {path.join(opt.outputdir, "umbrella.m")}))
        tokens_kept(text, wanted, kept, reached)
        if apart then
            own[language.name] = {kept = {}, reached = {}}
            tokens_kept(text, apart, own[language.name].kept, own[language.name].reached)
        end
    end
    return kept, reached, own
end

-- The names of wanted a preprocessor's output (clang -E, with its line markers) keeps as tokens, by the file and line
-- each came from: added to kept[file][line][name], and every file it names to reached.
function tokens_kept(text, wanted, kept, reached)
    local file, line
    for output in (text .. "\n"):gmatch("([^\n]*)\n") do
        local number, marked = output:match('^# (%d+) "([^"]*)"')
        if number then
            file, line = marked, tonumber(number)
            reached[file] = true
        elseif file then
            for word in code_of(output):gmatch("[%a_][%w_]*") do
                if wanted[word] then
                    kept[file] = kept[file] or {}
                    kept[file][line] = kept[file][line] or {}
                    kept[file][line][word] = true
                end
            end
            line = line + 1
        end
    end
end

-- What the macro uses at sites of the headers expand to where they stand, for the port's triple: each header is laid
-- over the SDK's own through a VFS overlay as a copy with each use between two markers, and the umbrella is
-- preprocessed, so each use expands in its header's own context - the macros defined, redefined or undefined around it
-- (time.h undefines __CLOCK_AVAILABILITY after its last use) and the include that brings the header in
-- (dispatch/block.h refuses to be included on its own). It is preprocessed once for every language that reads the
-- lifted headers - C, Objective-C, C++, Objective-C++, and Swift through its importer - since the text written in place of
-- a use is read by all of them: UIKIT_CLASS_AVAILABLE_IOS_ONLY is extern in C and extern "C" in C++. Where the languages
-- expand a use differently and the macros they predefine tell the expansions apart, each gets its own under a conditional
-- on those macros (by_language); any other difference has no text to be replaced by, is answered in refused with two of
-- the expansions, and is not lowered. A use a language does not reach (inside #ifdef __OBJC__) is not read by it either.
-- headers: the SDK's headers read, whose conditionals say which predefined macros they test. files: {file, lines, sites}
-- each. Answers found[site] = expansion or {branches}, refused[site] = why.
local function expander(opt, headers, languages)
    -- The macros each language predefines (clang -dM on an empty input), and of those whose presence differs between
    -- the languages the ones the SDK's own #if, #ifdef, #ifndef and #elif test, most tested first.
    local empty = path.join(opt.outputdir, "empty.h")
    io.writefile(empty, "")
    local defined, count = {}, {}
    for _, language in ipairs(languages) do
        defined[language.name] = {}
        local text = os.iorunv(opt.clang, table.join({"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot",
                                                      "-E", "-dM"}, language.arguments, {empty}))
        for name in text:gmatch("#define ([%w_]+)") do
            defined[language.name][name] = true
            count[name] = (count[name] or 0) + 1
        end
    end
    local tested = {}
    for _, file in ipairs(headers) do
        for line in io.readfile(file):gmatch("[^\n]+") do
            local condition = line:match("^%s*#%s*if%s(.*)") or line:match("^%s*#%s*ifdef%s(.*)")
                              or line:match("^%s*#%s*ifndef%s(.*)") or line:match("^%s*#%s*elif%s(.*)")
            for name in (condition or ""):gmatch("[%a_][%w_]*") do
                if count[name] and count[name] < #languages then
                    tested[name] = (tested[name] or 0) + 1
                end
            end
        end
    end
    local keys = table.orderkeys(tested)
    table.sort(keys, function (a, b)
        return tested[a] ~= tested[b] and tested[a] > tested[b] or tested[a] == tested[b] and a < b
    end)
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
            found[site], refused[site] = by_language(expansions, defined, keys)
        end
        return found, refused
    end
end

-- The text a use's expansions stand for in every language that reaches it, told apart by their tokens and not by the
-- spaces between them: the one text they agree on, or where they differ, {branches = {{condition, text}}, rest} - a text
-- for each set of the predefined macros that tells them apart, the fewest such macros that do, taken in the order of
-- keys (the macros the SDK's conditionals test, most tested first). rest is true where a combination of those macros
-- no language here has is left, which the conditional then refuses to compile. nil and why where no macros tell the
-- expansions apart. expansions: {language, text} each; defined[language]: the macros it predefines.
function by_language(expansions, defined, keys)
    local function tokens(text)
        return (text:gsub("%s+", " ")):trim()
    end
    local first, differing = expansions[1], nil
    for _, other in ipairs(expansions) do
        if tokens(other.text) ~= tokens(first.text) then
            differing = differing or other
        end
    end
    if not first or not differing then
        return first and first.text
    end
    local why = string.format("%s in %s, %s in %s", tokens(first.text), first.language, tokens(differing.text), differing.language)
    -- the combinations of size macros out of keys, in order
    local function combinations(size, from, chosen, found)
        if #chosen == size then
            table.insert(found, table.join(chosen))
            return found
        end
        for index = from, #keys do
            table.insert(chosen, keys[index])
            combinations(size, index + 1, chosen, found)
            table.remove(chosen)
        end
        return found
    end
    for size = 1, math.min(#expansions - 1, #keys) do
        for _, chosen in ipairs(combinations(size, 1, {}, {})) do
            local texts, order, apart = {}, {}, true
            for _, expansion in ipairs(expansions) do
                local signs = {}
                for _, key in ipairs(chosen) do
                    table.insert(signs, string.format("%sdefined(%s)", defined[expansion.language][key] and "" or "!", key))
                end
                local condition = table.concat(signs, " && ")
                if texts[condition] and tokens(texts[condition].text) ~= tokens(expansion.text) then
                    apart = false
                elseif not texts[condition] then
                    texts[condition] = expansion
                    table.insert(order, condition)
                end
            end
            if apart then
                local branches = {}
                for _, condition in ipairs(order) do
                    table.insert(branches, {condition = condition, text = texts[condition].text, language = texts[condition].language})
                end
                return {branches = branches, rest = #order < 2 ^ size}
            end
        end
    end
    return nil, why .. ", and no macro the languages predefine differently and the SDK tests tells them apart"
end

-- The text a use is replaced by where the languages expand it differently: each branch's expansion lowered to target
-- (lift_expansion) under its own condition, on lines of their own, so the preprocessor of each language that reads the
-- header picks its own; a combination no language measured has fails to compile, naming the use. nil where a branch
-- cannot be lowered.
function language_conditional(split, target, declarations, use)
    local lines = {""}
    for index, branch in ipairs(split.branches) do
        local lowered = lift_expansion(branch.text, target, declarations)
        if not lowered then
            return nil
        end
        table.insert(lines, string.format("#%s %s", index == 1 and "if" or "elif", branch.condition))
        table.insert(lines, lowered)
    end
    if split.rest then
        table.insert(lines, "#else")
        table.insert(lines, string.format("#error \"the lifted %s was expanded for no language with these macros\"", use:match("^[%w_]+")))
    end
    table.insert(lines, "#endif")
    table.insert(lines, "")
    return table.concat(lines, "\n")
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

-- The member an entry names, whoever declares it: a method by its selector and whether it is a class's or an instance's,
-- a property by its name, or by its getter's selector - a class property (+[NSString readableTypeIdentifiersForItemProvider])
-- is the class's, and an instance property the instance's.
local function member_matches(member, node)
    if node.kind ~= "ObjCMethodDecl" and node.kind ~= "ObjCPropertyDecl" then
        return false
    end
    if member.selector then
        if node.kind == "ObjCMethodDecl" then
            return node.name == member.selector and (node.instance ~= false) == (member.sign == "-")
        end
        -- a property is its getter's declaration; its setter has one of its own, implicit or written apart
        return node.name == member.selector and (node.class == true) == (member.sign == "+")
    end
    return node.kind == "ObjCPropertyDecl" and node.name == member.property
        or node.kind == "ObjCMethodDecl" and (node.name == member.property or setter_property(node.name) == member.property)
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
        return owner_of(node) == member.owner and member_matches(member, node)
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

-- Every header of the frameworks read, and every header of the SDK's usr/include: where a type's uses are looked for.
-- A use left out of them would not keep its type where it is, and the type would come down past API that is not
-- implemented; a use in a header the dump does not reach cannot be told, and keeps it.
local function header_files(sdk, frameworks)
    local files = {}
    for _, framework in ipairs(frameworks) do
        table.join2(files, os.files(path.join(sdk, "System", "Library", "Frameworks", framework .. ".framework", "Headers", "*.h")))
    end
    table.join2(files, os.files(path.join(sdk, "usr", "include", "**.h")))
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

-- The declaration of a member from its AST node, as a category would repeat for a class what a protocol it conforms to
-- or a superclass declares, or an interface would declare a property's setter apart from it: the member's own type, a
-- property's own attributes, and for a method whether it is a class's and its selector's parts paired in order with its
-- parameters. nil where the text would not be the SDK's declaration: a property whose type needs a declarator around
-- its name (a block or a function pointer), or a type that still carries an attribute the release does not replace.
function member_declaration(member, name, target)
    -- API_AVAILABLE(...) may nest parens (ios(8.0)), so the balanced match %b() is stripped, not [^)]*: it is the mark
    -- target replaces
    local function typed(field)
        return (((field or {}).qualType or "void"):gsub("^API_AVAILABLE%b()%s*", ""))
    end
    local types = {typed(member.type or member.returnType)}
    for _, child in ipairs(member.inner or {}) do
        if child.kind == "ParmVarDecl" then
            table.insert(types, typed(child.type))
        end
    end
    for _, type in ipairs(types) do
        if type:find("^[%u_]+%b()") then
            return nil
        end
    end
    if member.kind == "ObjCPropertyDecl" then
        local type = typed(member.type)
        if type:find("%(%s*[%^%*]") then
            return nil
        end
        local attributes = {}
        for _, attribute in ipairs({"class", "nonatomic", "atomic", "readonly", "readwrite", "copy", "strong", "weak",
                                    "assign", "retain", "unsafe_unretained", "null_resettable"}) do
            if member[attribute] then
                table.insert(attributes, attribute)
            end
        end
        for _, accessor in ipairs({"getter", "setter"}) do
            if member[accessor] and member[accessor].name then
                table.insert(attributes, accessor .. "=" .. member[accessor].name)
            end
        end
        return string.format("@property (%s) %s %s API_AVAILABLE(ios(%s));", table.concat(attributes, ", "), type, name, target)
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
    return string.format("%s (%s)%s API_AVAILABLE(ios(%s));", member.instance and "-" or "+", typed(member.returnType),
                         table.concat(parts, " "), target)
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
-- Where the C declaration that takes in byte position of code starts: after the ";", "{" or "}" that ends the one
-- before it, an @end, or a directive's line.
function statement_start(code, position)
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
    return start
end

function statement_words(code, position)
    local start = statement_start(code, position)
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
    local function standalone(name)
        local probe = path.join(opt.outputdir, "standalone.m")
        io.writefile(probe, string.format("#include <%s>\n", name))
        return try {function ()
            os.runv(opt.clang, {"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot", "-fsyntax-only",
                                "-x", "objective-c", probe})
            return true
        end} == true
    end
    local system = system_headers(opt.sdk, symbols, standalone)
    local dump, umbrella = dumper(opt, frameworks, system)
    local conforms = conformer(opt, umbrella)
    local languages = languages_of(opt)
    local expand = expander(opt, header_files(opt.sdk, frameworks), languages)
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

    local edits, blocked, targets, unmatched = {}, {}, {}, {}
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
    local setters, unwritable = {}, {}
    for api in pairs(kept) do
        local member = member_api(api)
        if member and member.selector and member.selector:find(":$") then
            for _, node in ipairs(dump(filter_of(listed[api]))) do
                if node.kind == "ObjCMethodDecl" and node.isImplicit and matches(listed[api], node) then
                    for _, mark in ipairs(marks(node)) do
                        local at = mark.line .. ":" .. mark.col
                        if edits[mark.file] and edits[mark.file][at] and not blocked[mark.file .. ":" .. at] then
                            setters[mark.file .. ":" .. at] = member_declaration(node, node.name, mark.introduced)
                            if not setters[mark.file .. ":" .. at] then
                                table.insert(unwritable, string.format("%s cannot be declared apart from its property, whose mark it shares at %s:%s",
                                                                       api, mark.file, at))
                            end
                        end
                    end
                end
            end
        end
    end

    -- A member the registry names on a class that the SDK declares not on the class itself but where a use of the class
    -- reaches it: in a superclass (+[UICollectionViewLayout invalidationContextClass] for the flow layout), or as a
    -- requirement of a protocol the class conforms to (UIView's traitCollection is UITraitEnvironment's, NSString's item
    -- provider members are NSItemProviderReading's and NSItemProviderWriting's, conformed to by a category). Lowering that
    -- declaration would reach every class that inherits it or conforms, with or without a backport. Instead the member is
    -- redeclared on the class, in its own @interface - which every language that reads the class must read, or this
    -- fails by name - and is checked both ways below as any member the class declares is. The text is the SDK's declaration, read from its AST, so this does not guess one.
    -- Where the class reaches declarations that say different things, or one this cannot write as the SDK does, it fails
    -- by name. A member the SDK declares nowhere a use of its class reaches - not in this SDK at all (a later release's),
    -- a private method, one the SDK gives only a subclass or an unrelated class - has nothing to lower, and is named with
    -- where the SDK does declare it.
    local redeclared, resolved, undeclared, unreachable, accounted = {}, {}, {}, {}, {}
    local function declares(name, kind)
        for _, node in ipairs(dump(name)) do
            if node.kind == kind and node.name == name then
                return true
            end
        end
        return false
    end
    local function carried(api)
        return (listed[api] or {}).status == "implemented"
    end
    -- per member: the declarations a use of its owner reaches, those of protocols still to be asked about, and where else
    local pending, questions = {}, {}
    for _, api in ipairs(unmatched) do
        local member = member_api(api:gsub("%(%)$", ""))
        if member then
            local owner = member.owner
            local class = declares(owner, "ObjCInterfaceDecl")
            local receiver = class and owner .. " *" or declares(owner, "ObjCProtocolDecl") and "id<" .. owner .. ">" or nil
            local chain = {}
            for _, name in ipairs(class and superclasses(owner) or {}) do
                chain[name] = true
            end
            local found = {api = api, member = member, owner = owner, class = class, reached = {}, asked = {}, elsewhere = {}}
            local by_owner = {}
            for _, node in ipairs(dump(member.selector or member.property)) do
                local by = owner_of(node)
                if by and member_matches(member, node) then
                    by_owner[by] = by_owner[by] or {}
                    table.insert(by_owner[by], node)
                end
            end
            for _, by in ipairs(table.orderkeys(by_owner)) do
                -- a property is the declaration its implicit accessors come from; one only an accessor names is found
                -- by the property's own name
                local nodes, properties = {}, {}
                for _, node in ipairs(by_owner[by]) do
                    if node.kind == "ObjCPropertyDecl" then
                        table.insert(properties, node)
                    elseif not node.isImplicit then
                        table.insert(nodes, node)
                    end
                end
                if #properties == 0 and #nodes == 0 then
                    local name = by_owner[by][1].name
                    name = setter_property(name) or name
                    for _, node in ipairs(dump(name)) do
                        if node.kind == "ObjCPropertyDecl" and node.name == name and owner_of(node) == by then
                            table.insert(properties, node)
                        end
                    end
                    if #properties == 0 then
                        table.insert(unreachable, string.format("%s is an implicit accessor of %s whose property cannot be found", api, by))
                    end
                end
                table.join2(nodes, properties)
                if by == owner then
                    table.insert(unreachable, string.format("%s is declared by %s itself, and was not matched there", api, owner))
                elseif chain[by] then
                    table.join2(found.reached, nodes)
                elseif receiver and declares(by, "ObjCProtocolDecl") then
                    table.insert(questions, {receiver = receiver, protocol = by})
                    found.asked[#questions] = nodes
                    found.elsewhere[by] = true
                else
                    found.elsewhere[by] = true
                end
            end
            table.insert(pending, found)
        end
    end
    local conforming = conforms(questions)
    local members = {}
    for _, found in ipairs(pending) do
        for index, nodes in pairs(found.asked) do
            if conforming[index] then
                table.join2(found.reached, nodes)
                found.elsewhere[questions[index].protocol] = nil
            end
        end
        local api, owner = found.api, found.owner
        local entry = listed[api]
        if #found.reached == 0 then
            local elsewhere = table.orderkeys(found.elsewhere)
            table.insert(undeclared, #elsewhere == 0 and api .. " (declared nowhere)"
                                     or string.format("%s (declared only by %s)", api, table.concat(elsewhere, ", ")))
            accounted[api] = true
        elseif not found.class then
            table.insert(unreachable, string.format("%s is declared only by a protocol %s inherits, and a protocol takes no category", api, owner))
        else
            local target = opt.minimum
            if entry.minimum and later(entry.minimum, target) then
                target = entry.minimum
            end
            local texts, sources = {}, {}
            for _, node in ipairs(found.reached) do
                local by = owner_of(node)
                table.insert(sources, by)
                for _, child in ipairs(node.inner or {}) do
                    if child.kind:endswith("Attr") and child.kind ~= "AvailabilityAttr" then
                        table.insert(unreachable, string.format("%s is declared by %s with %s, which a redeclaration would not carry", api, by, child.kind))
                    end
                end
                local text = member_declaration(node, node.name, target)
                if text then
                    texts[text] = true
                else
                    table.insert(unreachable, string.format("%s is declared by %s in a form this cannot write again", api, by))
                end
                if node.kind == "ObjCPropertyDecl" then
                    -- a property brings both its accessors down: each has to be carried for the class
                    local sign = node.class and "+" or "-"
                    local getter = node.getter and node.getter.name or node.name
                    local setter = node.setter and node.setter.name or "set" .. node.name:sub(1, 1):upper() .. node.name:sub(2) .. ":"
                    local accessors = {string.format("%s[%s %s]", sign, owner, getter)}
                    if not node.readonly then
                        table.insert(accessors, string.format("%s[%s %s]", sign, owner, setter))
                    end
                    for _, accessor in ipairs(accessors) do
                        if not (carried(accessor) or carried(owner .. "." .. node.name) and not kept[accessor]) then
                            table.insert(unreachable, string.format("%s is %s's property %s, whose accessor %s is not carried",
                                                                    api, by, node.name, accessor))
                        end
                    end
                end
            end
            local written = table.orderkeys(texts)
            if #written > 1 then
                table.insert(unreachable, string.format("%s is declared differently by %s: %s", api,
                                                        table.concat(table.unique(sources), ", "), table.concat(written, " / ")))
            elseif #written == 1 then
                members[owner] = members[owner] or {}
                members[owner][written[1]] = true
                targets[api] = target
                resolved[api] = found.reached
                accounted[api] = true
            end
        end
    end
    for _, owner in ipairs(table.orderkeys(members)) do
        -- dump(owner) answers one entry per file that names the class, most a forward declaration (@class UIView;); the
        -- class's own @interface is the entry that carries its members, and they go in before its @end. Not into a
        -- category: Swift's importer takes the requirement of a protocol that @interface adopts over a category's
        -- redeclaration of the same method on the class (UIView's -traitCollectionDidChange: stays UITraitEnvironment's,
        -- introduced in iOS 8), where it takes a redeclaration in the @interface itself.
        local interface
        for _, node in ipairs(dump(owner)) do
            if node.kind == "ObjCInterfaceDecl" and node.name == owner then
                for _, member in ipairs(node.inner or {}) do
                    if member.kind == "ObjCMethodDecl" or member.kind == "ObjCPropertyDecl" or member.kind == "ObjCIvarDecl" then
                        interface = node
                        break
                    end
                end
            end
        end
        local file = interface and (interface.loc or {}).file
        -- clang places the @interface's end at the "end" after the "@", and a location in a macro has no offset of its own
        local ending = file and ((interface.range or {})["end"] or {}).offset
        local content = ending and io.readfile(file)
        if content and interface.loc.offset and content:sub(ending, ending + 3) == "@end" then
            redeclared[file] = redeclared[file] or {}
            table.insert(redeclared[file], {owner = owner, name = interface.loc.offset, at = ending - 1,
                                            text = table.concat(table.orderkeys(members[owner]), "\n") .. "\n"})
        elseif file then
            table.insert(unreachable, string.format("the @end of the @interface of %s in %s is not where clang places it", owner,
                                                    path.relative(file, opt.sdk)))
        else
            table.insert(unreachable, string.format("the own header of %s, which would carry what it redeclares, cannot be found", owner))
        end
    end
    -- what is redeclared is matched on its class from here on, and what the SDK declares nowhere the class reaches is
    -- named; anything else stays unmatched, and the check for silent members below still sees it
    local left = {}
    for _, api in ipairs(unmatched) do
        if not accounted[api] then
            table.insert(left, api)
        end
    end
    unmatched = left
    table.sort(undeclared)

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
        -- a member redeclared on its class names what the declaration it repeats names
        local nodes = table.join(resolved[entry.api] or {})
        for _, node in ipairs(dump(filter_of(entry))) do
            if matches(entry, node) then
                table.insert(nodes, node)
            end
        end
        for _, node in ipairs(nodes) do
            do
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
    local headers = header_files(opt.sdk, frameworks)
    local codes = {}
    local function code(file)
        codes[file] = codes[file] or code_of(io.readfile(file))
        return codes[file]
    end
    -- What keeps a type from coming down: every use of it in the headers read whose declaration is above the port's
    -- release and not implemented, and every use whose declaration cannot be told; and the latest minimum among the
    -- implemented ones. A typedef that names it (dispatch_qos_class_t is qos_class_t) is no use of its own: its uses
    -- are the type's. declared: the type's own declarations, which are no uses of it.
    local told = {}
    for name in pairs(named) do
        told[name] = true
    end
    local owners = {}
    for _, entries in pairs(redeclared) do
        for _, entry in ipairs(entries) do
            owners[entry.owner] = true
        end
    end
    local tokens, reached, own = preprocessed(opt, languages, table.keys(told), owners)
    -- Every language that reads a class whose members go into its @interface reads that @interface: a header whose own
    -- #if gave a language another @interface of the class would leave the language without them.
    for file, entries in pairs(redeclared) do
        local starts = line_starts(io.readfile(file))
        for _, entry in ipairs(entries) do
            local line = 1
            while starts[line + 1] and starts[line + 1] <= entry.name + 1 do
                line = line + 1
            end
            for _, language in ipairs(languages) do
                local lines = own[language.name].kept[file] or {}
                local reads = false
                for _, names in pairs(lines) do
                    reads = reads or names[entry.owner] or false
                end
                if reads and not (lines[line] or {})[entry.owner] then
                    table.insert(unreachable, string.format("%s reads the class %s in %s, but not from the @interface at line %d",
                                                            language.name, entry.owner, path.relative(file, opt.sdk), line))
                end
            end
        end
    end
    local function users(name, declared, seen)
        seen[name] = true
        local blocking, target = {}, opt.minimum
        for _, file in ipairs(headers) do
            local text = code(file)
            if text:find("%f[%w_]" .. name .. "%f[^%w_]") then
                local starts, lines = line_starts(text), text:split("\n", {strict = true})
                -- a mention no language keeps as a token, in a file the umbrella reaches, is none; its declaration's
                -- lines count together, as a macro called over several lines expands on its first
                local function dropped(index)
                    if not (reached[file] and told[name]) then
                        return false
                    end
                    local first = index
                    local start = statement_start(text, starts[index])
                    while first > 1 and starts[first] > start do
                        first = first - 1
                    end
                    for line = first, index do
                        if ((tokens[file] or {})[line] or {})[name] then
                            return false
                        end
                    end
                    return true
                end
                for index, line in ipairs(lines) do
                    if line:find("%f[%w_]" .. name .. "%f[^%w_]") and not line:trim():startswith("#") and not dropped(index) then
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
        for _, entry in ipairs(redeclared[file] or {}) do
            local line = 1
            while starts[line + 1] and starts[line + 1] <= entry.at + 1 do
                line = line + 1
            end
            table.insert(sites, {line = line, col = entry.at + 2 - starts[line], insert = entry.text, redeclares = entry.owner})
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
                if not site.redeclares then
                    lifted = lifted + 1
                end
            else
                local rewritten = lift_macro(site.use, site.target)
                local declarations = table.getn(table.keys(site.declarations))
                if rewritten == site.use and type(expanded[site]) == "table" then
                    rewritten = language_conditional(expanded[site], site.target, declarations, site.use) or site.use
                elseif rewritten == site.use and expanded[site] then
                    rewritten = lift_expansion(expanded[site], site.target, declarations) or site.use
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
                    -- back over the same lines, so every later mark's line still means what marks() found it to mean;
                    -- the lines a conditional adds stay with the last
                    local parts = (before .. rewritten .. after):split("\n", {strict = true})
                    for index = 1, site.count do
                        lines[site.line + index - 1] = index < site.count and parts[index] or table.concat(parts, "\n", index)
                    end
                    lifted = lifted + 1
                end
            end
        end
        local copy = path.join(opt.outputdir, "headers", path.relative(file, opt.sdk))
        local text = table.concat(lines, "\n")
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
    local failures = table.join(refusals, unwritable, unreachable)
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
    -- method or property the AST-dump filter should find under its owner's own qualified scope, whether or not that
    -- owner has a registry entry of its own (this lookup never consults listed[owner] - see matches()), or else in a
    -- superclass or a protocol the owner conforms to, where it is redeclared, or nowhere the owner reaches, where it is
    -- named in undeclared with where the SDK does declare it (above). A member still here matched none of those: that
    -- is not a gap in SDK coverage, it is this lookup failing to find something that is really there, and reporting it
    -- only inside a count nobody is required to look at is exactly the silent loss this checks against.
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
            undeclared = undeclared, types = lowered_types, kept_types = kept_types}
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
