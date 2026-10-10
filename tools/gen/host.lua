-- The host programs of the differential and of the probe are xmake build products (design-spec-driven.md D5): the project
-- tools/gen/host/xmake.lua declares the oracle (the fixed probe source), the constants dylib (the framework's <F>Constants*.m
-- objects) and the reference program (the source this module writes for the framework's names). This module configures that
-- project for one framework, asks xmake where its build directory and products are, and builds them. xmake decides what is
-- rebuilt. Generated sources are written through emit into the build directory xmake reports; nothing is copied and no run
-- deletes a product. Every call configures the project for the framework it is given, so a run for one framework leaves no
-- configuration that another run reads.

local emit = import("emit", {anonymous = true})
local json = import("core.base.json")

-- The project folder, as an absolute path taken when the module loads (xmake reports paths relative to the working folder).
local PROJECT = path.absolute(path.join(os.scriptdir(), "host"))
local HOST = "/System/Library/Frameworks"

local builddir_cache = nil
local product_cache = {}

-- The text without the colour codes xmake puts in its messages.
local function plain(text)
    return (string.gsub(text or "", "\27%[[%d;]*m", ""))
end

-- The lines of a program's output, split as Python's str.splitlines splits them (a CR LF is one break; CR, LF, VT, FF, the
-- file, group and record separators, NEL, LS and PS also end a line).
function lines(text)
    local marked = string.gsub(text, "\r\n", "\n")
    marked = string.gsub(marked, "[\r\v\f\28\29\30]", "\n")
    marked = string.gsub(marked, "\194\133", "\n")
    marked = string.gsub(marked, "\226\128\168", "\n")
    marked = string.gsub(marked, "\226\128\169", "\n")
    local out, pos = {}, 1
    while pos <= #marked do
        local newline = string.find(marked, "\n", pos, true)
        if not newline then
            table.insert(out, string.sub(marked, pos))
            break
        end
        table.insert(out, string.sub(marked, pos, newline - 1))
        pos = newline + 1
    end
    return out
end

-- The last n bytes of the text without its surrounding white space (the tail the messages quote).
function tail(text, n)
    local stripped = string.gsub(string.gsub(text or "", "^%s+", ""), "%s+$", "")
    return string.sub(stripped, -n)
end

-- The JSON object xmake printed on its standard output.
local function json_of(text)
    return json.decode(string.sub(text, (string.find(text, "{", 1, true))))
end

-- Runs xmake on the project, from the project folder (xmake takes its build directory from the working folder when that folder
-- holds a .xmake folder, so the folder is fixed). Returns ok, stdout, stderr; on failure, ok is false and stderr is the error text.
local function xmake(argv)
    local here = os.curdir()
    local ok, out, err = true, "", ""
    local command = table.join({argv[1]}, {"-P", PROJECT}, table.slice(argv, 2))
    try {
        function()
            os.cd(PROJECT)
            out, err = os.iorunv(os.programfile(), command)
        end,
        catch {
            function(e)
                ok, out, err = false, "", tostring(e)
            end
        }
    }
    os.cd(here)
    return ok, plain(out), plain(err)
end

-- Configures the project for one framework and its constants folder (the .gen folder of the framework in the tree).
function configure(framework, sources)
    local ok, _, err = xmake({"f", "-y", "-q", "--framework=" .. framework, "--sources=" .. sources})
    assert(ok, "xmake configure failed: " .. tail(err, 300))
end

-- The build directory xmake reports for the project, absolute.
function builddir()
    if builddir_cache == nil then
        local ok, out, err = xmake({"show", "--format=json"})
        assert(ok, "xmake show failed: " .. tail(err, 300))
        local dir = json_of(out).project.builddir
        if not path.is_absolute(dir) then
            dir = path.join(PROJECT, dir)
        end
        builddir_cache = path.absolute(dir)
    end
    return builddir_cache
end

-- The product xmake builds for a target, absolute. The project must be configured.
function product(name)
    if product_cache[name] == nil then
        local ok, out, err = xmake({"show", "-t", name, "--format=json"})
        assert(ok, "xmake show failed for " .. name .. ": " .. tail(err, 300))
        local file = json_of(out).targetfile
        if not path.is_absolute(file) then
            file = path.join(PROJECT, file)
        end
        product_cache[name] = path.absolute(file)
    end
    return product_cache[name]
end

-- Builds one target. xmake rebuilds only what its inputs changed; with force, the target is rebuilt whole (used when a generated
-- source of the target was just rewritten: xmake compares whole-second mtimes, so a source rewritten in the second its object was
-- built is not seen as newer). Returns true, or false and the error text. The build output goes to stderr, where the compile
-- lines of a rebuild show.
function build(name, force)
    local argv = {"build", "-y"}
    if force then
        table.insert(argv, "-r")
    end
    table.insert(argv, name)
    local ok, out, err = xmake(argv)
    io.stderr:write(out)
    if not ok then
        -- xmake ends an error with "> in <absolute path>" lines, which name a host path; the message keeps the rest of the text.
        local kept = {}
        for _, line in ipairs(lines(err ~= "" and err or out)) do
            if not string.find(line, "^%s*>%s+in%s") then
                table.insert(kept, line)
            end
        end
        return false, table.concat(kept, "\n")
    end
    io.stderr:write(err)
    return true, ""
end

-- Runs a host program and returns its standard output, and whether it exited with status 0.
function run(program, argv)
    local ok, out = true, ""
    try {
        function()
            out = os.iorunv(program, argv or {})
        end,
        catch {
            function()
                ok = false
            end
        }
    }
    return ok, out
end

-- Writes a generated source of the build directory through emit: gen/<name> under the build directory. Returns its path, and
-- whether the file changed (emit writes nothing when the text is the file's own).
function write_generated(name, text)
    local filepath = path.join(builddir(), "gen", name)
    local changed = emit.file(filepath, text)
    return filepath, changed
end

-- The framework's binary on this host, and whether the host carries the framework at all.
function framework_binary(framework)
    return path.join(HOST, framework .. ".framework", framework), os.isdir(path.join(HOST, framework .. ".framework"))
end
