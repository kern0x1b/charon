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
import("async.runjobs")
import("core.compress.lz4")
import("dyld")
import("backports")
import("compat")
import("cache")
import("multidump")

local function version(text)
    return (text or ""):gsub("_", ".")
end

local function later(a, b)
    return dyld.compare_versions(version(a), version(b)) > 0
end

-- The top-level objects of a JSON dump, which clang writes one after another.
local function objects(text)
    -- clang writes each top-level declaration as one object whose braces stand at the start of a line (everything nested
    -- is indented, and a newline inside a string is escaped): the objects are split there and decoded at once.
    return json.decode("[" .. text:gsub("\n}\n{", "\n},\n{") .. "]")
end

-- What a framework with no umbrella header keeps in folders below Headers: OpenGLES's ES1, ES2 and ES3, each the whole of one generation of
-- the API (ES3/gl.h declares what ES2/gl.h does, and 25 more that the backports carry). The newest is read, which declares what the older ones
-- do; the three together only redeclare, and each name would be found three times.
local function generation_headers(sdk, framework)
    local folder = path.join(sdk, "System", "Library", "Frameworks", framework .. ".framework", "Headers")
    local files = {}
    if not os.isfile(path.join(folder, framework .. ".h")) then
        local generations = os.dirs(path.join(folder, "*"))
        table.sort(generations)
        if #generations > 0 then
            files = os.files(path.join(generations[#generations], "*.h"))
            table.sort(files)
        end
    end
    return files
end

-- A framework's headers: its umbrella header where it has one, every header it has where it does not (CoreTelephony,
-- OpenGLES, whose newest generation is read as well).
local function framework_headers(sdk, framework)
    local folder = path.join(sdk, "System", "Library", "Frameworks", framework .. ".framework", "Headers")
    local umbrella = path.join(folder, framework .. ".h")
    local files = os.isfile(umbrella) and {umbrella} or os.files(path.join(folder, "*.h"))
    table.sort(files)
    return table.join(files, generation_headers(sdk, framework))
end

-- The public headers of the SDK's usr/include that bring in what charon@apple-compat carries: every file that names a
-- symbol followed by a paren outside a directive, as a module map reaches it - the file itself where a module map names
-- it as a header, the umbrella header of its folder where one covers the folder. A header a module map lists that another
-- header of the same map includes is left to that header when standalone(name) says it cannot be included alone
-- (dispatch/block.h refuses to be, and is reached through dispatch/dispatch.h): SDK 16.4's dispatch map names an umbrella,
-- 26.2's lists every dispatch header, block.h among them, and a symbol found in such a header brings the headers that
-- include it. Which of them declares the symbol is the dump's to say. A symbol no public header names - a compiler-rt intrinsic - brings none; the dump then finds no declaration of it.
function system_headers(sdk, symbols, standalone)
    local root = path.join(sdk, "usr", "include")
    local public, umbrellas, includers = {}, {}, {}
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
                    for _, key in ipairs({target, path.relative(path.join(path.directory(file), target), root)}) do
                        included[key] = true
                        includers[key] = includers[key] or {}
                        table.insert(includers[key], name)
                    end
                end
            end
        end
        for _, name in ipairs(listed) do
            if not included[name] or standalone(name) then
                public[name] = true
            end
        end
    end
    -- the headers a symbol found in `name` is reached through: itself where it is public, otherwise those that include it, and
    -- theirs in turn, or the umbrella header of its folder. An includer counts where the compiler reads it alone: libc++'s headers,
    -- which include the one a symbol is in, do not without their C++ include path, and are no header of this umbrella.
    local alone = {}
    local function stands(name)
        if alone[name] == nil then
            alone[name] = standalone(name)
        end
        return alone[name]
    end
    local function through(name, seen)
        local found = {}
        for _, includer in ipairs(includers[name] or {}) do
            if not seen[includer] then
                seen[includer] = true
                if public[includer] then
                    if stands(includer) then
                        table.insert(found, includer)
                    end
                else
                    table.join2(found, through(includer, seen))
                end
            end
        end
        return found
    end
    local function reached_through(name)
        if public[name] then
            return {name}
        end
        local found = through(name, {[name] = true})
        if #found == 0 and umbrellas[path.directory(name)] then
            found = {umbrellas[path.directory(name)]}
        end
        return found
    end
    local found = {}
    for _, file in ipairs(os.files(path.join(root, "**.h"))) do
        local text = io.readfile(file)
        for _, symbol in ipairs(symbols) do
            if text:find(symbol, 1, true) then
                for line in text:gmatch("[^\n]+") do
                    if not line:match("^%s*#") and line:find("%f[%w_]" .. symbol .. "%s*%(") then
                        for _, reached in ipairs(reached_through(path.relative(file, root))) do
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

-- system_headers() for this lift, kept on disk: it is a function of the SDK's own headers, the symbols, the compiler and the
-- target, and it costs a compile per header that cannot be told public from its module map alone (30 s of a 65 s lift of
-- three frameworks, measured). The key is every file under the SDK's usr/include by name, size and time, the symbols, the
-- compiler by path, size and time, the target, and this file's text - what system_headers() and stands_alone() read.
-- The environment a compiler reads, which the kept system headers, a kept answer and a kept lift are keyed on.
local ENVIRONMENT = {"CPATH", "C_INCLUDE_PATH", "OBJC_INCLUDE_PATH", "CPLUS_INCLUDE_PATH", "OBJCPLUS_INCLUDE_PATH",
                     "SDKROOT", "DEVELOPER_DIR", "IPHONEOS_DEPLOYMENT_TARGET", "CCC_OVERRIDE_OPTIONS", "CHARON_LIFT_MULTIDUMP",
                     "CHARON_LLVM_CONFIG"}

function kept_system_headers(opt, symbols)
    local root = path.join(opt.sdk, "usr", "include")
    local parts = {"charon-system-headers-1", opt.triple, opt.clang, tostring(os.filesize(opt.clang)), tostring(os.mtime(opt.clang)),
                   hash.strhash128(io.readfile(path.join(os.scriptdir(), "lift.lua"))), table.concat(symbols, " ")}
    -- what the probes compile reads the environment as the lift's own compiles do
    for _, name in ipairs(ENVIRONMENT) do
        table.insert(parts, name .. "=" .. (os.getenv(name) or ""))
    end
    local files = os.files(path.join(root, "**"))
    table.sort(files)
    for _, file in ipairs(files) do
        table.insert(parts, path.relative(file, root) .. " " .. hash.xxhash128(file))
    end
    local key = hash.strhash128(table.concat(parts, "\n"))
    local file = path.join(os.getenv("CHARON_HOME") or path.join(os.getenv("HOME"), ".charon"), "cache", "lift", "system-" .. key .. ".lua")
    local saved = os.isfile(file) and io.load(file)
    if saved then
        return saved.headers
    end
    local headers = system_headers(opt.sdk, symbols, function (name) return stands_alone(opt, name) end)
    try { function () os.mkdir(path.directory(file)) end }
    local temporary = file .. "." .. hash.strhash32(file .. os.mclock()) .. ".tmp"
    io.save(temporary, {headers = headers})
    os.mv(temporary, file)
    return headers
end

-- Whether a header can be included alone: the compiler reads `#include <name>` and finds an error in it or not. An error the compiler places in
-- a file (the header's, or one it includes) says it cannot, and so does one of its own includes it cannot find (a libc++ header needs its C++ include path, which it does not
-- have here). A compiler that does not run, a crash, or the probed header not being there at all raise, because answering "cannot"
-- for them would leave the header to its includer for the wrong reason. opt.clang, opt.triple, opt.sdk, and opt.outputdir for the
-- probe file.
function stands_alone(opt, name)
    local probe = path.join(opt.outputdir, "standalone.m")
    local errors = path.join(opt.outputdir, "standalone.err")
    io.writefile(probe, string.format("#include <%s>\n", name))
    local status, launch = cache.execv(opt.clang, {"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot", "-fsyntax-only",
                                                "-ferror-limit=0", "-x", "objective-c", probe}, {try = true, stderr = errors})
    local diagnostics = os.isfile(errors) and io.readfile(errors) or ""
    if status == 0 then
        return true
    end
    local absent, crashed, located = false, diagnostics:find("PLEASE submit a bug report", 1, true) or diagnostics:find("Stack dump", 1, true), false
    for line in diagnostics:gmatch("[^\n]+") do
        if line:startswith(probe .. ":") and line:find("file not found", 1, true) then
            absent = true
        end
        -- an error of a header is told by where it is (file:line:column); the driver's (a triple it does not know) has no place in a file
        if line:find(":%d+:%d+: [%a ]*error: ") then
            located = true
        end
    end
    if status == nil or crashed or absent or not located then
        raise("the probe of %s did not end in an error of the header (%s): %s", name, tostring(launch or status), diagnostics)
    end
    return false
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

-- The names split into runs of the sorted list that share a prefix of at least GROUP_PREFIX characters, at most GROUP_SIZE to a
-- run: {prefix = the prefix all of a run's names share, names = them}. A name that shares none with its neighbours is a run of its own.
-- Six characters keep a group to one family of an SDK (the 2807 functions, constants and types of the registry make 458 groups; a prefix
-- of "NS" or "UI" would be most of Foundation and UIKit in one dump), and forty bound what one dump holds.
local GROUP_PREFIX, GROUP_SIZE = 6, 40
function name_groups(names)
    local sorted = table.join(names)
    table.sort(sorted)
    local groups, current, prefix = {}, {}, nil
    for _, name in ipairs(sorted) do
        local shared = 0
        if prefix then
            while shared < math.min(#prefix, #name) and prefix:byte(shared + 1) == name:byte(shared + 1) do
                shared = shared + 1
            end
        end
        if prefix and shared >= GROUP_PREFIX and #current < GROUP_SIZE then
            table.insert(current, name)
            prefix = prefix:sub(1, shared)
        else
            if prefix then
                table.insert(groups, {prefix = prefix, names = current})
            end
            current, prefix = {name}, name
        end
    end
    if prefix then
        table.insert(groups, {prefix = prefix, names = current})
    end
    return groups
end

local OUTPUTDIR = "@charon-lift-outputdir@"

-- every string of value with from replaced by to, tables walked
local function respelled(value, from, to)
    if type(value) == "string" then
        -- in pieces, joined once: a dump names the umbrella at every declaration, and rebuilding the string at each was
        -- quadratic in its length
        local pieces, from_at = {}, 1
        local at = value:find(from, 1, true)
        if not at then
            return value
        end
        while at do
            table.insert(pieces, value:sub(from_at, at - 1))
            table.insert(pieces, to)
            from_at = at + #from
            at = value:find(from, from_at, true)
        end
        table.insert(pieces, value:sub(from_at))
        return table.concat(pieces)
    elseif type(value) == "table" then
        local copy = {}
        for key, item in pairs(value) do
            copy[respelled(key, from, to)] = respelled(item, from, to)
        end
        return copy
    end
    return value
end

-- The output folder's path spelled as a mark in a kept file, and back: as it is, and as JSON writes it (vfs.yaml, where every
-- "/" is "\/"), so that no spelling of the folder a lift was run in is left in what another folder is given.
local function unplaced(text, outputdir)
    return respelled(respelled(text, (outputdir:gsub("/", "\\/")), OUTPUTDIR .. "json"), outputdir, OUTPUTDIR)
end
local function placed(text, outputdir)
    return respelled(respelled(text, OUTPUTDIR .. "json", (outputdir:gsub("/", "\\/"))), OUTPUTDIR, outputdir)
end

-- What an SDK's headers are, by name and content (7153 headers of SDK 26.2 in 0.2 s), read once per lift: lift() empties
-- the table, so that headers rewritten between two lifts of one process - as a test rewrites its fixture - are read again.
-- Not by size and time, which a header rewritten to the same length within a second does not change.
local stamps = {}
function sdk_stamp(sdk)
    if not stamps[sdk] then
        local headers = table.join(os.files(path.join(sdk, "**.h")), os.files(path.join(sdk, "usr", "include", "**.modulemap")))
        table.sort(headers)
        local parts = {sdk}
        for _, file in ipairs(headers) do
            table.insert(parts, path.relative(file, sdk) .. " " .. hash.xxhash128(file))
        end
        stamps[sdk] = hash.strhash128(table.concat(parts, "\n"))
    end
    return stamps[sdk]
end

local function dumper(opt, frameworks, headers)
    local umbrella = path.join(opt.outputdir, "umbrella.m")
    local lines = {}
    -- Foundation first, and for a reason: the macro a redeclaration writes for a swift_private property and
    -- API_AVAILABLE are both declared in NSObjCRuntime.h, which a header that imports only its own framework
    -- does not reach. A lifted header is written under the same umbrella this is, so this is where that scope
    -- comes from - not from the header's own imports, which are the SDK's business and not ours to widen.
    table.insert(lines, "#import <Foundation/Foundation.h>")
    for _, framework in ipairs(frameworks) do
        local folder = path.join(opt.sdk, "System", "Library", "Frameworks", framework .. ".framework", "Headers")
        for _, header in ipairs(framework_headers(opt.sdk, framework)) do
            table.insert(lines, string.format("#import <%s/%s>", framework, path.relative(header, folder)))
        end
    end
    for _, header in ipairs(headers) do
        table.insert(lines, string.format("#include <%s>", header))
    end
    io.writefile(umbrella, table.concat(lines, "\n") .. "\n")
    -- What a query on the umbrella runs: the parse of all of it, most of what one costs. (Read back precompiled it gives
    -- less: an @interface's members and categories are loaded lazily and not all dumped.)
    local function base(vfs)
        local arguments = {"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot", "-fsyntax-only", "-x", "objective-c", umbrella}
        if vfs then
            table.join2(arguments, {"-ivfsoverlay", vfs})
        end
        return arguments
    end
    -- what was asked, counted as it is asked: the lift reads it when it ends
    local asked, runs = {}, 0
    local counted = {filters = 0, runs = 0, frameworks = #frameworks, parses = 0, clang = 0, decode = 0, bytes = 0, prefetch = 0, prefetches = 0, recalled = 0}
    local function note(filter, cost)
        if not asked[filter] then
            asked[filter] = true
            counted.filters = counted.filters + 1
        end
        runs = runs + cost
        counted.runs = runs
    end
    -- What a query found: the JSON dump's declarations, each with the qualified name and the typedefs the text dump of the
    -- same filter heads it with.
    local function answered(filter, text, listing)
        if not text or not listing then
            raise("clang gave no dump for the filter %s", filter)
        end
        local started = os.mclock()
        counted.bytes = counted.bytes + #text + #listing
        local found = objects(text)
        -- The JSON names no owner; the text dump of the same filter heads each declaration with its qualified name, in
        -- the same order. With the declaration's type written after it (-ast-dump-decl-types: a function's, a variable's,
        -- a typedef's own), it also names every typedef that type goes through - a return type, a parameter's, and the
        -- typedef a typedef names in turn (dispatch_qos_class_t, then qos_class_t) - which the JSON gives no way to follow.
        local sections = listing_sections(listing)
        if #sections == #found then
            for index, node in ipairs(found) do
                node._qualified = sections[index].heading
                node._typedefs = sections[index].typedefs
            end
        end
        counted.decode = counted.decode + os.mclock() - started
        return found
    end
    -- The two dumps of one filter, as clang prints them for it on its own: two parses of the umbrella.
    local function asked_alone(filter, vfs)
        note(filter, 2)
        local arguments = table.join(base(vfs), {"-Xclang", "-ast-dump-filter=" .. filter})
        return cache.iorunv(opt.clang, table.join(arguments, {"-Xclang", "-ast-dump=json"})),
               cache.iorunv(opt.clang, table.join(arguments, {"-Xclang", "-ast-dump", "-Xclang", "-ast-dump-decl-types"}))
    end
    -- The two dumps of every filter of a list, from one parse (multidump.lua), or nil where there is no plugin.
    local batches = 0
    local function asked_together(filters, vfs)
        local dylib = multidump.plugin(opt.clang)
        if not dylib then
            return nil
        end
        batches = batches + 1
        for index, filter in ipairs(filters) do
            note(filter, index == 1 and 1 or 0)
        end
        local folder = path.join(opt.outputdir, "multidump", tostring(batches) .. "-" .. hash.strhash32(filters[1] .. os.mclock()))
        os.mkdir(folder)
        local list = path.join(folder, "filters.txt")
        io.writefile(list, table.concat(filters, "\n") .. "\n")
        local started = os.mclock()
        os.iorunv(opt.clang, multidump.arguments(dylib, base(vfs), list, folder))
        counted.parses = counted.parses + 1
        counted.clang = counted.clang + os.mclock() - started
        local answers = {}
        for index = 1, #filters do
            answers[index] = {io.readfile(path.join(folder, index .. ".json")), io.readfile(path.join(folder, index .. ".txt"))}
        end
        os.tryrm(folder)
        return answers
    end
    -- What the plugin answered for a filter over the umbrella alone, kept between lifts: an answer is what clang prints for
    -- the umbrella's parse, and depends on the umbrella's text, the SDK's headers, the compiler, the plugin and the
    -- environment the compiler reads - not on the registry or on this file. A lift after a change to the registry asks
    -- again only what it did not ask before. The folder the umbrella is in is spelled as a mark, as in a kept result;
    -- a query over an overlay is not kept (the overlay is the lift's own output).
    local held
    do
        local dylib = multidump.plugin(opt.clang)
        if dylib and opt.keep then
            local parts = {"charon-lift-dumps-1", io.readfile(umbrella), sdk_stamp(opt.sdk), opt.triple, dylib,
                           opt.clang .. " " .. tostring(os.filesize(opt.clang)) .. " " .. tostring(os.mtime(opt.clang))}
            for _, name in ipairs(ENVIRONMENT) do
                table.insert(parts, name .. "=" .. (os.getenv(name) or ""))
            end
            held = path.join(os.getenv("CHARON_HOME") or path.join(os.getenv("HOME"), ".charon"), "cache", "lift",
                             "dumps-" .. hash.strhash128(table.concat(parts, "\n")))
        end
    end
    if held then
        try { function () os.mkdir(held) end }
        io.writefile(path.join(held, "used"), "")
    end
    -- The plugin's answers are compared with clang's own before any of them is used, on up to three filters of the first
    -- batch of different kinds (the first, a class's members, a plain name): a plugin built against headers that are not
    -- exactly the lift's clang's could print something else, and then it is not used again and every query is asked
    -- alone. Where its answers are kept, that they agreed is kept with them (a set of answers is a function of the plugin,
    -- the umbrella, the SDK, the target and the environment, as its key is), and the answers of that set are not
    -- compared again; a lift that keeps nothing compares once per run.
    local agrees = held and path.join(held, "agrees")
    local checked = agrees and os.isfile(agrees) or false
    local together
    local function asked_checked(filters, vfs)
        local answers = asked_together(filters, vfs)
        if answers and not checked then
            checked = true
            local compared, seen = {}, {}
            local function pick(index)
                if index and not seen[index] then
                    seen[index] = true
                    table.insert(compared, index)
                end
            end
            pick(1)
            for index, filter in ipairs(filters) do
                if filter:find("::", 1, true) then pick(index); break end
            end
            for index, filter in ipairs(filters) do
                if index ~= 1 and filter:find("^[%a_][%w_]*$") then pick(index); break end
            end
            local function same(a, b)
                return a and b and a:gsub("0x%x+", "") == b:gsub("0x%x+", "")
            end
            for _, index in ipairs(compared) do
                local text, listing = asked_alone(filters[index], vfs)
                if not same(text, answers[index][1]) or not same(listing, answers[index][2]) then
                    cprint("${color.warning}lift:${clear} the multidump plugin does not answer %s as clang does; every query is asked alone", filters[index])
                    multidump.refuse()
                    return nil
                end
            end
            if agrees then
                local names = {}
                for _, index in ipairs(compared) do
                    table.insert(names, filters[index])
                end
                io.writefile(agrees, table.concat(names, "\n") .. "\n")
            end
        end
        return answers
    end
    local function held_file(filter)
        return path.join(held, hash.strhash128(filter) .. ".lz4")
    end
    local function recalled(filter)
        local file = held_file(filter)
        if not os.isfile(file) then
            return nil
        end
        local text = placed(lz4.decompress(io.readfile(file, {encoding = "binary"})):str(), opt.outputdir)
        local split = text:find("\0", 1, true)
        return split and {text:sub(1, split - 1), text:sub(split + 1)} or nil
    end
    local function remember(filter, answer)
        if not answer[1] or not answer[2] then
            return
        end
        local file = held_file(filter)
        try { function () os.mkdir(held) end }
        local temporary = file .. "." .. hash.strhash32(file .. os.mclock()) .. ".tmp"
        io.writefile(temporary, lz4.compress(unplaced(answer[1] .. "\0" .. answer[2], opt.outputdir)):str(), {encoding = "binary"})
        os.mv(temporary, file)
    end
    together = function (filters, vfs)
        if vfs or not held then
            return asked_checked(filters, vfs)
        end
        local answers, missing, at = {}, {}, {}
        for index, filter in ipairs(filters) do
            answers[index] = recalled(filter)
            if answers[index] then
                counted.recalled = counted.recalled + 1
            else
                table.insert(missing, filter)
                at[#missing] = index
            end
        end
        if #missing > 0 then
            local asked = asked_checked(missing, vfs)
            if not asked then
                return nil
            end
            for position, answer in ipairs(asked) do
                answers[at[position]] = answer
                remember(missing[position], answer)
            end
        end
        return answers
    end
    local function query(filter, vfs)
        local answers = together({filter}, vfs)
        if answers then
            return answered(filter, answers[1][1], answers[1][2])
        end
        local text, listing = asked_alone(filter, vfs)
        return answered(filter, text, listing)
    end
    local dumps, alone = {}, {}
    -- While collecting, a dump not held yet is noted instead of asked, and answers nothing: a loop run once that way names
    -- the queries it will make, and they are then asked together (prefetch) before it runs for real.
    local collecting
    local function collect(on)
        local noted = collecting
        collecting = on and {} or nil
        return noted and table.orderkeys(noted) or {}
    end
    local function dump(filter, vfs)
        local key = filter .. "|" .. (vfs or "")
        if not dumps[key] and collecting and not vfs then
            collecting[filter] = true
            return {}
        end
        if not dumps[key] then
            table.insert(alone, key)
            dumps[key] = query(filter, vfs)
        end
        return dumps[key]
    end
    -- What a declaration's subtree names, all in one string: a name a filter finds only below a declaration that does not match
    -- itself.
    local function nested_names(node)
        local names = {}
        local function walk(item)
            if type(item) == "table" then
                if type(item.name) == "string" then
                    table.insert(names, item.name)
                end
                for _, value in pairs(item) do
                    walk(value)
                end
            end
        end
        for _, child in ipairs(node.inner or {}) do
            walk(child)
        end
        return table.concat(names, "\0")
    end
    -- The queries a loop is about to make, asked at once and in parallel: what the loop then reads is the answer it would have had,
    -- from the cache. Names that are one identifier (a function, a constant, a type) are asked for by the prefix a group of them
    -- shares, one query for the group: clang prints, for a filter, the outermost declarations whose qualified name contains it,
    -- so what a name's own query prints is those of the group's that contain the name - unless the name is found only below a
    -- declaration of the group that does not contain it, and then it is asked for on its own. What is asked one at a time is
    -- kept in `alone`, to see what a loop still lacks a prefetch for.
    local prefetch_inner
    local function prefetch(filters, vfs)
        local started = os.mclock()
        prefetch_inner(filters, vfs)
        counted.prefetch = counted.prefetch + os.mclock() - started
        counted.prefetches = counted.prefetches + 1
    end
    prefetch_inner = function (filters, vfs)
        local missing, seen, plain, names = {}, {}, {}, {}
        for _, filter in ipairs(filters) do
            local key = filter .. "|" .. (vfs or "")
            if not dumps[key] and not seen[key] then
                seen[key] = true
                table.insert(filter:find("^[%a_][%w_]*$") and names or plain, filter)
            end
        end
        local jobs = {}
        for _, filter in ipairs(plain) do
            table.insert(jobs, {filter = filter})
        end
        -- With the plugin every filter of a batch is answered from the batch's one parse, and a group saves nothing: it
        -- only makes the answer larger (a prefix of six characters is every declaration that contains it)
        local grouped = opt.grouped ~= false and not multidump.plugin(opt.clang)
        for _, group in ipairs(name_groups(names)) do
            if not grouped then
                for _, name in ipairs(group.names) do
                    table.insert(jobs, {filter = name})
                end
            else
                table.insert(jobs, {filter = group.prefix, names = #group.names > 1 and group.names or nil})
            end
        end
        local answers = {}
        local function ask(wanted)
            -- With the plugin, the queries go in batches, each one parse: as many batches as runs at once. A parse is a
            -- second whatever it is asked, and what it writes for each filter is a fraction of that (measured over the
            -- overlay: 1500 filters in one parse 3.0 s, a bare parse 1.0 s), so a batch is as large as the width allows.
            local width = opt.jobs or 8
            if #wanted > 1 and multidump.plugin(opt.clang) then
                local size = math.max(1, math.ceil(#wanted / width))
                local groups = {}
                for first = 1, #wanted, size do
                    table.insert(groups, first)
                end
                -- the first batch alone, so that the check against clang's own answer is made before the others run, until
                -- it has been made
                local order = checked and {} or {groups[1]}
                local rest = {}
                for index = checked and 1 or 2, #groups do
                    table.insert(rest, groups[index])
                end
                local function batch(first)
                    local filters = {}
                    for index = first, math.min(first + size - 1, #wanted) do
                        table.insert(filters, wanted[index].filter)
                    end
                    local found = together(filters, vfs)
                    for offset, filter in ipairs(filters) do
                        answers[first + offset - 1] = found and answered(filter, found[offset][1], found[offset][2]) or query(filter, vfs)
                    end
                end
                if order[1] then
                    batch(order[1])
                end
                runjobs("dump", function (index)
                    batch(rest[index])
                end, {total = #rest, comax = width})
                return
            end
            runjobs("dump", function (index)
                answers[index] = query(wanted[index].filter, vfs)
            end, {total = #wanted, comax = width})  -- 96 queries: 71 s one at a time, 12.7 s at 8, 11.6 s at 10 (12 cores)
        end
        ask(jobs)
        local again = {}
        for index, job in ipairs(jobs) do
            local answer = answers[index]
            local reliable = true
            for _, node in ipairs(answer) do
                reliable = reliable and node._qualified ~= nil
            end
            if not job.names then
                dumps[job.filter .. "|" .. (vfs or "")] = answer
            elseif not reliable then
                for _, name in ipairs(job.names) do
                    table.insert(again, {filter = name})
                end
            else
                local below = {}
                for _, name in ipairs(job.names) do
                    local found, hidden = {}, false
                    for position, node in ipairs(answer) do
                        if node._qualified:find(name, 1, true) then
                            table.insert(found, node)
                        else
                            below[position] = below[position] or nested_names(node)
                            hidden = hidden or below[position]:find(name, 1, true) ~= nil
                        end
                    end
                    if hidden then
                        table.insert(again, {filter = name})
                    else
                        dumps[name .. "|" .. (vfs or "")] = found
                    end
                end
            end
        end
        if #again > 0 then
            answers = {}
            ask(again)
            for index, job in ipairs(again) do
                dumps[job.filter .. "|" .. (vfs or "")] = answers[index]
            end
        end
    end
    -- What the dumper spent its time on, by count: the filters are the unit of work, each one two
    -- clang runs over the whole umbrella, and a grouped filter covers a prefix of names. The
    -- per-framework breakdown is the umbrella's own, and a lift's cost does not follow it - a
    -- framework with few registry entries is read in full and lifted in none.
    return dump, umbrella, prefetch, alone, counted, collect
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
        local _, diagnostics = cache.iorunv(opt.clang, {"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot",
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
    -- every language's preprocessing at once: each is a compile of the umbrella, and they do not depend on each other
    local texts = {}
    runjobs("preprocess", function (index)
        texts[index] = cache.iorunv(opt.clang, table.join({"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot", "-E"},
                                                       languages[index].arguments, {path.join(opt.outputdir, "umbrella.m")}))
    end, {total = #languages, comax = math.max(1, math.min(#languages, opt.jobs or 8))})
    for index, language in ipairs(languages) do
        if apart then
            own[language.name] = {kept = {}, reached = {}}
        end
        tokens_kept(texts[index], wanted, kept, reached, apart, apart and own[language.name].kept, apart and own[language.name].reached)
    end
    return kept, reached, own
end

-- The names of wanted a preprocessor's output (clang -E, with its line markers) keeps as tokens, by the file and line
-- each came from: added to kept[file][line][name], and every file it names to reached.
-- A second set of names (apart, into apart_kept and apart_reached) is told in the same pass, as if tokens_kept were called
-- again with it: the output is read once for both.
function tokens_kept(text, wanted, kept, reached, apart, apart_kept, apart_reached)
    local file, line
    for output in (text .. "\n"):gmatch("([^\n]*)\n") do
        local number, marked = output:match('^# (%d+) "([^"]*)"')
        if number then
            file, line = marked, tonumber(number)
            reached[file] = true
            if apart_reached then
                apart_reached[file] = true
            end
        elseif file then
            -- code_of() gives back a line with no comment or literal in it unchanged, and most lines of clang -E have
            -- neither: those are read as they are
            for word in (output:find("[/\"']") and code_of(output) or output):gmatch("[%a_][%w_]*") do
                if wanted[word] then
                    kept[file] = kept[file] or {}
                    kept[file][line] = kept[file][line] or {}
                    kept[file][line][word] = true
                end
                if apart and apart[word] then
                    apart_kept[file] = apart_kept[file] or {}
                    apart_kept[file][line] = apart_kept[file][line] or {}
                    apart_kept[file][line][word] = true
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
        local text = cache.iorunv(opt.clang, table.join({"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot",
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
        local forms, texts = {}, {}
        -- every language at once, read back in the languages' order
        runjobs("expand", function (index)
            texts[index] = cache.iorunv(opt.clang, table.join({"-target", opt.triple, "-isysroot", opt.sdk, "-Wno-incompatible-sysroot",
                                                            "-E", "-P"}, languages[index].arguments,
                                                           {path.join(opt.outputdir, "umbrella.m"), "-ivfsoverlay", vfs}))
        end, {total = #languages, comax = math.max(1, math.min(#languages, opt.jobs or 8))})
        for position, language in ipairs(languages) do
            local text = texts[position]
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

-- The property whose declared getter is this selector: `isFoo` is the getter `foo` is declared with, and `Foo` is
-- the getter of a class property of that name. Only a candidate - nothing here decides that a property *is* the one,
-- which is the property's own `getter` the caller checks.
function getter_property(selector)
    local first, rest = selector:match("^is(%a)([%w_]*)$")
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

-- An entry's own name without a trailing "(", and the member it names if it names one. Both
-- depend on the entry alone, and matches() is called once per node of the entry's dump - a dump
-- of a class prefix is thousands of nodes - so computing them per node is the single largest
-- thing the entries loop does: a string substitution and a table built and thrown away for every
-- (entry, node) pair, which is what made the loop 64 per cent of a lift. Kept on the entry, so
-- every call site gets them and none of them changes what is matched.
local function api_of(entry)
    if entry.name == nil then
        local api = entry.api:gsub("%(%)$", "")
        entry.name = api
        entry.member = member_api(api)
    end
    return entry.name, entry.member
end

local function matches(entry, node)
    local api, member = api_of(entry)
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

-- The nodes of a dump that can match an entry, in the dump's order: for a member, those whose name is its selector, its
-- property or the setter of its property - the only names member_matches() accepts - and every node for anything else.
-- A dump of a class's members is thousands of nodes and the class has hundreds of entries, and each entry looked at every
-- node: the entries loops were most of a lift. The index is built once per dump, and matches() still decides.
local indexes = {}
local function candidates(entry, nodes)
    local _, member = api_of(entry)
    if not member then
        return nodes
    end
    local index = indexes[nodes]
    if not index then
        index = {}
        for position, node in ipairs(nodes) do
            for _, name in ipairs({node.name, node.name and setter_property(node.name) or nil}) do
                index[name] = index[name] or {}
                table.insert(index[name], position)
            end
        end
        indexes[nodes] = index
    end
    local positions, seen = {}, {}
    for _, name in ipairs(member.selector and {member.selector} or {member.property}) do
        for _, position in ipairs(index[name] or {}) do
            if not seen[position] then
                seen[position] = true
                table.insert(positions, position)
            end
        end
    end
    table.sort(positions)
    local found = {}
    for _, position in ipairs(positions) do
        table.insert(found, nodes[position])
    end
    return found
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
        table.join2(files, os.files(path.join(sdk, "System", "Library", "Frameworks", framework .. ".framework", "Headers", "*.h")), generation_headers(sdk, framework))
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
-- The attributes a declaration node carries, by clang's own kind, and the ones a redeclaration here cannot carry.
-- AvailabilityAttr is written by member_declaration() itself, and SwiftPrivateAttr is written as the macro the SDK
-- spells, so both are carried; every other attribute is a fact about the declaration this cannot repeat, and a
-- redeclaration without it would say something the SDK does not.
local function attributes_of(node)
    local found = {}
    for _, child in ipairs((node or {}).inner or {}) do
        if child.kind and child.kind:endswith("Attr") then
            table.insert(found, child.kind)
        end
    end
    return found
end

local CARRIED_ATTRIBUTES = {AvailabilityAttr = true, SwiftPrivateAttr = true}

function uncarried_attributes(node)
    local left = {}
    for _, kind in ipairs(attributes_of(node)) do
        if not CARRIED_ATTRIBUTES[kind] then
            table.insert(left, kind)
        end
    end
    return left
end

local function has_attribute(node, kind)
    for _, each in ipairs(attributes_of(node)) do
        if each == kind then
            return true
        end
    end
    return false
end

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
        -- A property the SDK declares swift_private is one Swift must not see by its own name, and a redeclaration
        -- that dropped the attribute would show Swift a member of a name it does not have. NS_REFINED_FOR_SWIFT
        -- expands to __attribute__((swift_private)), so it goes AFTER the declarator, beside API_AVAILABLE and not
        -- inside the property's own attribute list, where clang reads the expansion as an unknown property attribute.
        -- The fact is clang's attribute kind; what is written is the macro's name, as a header spells it.
        local refined = has_attribute(member, "SwiftPrivateAttr") and "NS_REFINED_FOR_SWIFT " or ""
        return string.format("@property (%s) %s %s %sAPI_AVAILABLE(ios(%s));", table.concat(attributes, ", "), type,
                             name, refined, target)
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
-- opt.registry (the folder holding registry/), opt.outputdir; opt.jobs, the compiler runs at once (8), and opt.grouped = false, which
-- asks for every name on its own, not by the prefix a group of them shares (the reference the grouping is checked against).
-- Answers the VFS overlay to hand the compiler and what was done; raises when either check finds a difference.
local function computed(opt)
    -- Where the time went, per phase, in this run's own output. A lift is the slowest job on this
    -- machine and until now it reported only its total, so the only way to see which phase that
    -- total was made of was to sample the process tree from outside - which is not a number two
    -- runs can be compared on, and which cannot say which framework or which filter cost what. The
    -- per-phase marks below are the four calls that can each take minutes; the per-filter counts
    -- come from the dumper, which already knows how many it asked.
    local marked = os.getenv("LIFT_PROFILE") and {} or nil
    local phase = marked and os.mclock() or 0
    local counted
    local function mark(name)
        if not marked then
            return
        end
        local now = os.mclock()
        marked[#marked + 1] = {name, (now - phase) / 1000}
        phase = now
        -- as it happens too, so a lift that stops on an error still says where its time went
        printf("lift: %-18s %8.1fs (so far)\n", name, marked[#marked][2])
        if counted then
            local was = marked.counted or {}
            local function delta(key) return (counted[key] or 0) - (was[key] or 0) end
            printf("lift:   %d prefetches %.1fs wall, %d parses %.1fs clang (summed), %.1fs decode, %.1f MB, %d filters, %d recalled\n",
                   delta("prefetches"), delta("prefetch") / 1000, delta("parses"), delta("clang") / 1000, delta("decode") / 1000,
                   delta("bytes") / 1e6, delta("filters"), delta("recalled"))
            marked.counted = table.copy(counted)
        end
    end
    os.tryrm(opt.outputdir)
    os.mkdir(opt.outputdir)
    local listed, incomplete, registered = backports.registry(opt.registry)
    if #incomplete > 0 then
        raise("the backports registry is incomplete: %s", table.concat(incomplete, "; "))
    end
    mark("registry")
    -- The frameworks read: every one the registry has a file for, and opt.frameworks on top of them.
    --
    -- The registry names only the frameworks a backport implements something in, a minority of the
    -- frameworks the SDK ships and of those the corpus surface covers, so a header-only API - one that needs no backport, only its
    -- availability lowered so a translation unit naming it compiles for 6.1.3 - in any other
    -- framework is not read at all, and cannot become reachable however long the registry's own
    -- frameworks take. The extra list is the surface's frameworks, and it is passed in rather than
    -- discovered here for two reasons: what the surface covers is not this repository's business,
    -- and a default that changed the frameworks read would change the committed set on every run
    -- without anyone asking. With no list the lift reads exactly what it read before.
    --
    -- A framework the SDK has no headers for contributes nothing and is not an error: os.files and
    -- framework_headers() both answer an empty list for it, which is how a Swift-only framework in
    -- the surface is carried here.
    local frameworks = table.unique(table.join(registered, opt.frameworks or {}))
    table.sort(frameworks)
    if opt.frameworks and #opt.frameworks > 0 then
        local read, asked = #frameworks, #opt.frameworks
        printf("lift: reading %d frameworks - %d the registry names and %d more from the caller's list\n",
               read, read - asked, asked)
    end
    local symbols = {}
    for _, entry in ipairs(system_entries()) do
        table.insert(symbols, entry.api)
    end
    local system = kept_system_headers(opt, symbols)
    mark("system headers")
    local dump, umbrella, prefetch, alone, collect
    dump, umbrella, prefetch, alone, counted, collect = dumper(opt, frameworks, system)
    mark("dumper")
    local conforms = conformer(opt, umbrella)
    mark("conformer")
    local languages = languages_of(opt)
    mark("languages")
    local expand = expander(opt, header_files(opt.sdk, frameworks), languages)
    mark("expander")
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

    -- Before the surface is asked: the kept accessors a carried property carries. The carried properties of a class
    -- that also has a kept getter, and the kept getters themselves, are one parse's worth of filters (multidump), and
    -- the join is the attribute each is written from. A refusal here instead of at the end of the run is a second or
    -- two of a run that is a minute, and it names both rows and both statuses.
    local getters, owners, asked = {}, {}, 0
    for api in pairs(kept) do
        local member = member_api(api:gsub("%(%)$", ""))
        if member and member.selector and not member.selector:find(":") then
            getters[api] = member
            owners[member.owner] = true
            asked = asked + 1
        end
    end
    local carried_properties = {}
    for _, entry in ipairs(entries) do
        if entry.kind == "property" then
            local member = member_api(entry.api:gsub("%(%)$", ""))
            if member and owners[member.owner] then
                table.insert(carried_properties, entry)
            end
        end
    end
    if #carried_properties > 0 and asked > 0 then
        local wave = {}
        for _, entry in ipairs(carried_properties) do
            table.insert(wave, filter_of(entry))
        end
        for api in pairs(getters) do
            table.insert(wave, filter_of(listed[api]))
        end
        prefetch(wave)
        local where_of, answers = {}, {}
        for _, entry in ipairs(carried_properties) do
            for _, node in ipairs(dump(filter_of(entry))) do
                local found = node.kind == "ObjCPropertyDecl" and attribute_where(node)
                if found and listed[member_api(entry.api:gsub("%(%)$", "")).owner .. "." .. node.name] then
                    -- a set, and not one name: a macro that expands to two declarations writes both their
                    -- attributes at one place, and a location carrying two properties pairs with neither
                    where_of[found] = where_of[found] or {}
                    table.insert(where_of[found], listed[member_api(entry.api:gsub("%(%)$", "")).owner .. "." .. node.name].api)
                end
                table.insert(answers, node)
            end
        end
        for api in pairs(getters) do
            for _, node in ipairs(dump(filter_of(listed[api]))) do
                table.insert(answers, node)
            end
        end
        local conflicts = accessor_conflicts(kept, listed, answers, where_of)
        if #conflicts > 0 then
            table.sort(conflicts)
            raise("the registry answers an accessor and the property it is written from differently, and the lift carries the property: %s",
                  table.concat(conflicts, "; "))
        end
    end
    mark("accessor pairs")

    local supers = {}
    local function superclass(name)
        if supers[name] == nil then
            supers[name] = false
            for _, node in ipairs(dump(name)) do
                if node.kind == "ObjCInterfaceDecl" and node.name == name and node.super then
                    supers[name] = node.super.name
                end
            end
        end
        return supers[name] or nil
    end
    local function superclasses(name)
        local chain, seen = {}, {}
        while name and not seen[name] do
            seen[name] = true
            name = superclass(name)
            if name then
                table.insert(chain, name)
            end
        end
        return chain
    end

    -- A header's text, read once. Several loops here walk the declarations a dump brought back
    -- and each of them needs the file those declarations are in, and the same file comes round
    -- once per declaration in it.
    local read = {}
    local function contents(file)
        local held = read[file]
        if held == nil then
            held = io.readfile(file) or false
            read[file] = held
        end
        return held or nil
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
    local filters = {}
    for _, entry in ipairs(entries) do
        table.insert(filters, filter_of(entry))
    end
    prefetch(filters)
    -- the superclasses of every class, a level at a time: the loop below reads each class's chain, and a chain read
    -- one class at a time was a parse of the umbrella for each
    do
        local wave, reached = {}, {}
        for _, entry in ipairs(entries) do
            if entry.kind == "class" then
                table.insert(wave, entry.api)
            end
        end
        while #wave > 0 do
            prefetch(wave)
            local up = {}
            for _, name in ipairs(wave) do
                local above = superclass(name)
                if above and not reached[above] then
                    reached[above] = true
                    table.insert(up, above)
                end
            end
            wave = up
        end
    end
    mark("entries:prefetch")
    for _, entry in ipairs(entries) do
        local target = opt.minimum
        if entry.minimum and later(entry.minimum, target) then
            target = entry.minimum
        end
        local found = {}
        for _, node in ipairs(candidates(entry, dump(filter_of(entry)))) do
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

    mark("entries:loop")
    -- A property the backports carry whose setter they leave out: the setter clang declares for it shares the property's
    -- mark, so lowering the mark would lower the setter too. It is declared explicitly beside the property instead, at
    -- the release the SDK gives it - Swift then answers the property from the lowered release and refuses the setter
    -- below the SDK's, as it does for any setter declared apart from its property.
    local setters, unwritable = {}, {}
    local kept_filters = {}
    for api in pairs(kept) do
        table.insert(kept_filters, filter_of(listed[api]))
    end
    prefetch(kept_filters)
    for api in pairs(kept) do
        local member = member_api(api)
        if member and member.selector and member.selector:find(":$") then
            for _, node in ipairs(candidates(listed[api], dump(filter_of(listed[api])))) do
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

    mark("entries:setters")
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
    do
        -- the owners of what is unmatched, the selectors asked for, and the superclasses a level at a time
        local wave, asked, reached = {}, {}, {}
        for _, api in ipairs(unmatched) do
            local member = member_api(api:gsub("%(%)$", ""))
            if member then
                table.insert(wave, member.owner)
                table.insert(asked, member.selector or member.property)
            end
        end
        prefetch(asked)
        -- what the loop below asks of what the selectors found: whether each owner is a protocol, and, for an owner that
        -- only an implicit accessor names, its property by name
        local owners = {}
        for _, api in ipairs(unmatched) do
            local member = member_api(api:gsub("%(%)$", ""))
            if member then
                local by_owner = {}
                for _, node in ipairs(dump(member.selector or member.property)) do
                    local by = owner_of(node)
                    if by and member_matches(member, node) then
                        by_owner[by] = by_owner[by] or {}
                        table.insert(by_owner[by], node)
                    end
                end
                for by, nodes in pairs(by_owner) do
                    table.insert(owners, by)
                    local accessor_only = true
                    for _, node in ipairs(nodes) do
                        accessor_only = accessor_only and node.kind ~= "ObjCPropertyDecl" and node.isImplicit
                    end
                    if accessor_only then
                        table.insert(owners, setter_property(nodes[1].name) or nodes[1].name)
                    end
                end
            end
        end
        prefetch(owners)
        while #wave > 0 do
            prefetch(wave)
            local up = {}
            for _, name in ipairs(wave) do
                local above = superclass(name)
                if above and not reached[above] then
                    reached[above] = true
                    table.insert(up, above)
                end
            end
            wave = up
        end
    end
    mark("entries:waves")
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
            local found = {api = api, member = member, owner = owner, class = class, known = receiver ~= nil, reached = {}, asked = {}, elsewhere = {}}
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
                    -- An accessor named for the property's own declared getter: `isTextDragActive` is the getter of
                    -- `textDragActive`, which @property (nonatomic, readonly, getter=isTextDragActive) declares, on the
                    -- protocol UITextDraggable that UIView adopts. The name alone cannot say so - and the registry check
                    -- needs the row spelled as the port builds the getter, so a row named UIView.isTextDragActive is what
                    -- backports spells and what a port writes. So the candidates come from the accessor's name, and a
                    -- candidate is only its property when the getter the property declares IS this accessor, which an
                    -- unrelated property of a similar name cannot pass. The property may be declared on the class or on
                    -- a protocol it conforms to, both of which this file already redeclares from.
                    if #properties == 0 then
                        for _, candidate in ipairs({getter_property(name), name}) do
                            if candidate then
                                for _, node in ipairs(dump(candidate)) do
                                    if node.kind == "ObjCPropertyDecl" and node.name == candidate then
                                        local getter = node.getter and node.getter.name or node.name
                                        -- the declared getter is the whole test: a property whose getter is
                                        -- not this accessor is not the property behind it, whatever it is
                                        -- called and whoever declares it
                                        if getter == by_owner[by][1].name then
                                            table.insert(properties, node)
                                        end
                                    end
                                end
                            end
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
    mark("entries:unmatched")
    local conforming = conforms(questions)
    mark("entries:conforms")
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
            -- what the search did not find is not what the SDK does not declare: an owner no header declares is a member the
            -- search could not have found, and it is named as that
            table.insert(undeclared, {api = api, how = #elsewhere > 0 and "declared only by " .. table.concat(elsewhere, ", ")
                                                       or found.known and "declared nowhere" or "owner not found"})
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
                for _, kind in ipairs(uncarried_attributes(node)) do
                    table.insert(unreachable, string.format("%s is declared by %s with %s, which a redeclaration would not carry", api, by, kind))
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
    mark("entries:pending")
    prefetch(table.orderkeys(members))
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
        -- clang places the @interface's end at the "end" after the "@", and a location in a macro has no offset
        local ending = file and ((interface.range or {})["end"] or {}).offset
        -- The header, read once per file and not once per @interface: this loop runs over every
        -- interface the dump found, and a class with several declarations - a category, a class
        -- extension, a redeclaration in a second header - came back through it each time, reading
        -- the same file again to look at three bytes. Three lines below, code_of() memoises the
        -- same file for the same reason; this is the same thing one function up.
        local content = ending and contents(file)
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
    table.sort(undeclared, function (a, b) return a.api < b.api end)

    -- The types the headers alone declare that implemented API names in its signature: the prefixed names its signature
    -- spells, every typedef its type goes through (a function's return type and parameters, a variable's type: the
    -- dump's _typedefs), every typedef a method or property names for its result, a parameter or itself, and then every
    -- typedef those name in turn - qos_class_self returns qos_class_t, dispatch_queue_attr_make_with_qos_class takes
    -- dispatch_qos_class_t, which is qos_class_t, whose enumerators are the values both mean.
    mark("entries:members")
    local named = {}
    local function alias(type)
        type = type or {}
        return type.typeAliasDeclId and (type.qualType or ""):gsub("%f[%w_]const%f[^%w_]", ""):match("[%a_][%w_]*") or nil
    end
    for _, entry in ipairs(entries) do
        -- a member redeclared on its class names what the declaration it repeats names
        local nodes = table.join(resolved[entry.api] or {})
        for _, node in ipairs(candidates(entry, dump(filter_of(entry)))) do
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
    mark("entries:named")
    local followed = {}
    local pending = table.keys(named)
    while #pending > 0 do
        -- a wave: what the types just reached name in turn is asked for once they are all in
        prefetch(pending)
        local wave = pending
        pending = {}
        for _, name in ipairs(wave) do
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
    end
    local lowered_types, kept_types = {}, {}
    local headers = header_files(opt.sdk, frameworks)
    mark("rewrite:entries")
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
    mark("rewrite:codes")
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
    -- Where each word of the headers' code stands: mentioned[word] = {{file, lines = {line, ...}}, ...}, in the order of
    -- headers and of lines. users() runs once for every type the entries name, and it looked for the type in the whole of
    -- every header read - thousands of files, for each of thousands of types, and again for the pass that names what it
    -- will ask: 270 s of a full lift was that scan. A word here is what the pattern %f[%w_]name%f[^%w_] finds, a run of
    -- letters, digits and underscores, so the lines this lists for a name are the lines that pattern finds it on.
    local mentioned, split
    local function mentions(name)
        if not mentioned then
            mentioned, split = {}, {}
            for _, file in ipairs(headers) do
                local lines = code(file):split("\n", {strict = true})
                split[file] = lines
                for index, line in ipairs(lines) do
                    local here = {}
                    for word in line:gmatch("[%w_]+") do
                        if not here[word] then
                            here[word] = true
                            local places = mentioned[word]
                            if not places then
                                places = {}
                                mentioned[word] = places
                            end
                            local last = places[#places]
                            if not last or last.file ~= file then
                                last = {file = file, lines = {}}
                                table.insert(places, last)
                            end
                            table.insert(last.lines, index)
                        end
                    end
                end
            end
        end
        return mentioned[name] or {}
    end
    local starts_of = {}
    local function users(name, declared, seen)
        seen[name] = true
        local blocking, target = {}, opt.minimum
        for _, place in ipairs(mentions(name)) do
            local file = place.file
            local text = code(file)
            do
                starts_of[file] = starts_of[file] or line_starts(text)
                local starts, lines = starts_of[file], split[file]
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
                for _, index in ipairs(place.lines) do
                    local line = lines[index]
                    if not line:trim():startswith("#") and not dropped(index) then
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
    mark("rewrite:before types")
    prefetch(names)
    -- what users() is about to ask one at a time - the owners of the lines a type is used on, the words of their
    -- declarations - named by a pass that asks nothing, then asked together: each alone was a parse of the whole umbrella
    collect(true)
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
            users(name, declared, {})
        end
    end
    prefetch(collect(false))
    mark("rewrite:types prefetch")
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
    mark("rewrite:preprocessed")
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
    mark("rewrite:unrewritten")
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
    mark("rewrite:write")
    -- marked, so that no edit at all still writes `"roots": []`, which clang reads, not `{}`, which it refuses
    local overlay = {version = 0, ["case-sensitive"] = "false", roots = json.mark_as_array({})}
    local folders = table.keys(roots)
    table.sort(folders)
    mark("rewrite:overlay")
    for _, folder in ipairs(folders) do
        table.insert(overlay.roots, {type = "directory", name = folder, contents = roots[folder]})
    end
    local vfs = path.join(opt.outputdir, "vfs.yaml")
    json.savefile(vfs, overlay)
    mark("rewrite:prefetch")

    -- Both ways: what is implemented answers the lowered release, and nothing else moved. A use no one text can stand
    -- for in every language fails by its own name, whatever else it would have shown.
    local failures = table.join(refusals, unwritable, unreachable)
    local lifted_filters = {}
    for name in pairs(lowered_types) do
        table.insert(lifted_filters, name)
    end
    for _, entry in ipairs(entries) do
        if targets[entry.api] then
            table.insert(lifted_filters, filter_of(entry))
        end
    end
    -- A kept entry is asked over the overlay only where the overlay can move what it answers: the overlay changes a mark only
    -- where the lift edited one (edits, regional), and adds declarations only to the classes it redeclares members on (a member of
    -- such a class may match one). Where none of the marks of the entry's declarations is at an edited place, what it answers is what
    -- it answered before. `skipped` counts those, in the result.
    -- (A declaration lowered through a region is given its own raw attribute in the overlay, and clang leaves the file out of the location of
    -- an attribute written in the file it printed last, so marks() sees none over the overlay: the `regional` clause guards a change the
    -- check could not see either way, and no fixture can make it fail.)
    local function edited(mark)
        return edits[mark.file] and (edits[mark.file][mark.line .. ":" .. mark.col] or mark.declaration and (regional[mark.file] or {})[mark.declaration])
    end
    local before, touched, skipped = {}, {}, 0
    for api in pairs(kept) do
        local entry = listed[api]
        local member = member_api(api:gsub("%(%)$", ""))
        touched[api] = member and members[member.owner] ~= nil
        for _, node in ipairs(candidates(entry, dump(filter_of(entry)))) do
            if matches(entry, node) then
                for _, mark in ipairs(marks(node)) do
                    before[api] = (not before[api] or later(before[api], mark.introduced)) and mark.introduced or before[api]
                    touched[api] = touched[api] or edited(mark) and true
                end
            end
        end
        if touched[api] then
            table.insert(lifted_filters, filter_of(entry))
        else
            skipped = skipped + 1
        end
    end
    prefetch(lifted_filters, vfs)
    mark("rewrite:types")
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
    mark("rewrite:kept")
    for api in pairs(kept) do
        local entry = listed[api]
        local after
        for _, node in ipairs(touched[api] and dump(filter_of(entry), vfs) or {}) do
            if matches(entry, node) then
                for _, mark in ipairs(marks(node)) do
                    after = (not after or later(after, mark.introduced)) and mark.introduced or after
                end
            end
        end
        if before[api] and after and later(before[api], after) then
            table.insert(failures, string.format("%s is %s and was lowered from iOS %s to %s", api, entry.status, before[api], after))
        end
    end
    if #failures > 0 then
        table.sort(failures)
        raise("the lifted headers are wrong: %s", table.concat(failures, "; "))
    end
    table.sort(unmatched)
    -- A plain function or a type can be unmatched honestly (a compiler-rt intrinsic, a private header this dumper does
    -- not read) - lift.lua's own header comment already documents that as expected, and a class with no declaration is
    -- measured as a line for the same reason. So is a protocol: the SDK can have one this port declares itself and no
    -- header of, and that is a fact about the SDK, not a gap in the lookup. Both go into the set with their kind, and
    -- the set is re-measured and reviewed, so a name spelled wrong arrives as a new line in that diff instead of as
    -- silence here.
    --
    -- A class or protocol *member* is different, and cannot be: entry.kind == "class"/nil-with-member-syntax names a
    -- method or property the AST-dump filter should find under its owner's own qualified scope, whether or not that
    -- owner has a registry entry of its own (this lookup never consults listed[owner] - see matches()), or else in a
    -- superclass or a protocol the owner conforms to, where it is redeclared, or nowhere the owner reaches, where it is
    -- named in undeclared with where the SDK does declare it (above). A member still here matched none of those: that
    -- is not a gap in SDK coverage, it is this lookup failing to find something that is really there, and reporting it
    -- only inside a count nobody is required to look at is exactly the silent loss this checks against.
    local silent = silently_absent(unmatched, listed)
    if #silent > 0 then
        raise("lift() found no declaration at all for %d registered class/protocol member(s), which should never be silently absent: %s",
              #silent, table.concat(silent, "; "))
    end
    -- what the lift leaves alone is written beside its result, and compared with the set measured for this SDK
    local left = left_alone(unmatched, undeclared, listed)
    io.writefile(path.join(opt.outputdir, "left-alone.txt"), table.concat(left, "\n") .. "\n")
    local classes, rest, kinds = split_unmatched(unmatched, listed)
    -- `alone`: the queries asked one at a time, which no loop asked for ahead of itself; `skipped`: the kept entries not asked over the overlay
    mark("rewrite:tail")
    if marked then
        for _, row in ipairs(marked) do
            printf("lift: %-18s %8.1fs\n", row[1], row[2])
        end
        printf("lift: dumper asked %d filters over %d frameworks in %d clang runs\n",
               counted.filters, counted.frameworks, counted.runs)
    end
    return {alone = alone, skipped = skipped, vfs = vfs, lifted = lifted, headers = #sorted_files, implemented = #entries, unmatched = rest, kinds = kinds,
            classes = classes, undeclared = undeclared, types = lowered_types, kept_types = kept_types, phases = marked, dumper = counted}, left
end

-- What a lift is a function of, as one key: the registry and the SDK's headers and module maps by content or by name, size
-- and time, the two compilers by path, size and time, the environment they read, the target, the frameworks asked for, and
-- the code that lifts (this folder's modules and the plugin's source). The same key is the same lift, so its output is kept
-- and handed back instead of lifted again: a lift is minutes of compiles, and the key is a second of reading.
local function lift_key(opt)
    local parts = {"charon-lift-1", opt.triple, tostring(opt.minimum), tostring(opt.grouped),
                   table.concat(table.unique(table.join(opt.frameworks or {})), " ")}
    for _, program in ipairs({opt.clang, opt.swiftc}) do
        table.insert(parts, program .. " " .. tostring(os.filesize(program)) .. " " .. tostring(os.mtime(program)))
    end
    for _, name in ipairs(ENVIRONMENT) do
        table.insert(parts, name .. "=" .. (os.getenv(name) or ""))
    end
    local code = table.join(os.files(path.join(os.scriptdir(), "*.lua")), os.files(path.join(os.scriptdir(), "multidump", "*")))
    table.sort(code)
    for _, file in ipairs(code) do
        table.insert(parts, path.filename(file) .. " " .. hash.strhash128(io.readfile(file)))
    end
    local registry = os.files(path.join(opt.registry, "registry", "**"))
    table.sort(registry)
    for _, file in ipairs(registry) do
        table.insert(parts, path.relative(file, opt.registry) .. " " .. hash.strhash128(io.readfile(file)))
    end
    table.insert(parts, sdk_stamp(opt.sdk))
    return hash.strhash128(table.concat(parts, "\n"))
end

local function kept_folder(key)
    return path.join(os.getenv("CHARON_HOME") or path.join(os.getenv("HOME"), ".charon"), "cache", "lift", "result-" .. key)
end

-- The kept folders of one kind beyond the most recently used few, removed: a result is kept for every registry a lift
-- was run on, and each is the whole of the lifted headers (14 MB for SDK 26.2), so without this the folder grows with
-- every change to the registry. The file stamp in each is touched whenever the folder is used (a folder's own time is not
-- moved by a touch), so what is removed is what was used least lately.
local function swept(pattern, stamp, count)
    local folders = os.dirs(path.join(os.getenv("CHARON_HOME") or path.join(os.getenv("HOME"), ".charon"), "cache", "lift", pattern))
    local used = {}
    for _, folder in ipairs(folders) do
        used[folder] = os.mtime(path.join(folder, stamp)) or 0
    end
    table.sort(folders, function (a, b) return used[a] > used[b] end)
    for index = count + 1, #folders do
        os.tryrm(folders[index])
    end
end

-- The output of a lift kept under key: every file of the output folder with its own path spelled as a mark, and the result.
local function keep(key, outputdir, result, left)
    local folder = kept_folder(key)
    if os.isdir(folder) then
        return
    end
    local temporary = folder .. "." .. hash.strhash32(folder .. os.mclock()) .. ".tmp"
    for _, file in ipairs(os.files(path.join(outputdir, "**"))) do
        local target = path.join(temporary, "files", path.relative(file, outputdir))
        try { function () os.mkdir(path.directory(target)) end }
        local text = io.readfile(file, {encoding = "binary"})
        io.writefile(target, unplaced(text, outputdir), {encoding = "binary"})
    end
    io.save(path.join(temporary, "result.lua"), unplaced({result = result, left = left}, outputdir))
    try { function () os.mkdir(path.directory(folder)) end }
    if not try { function () os.mv(temporary, folder); return true end } then
        os.tryrm(temporary)
    end
    swept("result-*", "result.lua", 8)
    swept("dumps-*", "used", 4)
end

-- The kept output under key laid into outputdir, and its result, or nil.
local function restore(key, outputdir)
    local folder = kept_folder(key)
    local saved = os.isfile(path.join(folder, "result.lua")) and io.load(path.join(folder, "result.lua"))
    if not saved then
        return nil
    end
    local files = path.join(folder, "files")
    for _, file in ipairs(os.files(path.join(files, "**"))) do
        local target = path.join(outputdir, path.relative(file, files))
        os.mkdir(path.directory(target))
        io.writefile(target, placed(io.readfile(file, {encoding = "binary"}), outputdir), {encoding = "binary"})
    end
    os.touch(path.join(folder, "result.lua"))
    return placed(saved, outputdir)
end

function lift(opt)
    stamps = {}
    local key = opt.keep and lift_key(opt) or nil
    local result, left
    local restored = key and (os.tryrm(opt.outputdir) or true) and (os.mkdir(opt.outputdir) or true) and restore(key, opt.outputdir)
    if restored then
        result, left = restored.result, restored.left
        result.kept = true
    else
        result, left = computed(opt)
        if key then
            keep(key, opt.outputdir, result, left)
        end
    end
    assert(opt.expected ~= nil, "lift: opt.expected is the text of the measured set of what is left alone, or false to only measure")
    if opt.expected then
        local differing = differences(left, opt.expected)
        if #differing > 0 then
            -- a set with no line at all is the one of an SDK nobody measured (the recipe gives "" for a file that is not there)
            local measured = false
            for line in opt.expected:gmatch("[^\n]+") do
                measured = measured or not line:startswith("#")
            end
            raise("what the lift leaves alone is not the set measured for this SDK (%s%d differences; left-alone.txt in the output has what was found): %s",
                  measured and "" or "no set is measured for it, ", #differing, table.concat(differing, "; "))
        end
    end
    return result
end

-- What the lift leaves alone, one line each, sorted: `class<TAB>name<TAB>` for an implemented class the search found no declaration of,
-- `unmatched<TAB>name<TAB>kind` for another name it found none of (kind as the registry gives it, or "function or constant"),
-- `undeclared<TAB>member<TAB>how` for a registered member whose owner reaches none. These are names the lift did not reach: a
-- name no header declares (a private class, a compiler-rt intrinsic, a later SDK's API), or one whose header it does not read. A
-- set measured for an SDK holds what was found, and is no proof that the SDK declares none of them: each line has to be a name
-- no header declares, or be told apart (a registry spelling lift() reads, a folder of headers it reads) when it is a defect.
-- Where the availability of a declaration is written, as the dump gives it: the file, line and column of the
-- AvailabilityAttr, or nil where the header writes none. An implicit accessor's attribute is its property's, written
-- once for both (see marks()), so two declarations that answer the same where are one API's declaration and its
-- accessors whatever they are called.
function attribute_where(node)
    for _, child in ipairs(node.inner or {}) do
        if child.kind == "AvailabilityAttr" and child.platform == "ios" and child.introduced then
            local begin = child.range and child.range.begin or {}
            local where = begin.expansionLoc or begin
            if where.file and where.line and where.col then
                return string.format("%s:%s:%s", where.file, where.line, where.col), child.introduced
            end
        end
    end
end

-- The kept accessors a carried property carries, one complaint each. What a parse answered for a list of filters is
-- the union of what each of them matches (a filter prints the outermost declarations whose qualified name contains
-- it), so every declaration is indexed by its own qualified name and each api read from its own nodes: an
-- attribute's where is the join between a property and the accessors written from it, and it is the only join there
-- is - a getter may be named anything at all, and only the header says which.
--
-- The registry refuses two spellings of one API that answer differently where it is read, by name: a property
-- `Class.name` and an accessor spelled -[Class name]. This is the half it cannot see.
-- `-[NSProcessInfo isLowPowerModeEnabled]` is the accessor of the property `NSProcessInfo.lowPowerModeEnabled`, and
-- the two are one API with a getter= attribute in a header between them.
function accessor_conflicts(kept, listed, answers, where_of)
    local declarations = {}
    for _, node in ipairs(answers) do
        if node.name then
            declarations[(owner_of(node) or "") .. "::" .. node.name] = node
        end
    end
    local found, seen = {}, {}
    for api in pairs(kept) do
        local member = member_api(api:gsub("%(%)$", ""))
        if member and member.selector and not member.selector:find(":") and not member.selector:find("^set") then
            local node = declarations[member.owner .. "::" .. member.selector]
            if node and node.kind == "ObjCMethodDecl" and node.isImplicit then
                local where = attribute_where(node)
                -- only a location that names one property pairs with it: where two properties are written at
                -- one place, neither can be told from the other, and a false refusal of an unrelated pair stops
                -- a lift, while a miss is a number
                local there = where and where_of[where] or nil
                local property = there and #there == 1 and there[1] or nil
                -- `api` is a bracketed method spelling and `property` the dotted one - the loop below reads only
                -- apis member_api() gives a selector, and where_of holds only what listed[Owner.name] answered -
                -- so the two can never be one row, and a guard for that would be a guard nothing can reach
                if property and kept[api] and listed[property].status == "implemented" then
                    local pair = api < property and (api .. " " .. property) or (property .. " " .. api)
                    if not seen[pair] then
                        seen[pair] = true
                        table.insert(found, string.format("%s is %s and %s is %s, and the first is written from the second's own availability, so lowering the second lowers the first",
                                                          api, listed[api].status, property, listed[property].status))
                    end
                end
            end
        end
    end
    return found
end

-- The names in unmatched that must not be there: a class or protocol *member* - anything spelled as one, a method or
-- a property - and nothing else. A plain function or a type can be unmatched honestly (a compiler-rt intrinsic, a
-- private header the dumper does not read), a class with no declaration is measured as a line for the same reason,
-- and so is a protocol: the SDK can have one this port declares itself and no header of, and the set is re-measured
-- and reviewed, so a name spelled wrong arrives as a new line in that diff rather than as silence here.
--
-- A member is different and cannot be: it is a method or property the filter should find under its owner's own
-- qualified scope, or in a superclass or a protocol the owner conforms to where it is redeclared, or nowhere the
-- owner reaches where it is named in undeclared with where the SDK does declare it. One still in unmatched matched
-- none of those, which is the lookup failing rather than the SDK.
-- The measured set as the file holds it: the header comment the file already carries, with its three per-kind
-- counts and its total computed from the lines, and the lines under it. The counts are what this computes and
-- never what a reader writes - a hand-written count is one a re-measure does not move, and the count is the one
-- number in the file a reader has no other way to check. A line the header has no line for is left as it is, and
-- a header with no line for a kind the set holds is refused: those two are the shape, and the shape is the reader's.
-- `series` replaces the parenthetical of the second line, which is what names the series the set was measured on.
function set_with_counts(header, lines, series)
    local counts = {class = 0, undeclared = 0, unmatched = 0}
    local total = 0
    for _, line in ipairs(lines) do
        local kind = line:match("^(%a+)\t")
        if counts[kind] then
            counts[kind] = counts[kind] + 1
            total = total + 1
        end
    end
    local said, out = {}, {}
    local text, tail = "# (", " lines."
    for _, line in ipairs(header) do
        if line:match("^#  %- class %(%d+%):") then
            line = "#  - class (" .. counts.class .. "):" .. line:sub((line:find(":", 1, true) or 1) + 1)
            said.class = true
        elseif line:match("^#  %- undeclared %(%d+%):") then
            line = "#  - undeclared (" .. counts.undeclared .. "):" .. line:sub((line:find(":", 1, true) or 1) + 1)
            said.undeclared = true
        elseif line:match("^#  %- unmatched %(%d+%):") then
            line = "#  - unmatched (" .. counts.unmatched .. "):" .. line:sub((line:find(":", 1, true) or 1) + 1)
            said.unmatched = true
        elseif line:match("^# %(.*%), none dropped: %d+ lines%.$") then
            local spelled = series
            if not spelled or spelled == "" then
                local at = line:find(text, 1, true)
                spelled = line:sub(at + #text, (line:find("), none dropped:", 1, true) or 1) - 1)
            end
            line = text .. spelled .. "), none dropped: " .. total .. tail
            said.total = true
        end
        table.insert(out, line)
    end
    local missing = {}
    for _, kind in ipairs({"class", "undeclared", "unmatched"}) do
        if counts[kind] > 0 and not said[kind] then
            table.insert(missing, kind)
        end
    end
    if not said.total then
        table.insert(missing, "the total")
    end
    if #missing > 0 then
        raise("the set's header says no count of %s, and this does not invent one", table.concat(missing, ", "))
    end
    for _, line in ipairs(lines) do
        table.insert(out, line)
    end
    return table.concat(out, "\n") .. "\n"
end

-- What a name in unmatched is: "member" when it is spelled as one - a method or a property, which the filter should
-- have found under its owner's own qualified scope, or in a superclass or a protocol the owner conforms to where it
-- is redeclared, or nowhere the owner reaches where it is named in undeclared with where the SDK does declare it -
-- and the registry's own kind otherwise. A member is the lookup failing; a protocol, a class, a function and a type
-- are facts about the SDK or about the port, and are measured.
function absence_of(api, listed)
    if member_api(api:gsub("%(%)$", "")) then
        return "member"
    end
    return (listed[api] or {}).kind or "function or constant"
end

-- The names in unmatched that must not be there: the members, and nothing else.
function silently_absent(unmatched, listed)
    local silent = {}
    for _, api in ipairs(unmatched) do
        if absence_of(api, listed) == "member" then
            table.insert(silent, api)
        end
    end
    return silent
end

function left_alone(unmatched, undeclared, listed)
    local lines = {}
    local classes, rest, kinds = split_unmatched(unmatched, listed)
    for _, api in ipairs(classes) do
        table.insert(lines, "class\t" .. api .. "\t")
    end
    for _, api in ipairs(rest) do
        table.insert(lines, "unmatched\t" .. api .. "\t" .. kinds[api])
    end
    for _, item in ipairs(undeclared) do
        table.insert(lines, "undeclared\t" .. item.api .. "\t" .. item.how)
    end
    table.sort(lines)
    return lines
end

-- What stays unmatched, in the classes and the rest, and the kind of each of the rest. A class is matched by its name alone
-- (matches()), in its @interface, any category of it or a bare @class, so one still unmatched is a class no header the umbrella
-- reads declares at all - a private class, or a later SDK's - and has nothing to lower. It is named apart; the rest is told with
-- its kind, as the registry gives it ("function or constant" where it gives none).
function split_unmatched(unmatched, listed)
    local classes, rest, kinds = {}, {}, {}
    for _, api in ipairs(unmatched) do
        if (listed[api] or {}).kind == "class" then
            table.insert(classes, api)
        else
            table.insert(rest, api)
            kinds[api] = (listed[api] or {}).kind or "function or constant"
        end
    end
    return classes, rest, kinds
end

-- The lines found that the measured set (its text; lines starting with # are comments) does not hold, and the lines it holds that
-- were not found, each named.
function differences(lines, expected)
    local measured, found, differing = {}, {}, {}
    for line in expected:gmatch("[^\n]+") do
        if not line:startswith("#") then
            measured[line] = true
        end
    end
    for _, line in ipairs(lines) do
        found[line] = true
        if not measured[line] then
            table.insert(differing, "new: " .. line:gsub("\t", " "))
        end
    end
    for _, line in ipairs(table.orderkeys(measured)) do
        if not found[line] then
            table.insert(differing, "no longer found: " .. line:gsub("\t", " "))
        end
    end
    return differing
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
