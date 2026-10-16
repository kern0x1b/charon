-- Re-measures what lift() leaves alone, for both SDKs, in one charon worktree, and writes the two sets into it. The job is the
-- swift-runtime set's re-measure (rule R4 of .agents/skills/patch-merge/SKILL.md): a registry change that moves what the lift leaves
-- alone makes every swift-runtime build with backports fail until both sets are re-measured in the same push. The three runners are
-- beside this file in tools/lift-remeasure/: measure.lua (one lift, through heavy.sh), assemble.lua (the set file from a measurement),
-- verify.lua (lift_test and the sets the build reads). The sets are the lift's own lines under the header the committed set carries,
-- with the counts recounted and checked; nothing is derived by guesswork.
--
-- Usage: xmake l tools/lift-remeasure.lua [options] <charon-worktree>
--   --series TEXT       the parenthetical of the header's second line: what this series added (kept from the header when absent)
--   --sdk-16.4 PATH     measure against this SDK instead of the one store install (required when the store has two)
--   --sdk-26.2 PATH     likewise
--   --clang PATH        the llvm install's clang (default: the store's one llvm 23.1.1)
--   --swiftc PATH       the swift install's swiftc (default: the store's one swift 6.4.0)
--   --jobs N            the clang runs the lift starts at once (default: the cores a lane's share of them, or all of them alone)
--   --no-profile        do not run the lift with LIFT_PROFILE=1 (every run profiles by default)
--   --parallel          run the two lifts side by side (needs two free bulk-lane slots)
--   --sequential        run them one after the other (the default when fewer than two are free)
--   --reuse             keep a measurement this run directory already holds instead of running that lift again
--   --assemble RUNDIR   skip the lifts and assemble the sets from a finished run directory
--   --allow-dirty       measure a worktree with uncommitted tracked changes (recorded in the manifest)
--   --check             resolve and print everything a run would use, write nothing, stop
--   --no-test           do not run lift_test and the set checks
--   --run RUNDIR        put the run somewhere else than <worktree>/.agent-work/runs/lift-remeasure/<UTC stamp>
--
-- The two lifts are one measurement and belong in one push: a set re-measured alone is half a re-measure, and the build still
-- fails on the other SDK. Everything a run touches is inside the worktree (.agent-work/), never /tmp.
-- A lift can fail with "clang gave no dump for the filter X" when a clang is killed under memory pressure; --reuse keeps the
-- measurement the other SDK already has, so a failed lift costs one lift and not the run.
-- If a worktree's set file is missing, this stops: the header's "but for the ones told here" block says which lines are known
-- exceptions and why, and only someone who has read the measurement can write it.

local BOOLEAN_OPTIONS = {["no-profile"] = true, parallel = true, sequential = true, reuse = true, ["allow-dirty"] = true,
                         check = true, ["no-test"] = true}
local VALUE_OPTIONS = {series = true, ["sdk-16.4"] = true, ["sdk-26.2"] = true, clang = true, swiftc = true, jobs = true,
                       assemble = true, run = true}

-- The options, as --name value or a flag, and one positional: the worktree. Returns the table keyed by the name with dashes as
-- underscores (and positional under "worktree").
local function parse(argv)
    local args = {}
    local i = 1
    while i <= #argv do
        local name = string.match(argv[i], "^%-%-(.+)$")
        if name and BOOLEAN_OPTIONS[name] then
            args[string.gsub(name, "%-", "_")] = true
            i = i + 1
        elseif name and VALUE_OPTIONS[name] then
            args[string.gsub(name, "%-", "_")] = argv[i + 1]
            assert(argv[i + 1], "option " .. argv[i] .. " needs a value")
            i = i + 2
        elseif name then
            error("unknown option " .. argv[i])
        else
            if args.worktree then
                error("one worktree, please: " .. args.worktree .. " and " .. argv[i])
            end
            args.worktree = argv[i]
            i = i + 1
        end
    end
    return args
end

local function say(message)
    print("lift-remeasure: " .. message)
end

local function die(message)
    print("lift-remeasure: " .. message)
    os.exit(1)
end

-- The text of a file, or nil where there is none (io.readfile raises on a missing file, so the test comes first).
local function read_or_nil(file)
    if os.isfile(file) then
        return io.readfile(file)
    end
    return nil
end

-- The output of a git command in the worktree, or the reason it failed.
local function git(worktree, arguments)
    return try { function () return (os.iorunv("git", table.join({"-C", worktree}, arguments))):trim() end }
end

-- The lines of a text, and the set of those lines.
local function lines_of(text)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    return lines
end

-- The body lines of a set text: the lines that are not comments.
local function body_lines(text)
    local body = {}
    for _, line in ipairs(lines_of(text)) do
        if not line:startswith("#") then
            table.insert(body, line)
        end
    end
    return body
end

-- The lines in a that are not in b, and the other way round: what changed between two sets of body lines.
local function only_in(a, b)
    local held, out = {}, {}
    for _, line in ipairs(b) do
        held[line] = true
    end
    for _, line in ipairs(a) do
        if not held[line] then
            table.insert(out, line)
        end
    end
    return out
end

-- The one install the store has of an SDK, or the caller's. Two installs are a question for the caller, not a guess.
local function resolve_sdk(version, given, home)
    if given then
        return path.absolute(given)
    end
    local found = os.dirs(path.join(home, ".xmake", "packages", "i", "iphoneos-sdk", version, "*", "Developer.app", "Contents",
                                    "Developer", "Platforms", "iPhoneOS.platform", "Developer", "SDKs", "iPhoneOS" .. version .. ".sdk"))
    if #found == 1 then
        return found[1]
    end
    if #found == 0 then
        die("no " .. version .. " SDK is installed under the store; name one with --sdk-" .. version .. " PATH")
    end
    die(version .. " has " .. #found .. " installs under the store; name one with --sdk-" .. version .. " PATH")
end

-- A store tool that exists in exactly one install, or the caller's.
local function resolve_tool(given, pattern, what)
    if given then
        return path.absolute(given)
    end
    local found = os.files(pattern)
    if #found == 1 then
        return found[1]
    end
    die(what .. " has " .. #found .. " installs under the store; name one with --" .. string.lower(what) .. " PATH")
end

-- An SDK is checked against its own name: the folder is named for the set the build reads, and SDKSettings names the same SDK.
local function check_sdk(sdk)
    if not os.isdir(sdk) then
        die("there is no SDK at " .. sdk)
    end
    local settings = read_or_nil(path.join(sdk, "SDKSettings.json"))
    if not settings then
        die(sdk .. " holds no SDKSettings.json")
    end
    local canonical = "iphoneos" .. string.gsub(string.gsub(path.filename(sdk), "^iPhoneOS", ""), "%.sdk$", "")
    if not settings:find('"CanonicalName":"' .. canonical .. '"', 1, true) then
        die(sdk .. " is not the " .. canonical .. " SDK its folder name says (SDKSettings.json names another)")
    end
end

-- The count of each kind in a set's body, and the body's line count.
local function counts_of(lines)
    local counted = {class = 0, undeclared = 0, unmatched = 0}
    for _, line in ipairs(lines) do
        local kind = string.match(line, "^(%a+)\t")
        if counted[kind] then
            counted[kind] = counted[kind] + 1
        end
    end
    return counted
end

-- The heavy slots of the bulk lane, as heavy.sh names them: a slot is taken while its directory exists.
local function free_bulk_slots(heavy_dir, slots)
    local free = 0
    for index = 1, slots do
        if not os.isdir(path.join(heavy_dir, "bulk", "slot." .. index)) then
            free = free + 1
        end
    end
    return free
end

-- Runs the driver. See the header for the options.
function main(...)
    local args = parse({...})
    local home = os.getenv("HOME")
    local workspace = os.getenv("FLEET_HEAVY_BASEDIR") or path.join(home, "Git", "projects", "ios")
    local heavy = path.join(workspace, "coordination", "heavy.sh")
    local measure = path.join(os.scriptdir(), "lift-remeasure", "measure.lua")
    local assemble = import("assemble", {rootdir = path.join(os.scriptdir(), "lift-remeasure"), anonymous = true})
    local verify = import("verify", {rootdir = path.join(os.scriptdir(), "lift-remeasure"), anonymous = true})
    local process = import("core.base.process")

    -- the lane a lift is run in is the bulk lane (heavy.sh sends a lift-remeasure job there); its slot count and the cores are
    -- heavy.sh's own, so a lift counts the slots heavy.sh really has free
    local heavy_dir = os.getenv("FLEET_HEAVY_DIR") or "/tmp/fleet-heavy"
    local slots = tonumber(os.getenv("FLEET_HEAVY_BULK_SLOTS") or "3")
    local cores = tonumber(os.getenv("FLEET_HEAVY_CORES") or "")
    if not cores then
        cores = tonumber(try { function () return (os.iorunv("sysctl", {"-n", "hw.ncpu"})):trim() end } or "") or 1
    end
    local lane_share = math.max(1, cores // slots)
    local solo_share = math.max(1, cores)

    local mode = args.assemble and "assemble" or (args.check and "check" or "measure")
    local worktree = args.worktree
    if not worktree then
        die("a charon worktree is needed")
    end
    worktree = os.isdir(worktree) and path.absolute(worktree) or die("there is no directory at " .. worktree)
    if not os.isfile(path.join(worktree, "modules", "apple", "lift.lua")) then
        die(worktree .. " is not a charon worktree (no modules/apple/lift.lua)")
    end
    if not os.isdir(path.join(worktree, "packages", "s", "swift-runtime", "lift")) then
        die(worktree .. " has no packages/s/swift-runtime/lift")
    end
    local registry_dir = path.join(worktree, "packages", "a", "apple-backports", "registry")
    if not os.isdir(registry_dir) then
        die(worktree .. " has no backports registry")
    end
    if not os.isfile(heavy) then
        die("no heavy.sh at " .. heavy)
    end
    local jobs_asked = args.jobs
    if jobs_asked and not string.match(jobs_asked, "^%d+$") then
        die("--jobs takes a number, not '" .. jobs_asked .. "'")
    end

    local head = git(worktree, {"rev-parse", "HEAD"}) or die(worktree .. " is not in a git repository")
    local status = git(worktree, {"status", "--short"}) or die("git status failed in " .. worktree)
    -- a measurement needs a tree it can name; a re-assembly measures nothing
    if mode == "measure" and status ~= "" and not args.allow_dirty then
        say(worktree .. " has uncommitted tracked changes:")
        print(status)
        die("a set measured against a tree nobody can name by hash is a set for no series: commit it, or pass --allow-dirty")
    end
    -- what was measured, named: the head, and the two trees the lift reads
    local registry_tree = git(worktree, {"rev-parse", "HEAD:packages/a/apple-backports/registry"}) or die("no registry at HEAD")
    local modules_tree = git(worktree, {"rev-parse", "HEAD:modules"}) or die("no modules at HEAD")

    local sdk16 = resolve_sdk("16.4", args["sdk_16.4"], home)
    local sdk26 = resolve_sdk("26.2", args["sdk_26.2"], home)
    check_sdk(sdk16)
    check_sdk(sdk26)
    local clang = resolve_tool(args.clang or os.getenv("LIFT_CLANG"),
                               path.join(home, ".xmake", "packages", "l", "llvm", "23.1.1", "*", "bin", "clang"), "clang")
    local swiftc = resolve_tool(args.swiftc or os.getenv("LIFT_SWIFTC"),
                                path.join(home, ".xmake", "packages", "s", "swift", "6.4.0", "*", "bin", "swiftc"), "swiftc")
    if not os.isexec(clang) then
        die("no clang at " .. clang)
    end
    if not os.isexec(swiftc) then
        die("no swiftc at " .. swiftc)
    end
    local name16, name26 = path.filename(sdk16), path.filename(sdk26)
    if name16 == name26 then
        die("both SDKs are the same directory (" .. sdk16 .. "); each set is measured against its own")
    end

    -- Two free slots of the bulk lane, and nothing holding the machine exclusively, or the lifts share the machine. A lock whose
    -- owner is gone still counts as busy: heavy.sh reaps it on entry, so a stale slot only makes this sequential.
    local exclusive = os.isdir(path.join(heavy_dir, "exclusive"))
    local free = exclusive and 0 or free_bulk_slots(heavy_dir, slots)
    local want = args.parallel and "parallel" or (args.sequential and "sequential" or nil)
    if not want then
        want = (not exclusive and free >= 2) and "parallel" or "sequential"
    end
    -- two lifts share the lane's share of the cores; one lift at a time has the machine to itself; a caller's --jobs wins
    local jobs = (jobs_asked and tonumber(jobs_asked)) or ((want == "parallel") and lane_share or solo_share)

    local profile = not args.no_profile
    if not profile and os.getenv("LIFT_PROFILE") then
        die("LIFT_PROFILE is set in the environment, and lift.lua profiles whenever it is set: unset it, or run without --no-profile")
    end

    say(worktree .. " at " .. head .. " (registry " .. registry_tree .. ", modules " .. modules_tree .. ")")
    if mode == "measure" and status ~= "" then
        say("measured with --allow-dirty; the manifest carries the uncommitted files")
    end
    say("16.4 " .. sdk16)
    say("26.2 " .. sdk26)
    say("clang " .. clang .. ", swiftc " .. swiftc .. ", " .. jobs .. " clang runs at once, " .. want)
    say("LIFT_PROFILE " .. (profile and "1" or "off") .. ", so every phase of every run is in its log")
    if exclusive then
        say("an exclusive job holds the machine, so the lifts are sequential")
    elseif free < 2 then
        say("only " .. free .. " of " .. slots .. " bulk heavy slots are free, so the lifts are sequential")
    end
    if mode == "check" then
        say("--check, nothing written")
        return
    end

    local run_dir
    if mode == "assemble" then
        run_dir = args.assemble
        if not os.isdir(run_dir) then
            die("there is no run directory at " .. run_dir)
        end
    else
        local stamp = os.date("!%Y-%m-%dT%H%M%SZ")
        run_dir = args.run or path.join(worktree, ".agent-work", "runs", "lift-remeasure", stamp)
        if os.isdir(run_dir) and #os.files(path.join(run_dir, "*")) > 0 and not os.isfile(path.join(run_dir, "manifest.txt")) then
            die(run_dir .. " holds something that is not a lift run; point --run somewhere of its own")
        end
        os.mkdir(run_dir)
    end
    local manifest = path.join(run_dir, "manifest.txt")
    local function note(text)
        io.writefile(manifest, (read_or_nil(manifest) or "") .. text .. "\n")
    end

    -- The inputs are copied, so a tree that moves under a long run cannot change what is measured.
    if mode == "measure" then
        if args.reuse and os.isdir(path.join(run_dir, "modules")) and os.isdir(path.join(run_dir, "registry", "registry")) then
            say("the frozen modules/ and registry/ of this run are kept; they are what its measurement read")
        else
            os.tryrm(path.join(run_dir, "modules"))
            os.tryrm(path.join(run_dir, "registry"))
            os.mkdir(path.join(run_dir, "registry"))
            os.cp(path.join(worktree, "modules"), path.join(run_dir, "modules"))
            os.cp(registry_dir, path.join(run_dir, "registry", "registry"))
        end
    end
    local set16 = path.join(worktree, "packages", "s", "swift-runtime", "lift", name16 .. ".txt")
    local set26 = path.join(worktree, "packages", "s", "swift-runtime", "lift", name26 .. ".txt")
    for _, set_file in ipairs({set16, set26}) do
        if not os.isfile(set_file) then
            die("there is no measured set at " .. set_file .. ", and this writes none: the header's \"but for the ones told here\" block is a reader's, not a count's")
        end
    end
    -- the set as it stood when this run started, kept once: a later --assemble must diff against what the worktree held
    for _, name in ipairs({name16, name26}) do
        local kept = path.join(run_dir, "set-" .. name .. ".before.txt")
        if not os.isfile(kept) then
            io.writefile(kept, io.readfile(path.join(worktree, "packages", "s", "swift-runtime", "lift", name .. ".txt")))
        end
    end

    if mode == "measure" then
        note("")
        note("--- attempt " .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. ", head " .. head .. " ---")
        note("run            " .. run_dir)
        note("worktree       " .. worktree)
        note("head           " .. head)
        note("registry tree  " .. registry_tree)
        note("modules tree   " .. modules_tree)
        if status ~= "" then
            note("dirty          the tracked changes below were measured as they stood")
            note(status)
        end
        note("clang          " .. clang)
        note("swiftc         " .. swiftc)
        note("jobs           " .. jobs)
        note("profile        " .. (profile and "LIFT_PROFILE=1" or "off"))
        note("started        " .. os.date("!%Y-%m-%dT%H:%M:%SZ"))
        note("sdk " .. name16 .. " " .. sdk16)
        note("sdk " .. name26 .. " " .. sdk26)
    end

    -- One lift, started through heavy.sh (which holds a bulk slot and runs it at lowered priority) with its environment set
    -- before the spawn. Its log is its record, rotated when an earlier attempt of this run left one.
    local function start(sdk, name)
        local out = path.join(run_dir, "out-" .. name)
        local log = path.join(run_dir, "lift-" .. name .. ".log")
        if os.isfile(log) then
            os.mv(log, path.join(run_dir, "lift-" .. name .. "-" .. os.date("%H%M%S") .. ".log"))
        end
        os.tryrm(out)
        os.setenv("LIFT_SDK", sdk)
        os.setenv("LIFT_CLANG", clang)
        os.setenv("LIFT_SWIFTC", swiftc)
        os.setenv("LIFT_JOBS", tostring(jobs))
        if profile then
            os.setenv("LIFT_PROFILE", "1")
        end
        local started = os.mclock()
        local proc, errors = process.openv(heavy, {"xmake", "l", measure, run_dir, out, path.join(run_dir, "registry")},
                                           {stdout = log, stderr = log})
        if not proc then
            die("could not start the lift against " .. name .. ": " .. tostring(errors))
        end
        return {name = name, log = log, proc = proc, started = started}
    end
    -- waits for a started lift: its exit status, and what the run records of it
    local function finish(job)
        local result = job.proc:wait(-1)
        job.proc:close()
        local took = math.floor((os.mclock() - job.started) / 1000)
        if result ~= 0 then
            say("the lift against " .. job.name .. " failed (exit " .. tostring(result) .. ", " .. took .. "s); the end of " .. job.log .. ":")
            local lines = lines_of(read_or_nil(job.log) or "")
            for index = math.max(1, #lines - 19), #lines do
                print(lines[index])
            end
        else
            say(job.name .. " measured in " .. took .. "s -> " .. path.join(run_dir, "out-" .. job.name, "left-alone.txt"))
        end
        note(job.name .. " exit=" .. tostring(result) .. " took=" .. took .. "s")
        return result
    end

    if mode == "measure" then
        local measured = {}
        for _, name in ipairs({name16, name26}) do
            local alone = path.join(run_dir, "out-" .. name, "left-alone.txt")
            if args.reuse and os.isfile(alone) then
                measured[name] = true
                local count = #lines_of(read_or_nil(alone))
                say(name .. " was measured in this run already (" .. count .. " lines); --reuse keeps it")
                note(name .. " reused=" .. count .. " lines")
            end
        end
        local status16, status26 = 0, 0
        if measured[name16] and measured[name26] then
            -- both kept
        elseif want == "parallel" and not measured[name16] and not measured[name26] then
            local first = start(sdk16, name16)
            local second = start(sdk26, name26)
            status16 = finish(first)
            status26 = finish(second)
        else
            if not measured[name16] then status16 = finish(start(sdk16, name16)) end
            if not measured[name26] then status26 = finish(start(sdk26, name26)) end
        end
        if status16 ~= 0 or status26 ~= 0 then
            die("a lift failed, so the sets are not re-measured; nothing in the worktree was changed (the logs are in " .. run_dir .. ")")
        end
    end

    -- Both sets are assembled and checked before either is written, so a worktree is never left with one SDK's set re-measured
    -- and the other's not.
    local assembled = {}
    for _, name in ipairs({name16, name26}) do
        local alone_file = path.join(run_dir, "out-" .. name, "left-alone.txt")
        local alone = read_or_nil(alone_file)
        if not alone then
            die("no " .. alone_file .. ": there is no measurement of " .. name .. " to assemble")
        end
        local before_text = io.readfile(path.join(run_dir, "set-" .. name .. ".before.txt"))
        local new_text = assemble.set_text(path.join(worktree, "modules"), before_text, alone, args.series or "")
        local contradictions = assemble.mismatches(new_text)
        if #contradictions > 0 then
            die("the new " .. name .. ".txt contradicts itself: " .. table.concat(contradictions, "; "))
        end
        local counted = counts_of(body_lines(new_text))
        say(name .. ".txt: " .. #lines_of(alone) .. " lines (" .. counted.class .. " class, " .. counted.undeclared .. " undeclared, " .. counted.unmatched .. " unmatched)")
        assembled[name] = {text = new_text, before = before_text}
    end
    for _, name in ipairs({name16, name26}) do
        local entry = assembled[name]
        io.writefile(path.join(run_dir, "set-" .. name .. ".new.txt"), entry.text)
        if entry.text == entry.before then
            say(name .. ".txt is unchanged")
        else
            say(name .. ".txt changed:")
            for _, line in ipairs(only_in(lines_of(entry.before), lines_of(entry.text))) do
                print("- " .. string.gsub(line, "\t", " "))
            end
            for _, line in ipairs(only_in(lines_of(entry.text), lines_of(entry.before))) do
                print("+ " .. string.gsub(line, "\t", " "))
            end
            -- the header's prose names known exceptions: a name it still tells about, which this measurement no longer leaves alone
            for _, line in ipairs(only_in(body_lines(entry.before), body_lines(entry.text))) do
                local item = string.gsub(string.match(line, "\t([^\t]*)") or "", "%(%)$", "")
                if item ~= "" and string.find(entry.text, item, 1, true) then
                    say("the header of " .. name .. ".txt still tells about " .. item .. ", which this measurement no longer leaves alone: read it against the diff above")
                end
            end
        end
    end
    for _, name in ipairs({name16, name26}) do
        io.writefile(path.join(worktree, "packages", "s", "swift-runtime", "lift", name .. ".txt"), assembled[name].text)
    end
    say("both sets written into " .. worktree .. " at " .. os.date("!%Y-%m-%dT%H:%M:%SZ") .. "; the run is in " .. run_dir)
    print(git(worktree, {"status", "--short", "--", "packages/s/swift-runtime/lift"}))

    if not args.no_test then
        say("lift_test, and the sets it does not read")
        local found = verify.failures(worktree)
        for _, failure in ipairs(found) do
            print(failure)
        end
        if #found > 0 then
            die("lift_test or the sets did not hold; the failures are above and the sets are written but not verified")
        end
    end
    say("done")
end
