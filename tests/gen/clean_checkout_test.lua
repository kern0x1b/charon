-- The clean-checkout check (review F2, and the v-gen2 ruling): the committed tree is extracted with `git archive HEAD` into a folder under
-- .agent-work/runs of this checkout, and `gen --all` and `check --all` run from that folder with no derived file present. It fails when
-- any file outside packages/a/apple-backports/.gen appears or changes (gen may write only that folder), when gen or check exits
-- non-zero, or when the Python oracle runs: gen and check run with a python3 on the PATH that writes a marker and fails, and the marker
-- must not exist afterwards (the build path reads the committed products and runs no gen.py). It checks HEAD, the last commit: git archive
-- reads committed files only, so an uncommitted change is not tested until it is committed. The archive, the python3 stand-in and the
-- marker are removed at the end. Run: xmake l tests/gen/clean_checkout_test.lua

local ROOT = path.absolute(path.join(os.scriptdir(), "..", ".."))
local GEN_PREFIX = "packages/a/apple-backports/.gen/"

-- Every file under dir, keyed by its path relative to dir, with its size and modification time.
local function listing(dir)
    local out = {}
    for _, filepath in ipairs(os.files(path.join(dir, "**"))) do
        out[path.relative(filepath, dir)] = {size = os.filesize(filepath), mtime = os.mtime(filepath)}
    end
    return out
end

-- The sorted names of a listing.
local function names_of(list)
    local out = {}
    for name in pairs(list) do
        table.insert(out, name)
    end
    table.sort(out)
    return out
end

-- The exit status of `xmake l tools/gen.lua <args>` run from dir with the given PATH, or nil when it could not start.
local function run_gen(dir, args, search_path)
    local argv = {"l", "tools/gen.lua"}
    for _, arg in ipairs(args) do
        table.insert(argv, arg)
    end
    return (os.execv(os.programfile(), argv, {try = true, curdir = dir, envs = {PATH = search_path}}))
end

function main()
    local failures = 0
    local function fail(label)
        failures = failures + 1
        print("FAIL " .. label)
    end
    local stamp = tostring(os.time()) .. "-" .. tostring(math.random(1000000))
    local dir = path.join(ROOT, ".agent-work", "runs", "clean-checkout-" .. stamp)
    local shim_dir = path.join(ROOT, ".agent-work", "runs", "clean-checkout-python-" .. stamp)
    local marker = path.join(shim_dir, "python3-was-run")
    os.mkdir(dir)
    os.mkdir(shim_dir)
    -- a python3 that records that it ran and fails, first on the PATH of the generator's runs
    io.writefile(path.join(shim_dir, "python3"), "#!/bin/sh\ntouch '" .. marker .. "'\nexit 99\n")
    os.execv("chmod", {"755", path.join(shim_dir, "python3")})
    local search_path = shim_dir .. ":" .. (os.getenv("PATH") or "")
    -- the stand-in must catch a call, or the "never ran" result below proves nothing
    os.execv("sh", {"-c", "python3"}, {try = true, envs = {PATH = search_path}})
    local caught = os.isfile(marker)
    if caught then
        os.rm(marker)
    else
        fail("the python3 stand-in does not catch a call, so the no-python result would prove nothing")
    end
    local extracted = os.execv("sh", {"-c", 'git -C "$1" archive --format=tar HEAD | tar -x -C "$2"', "sh", ROOT, dir}, {try = true})
    if extracted ~= 0 then
        fail("git archive HEAD could not be extracted (status " .. tostring(extracted) .. ")")
    else
        local before = listing(dir)
        local started = os.mclock()
        local gen_status = run_gen(dir, {"gen", "--tree", dir, "--all"}, search_path)
        local gen_ms = os.mclock() - started
        started = os.mclock()
        local check_status = run_gen(dir, {"check", "--tree", dir, "--all"}, search_path)
        local check_ms = os.mclock() - started
        local after = listing(dir)
        if gen_status ~= 0 then
            fail("gen --all from the clean checkout exits " .. tostring(gen_status))
        end
        if check_status ~= 0 then
            fail("check --all from the clean checkout exits " .. tostring(check_status))
        end
        if os.isfile(marker) then
            fail("the Python oracle ran from the clean checkout (python3 was called by gen or check)")
        end
        local derived, outside = 0, 0
        for _, name in ipairs(names_of(after)) do
            local was = before[name]
            if string.sub(name, 1, #GEN_PREFIX) == GEN_PREFIX then
                derived = derived + 1
            elseif was == nil then
                outside = outside + 1
                fail("added outside .gen: " .. name)
            elseif was.size ~= after[name].size or was.mtime ~= after[name].mtime then
                outside = outside + 1
                fail("changed outside .gen: " .. name)
            end
        end
        for _, name in ipairs(names_of(before)) do
            if after[name] == nil and string.sub(name, 1, #GEN_PREFIX) ~= GEN_PREFIX then
                outside = outside + 1
                fail("removed outside .gen: " .. name)
            end
        end
        if derived == 0 then
            fail("gen wrote nothing under " .. GEN_PREFIX)
        end
        print(string.format("clean checkout: %d files in the archive before, %d after, %d under .gen, %d outside .gen changed",
            #names_of(before), #names_of(after), derived, outside))
        print(string.format("clean checkout: gen --all exit %s in %d ms, check --all exit %s in %d ms, python3 run: %s",
            tostring(gen_status), gen_ms, tostring(check_status), check_ms, tostring(os.isfile(marker))))
    end
    os.rm(dir)
    os.rm(shim_dir)
    print("clean checkout test: " .. (failures == 0 and "OK" or ("FAIL " .. failures)))
    if failures > 0 then
        os.exit(1)
    end
end
