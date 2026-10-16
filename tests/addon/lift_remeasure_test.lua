-- The assembler of tools/lift-remeasure (the set file a measurement writes): the header a set carries, with its counts recounted from
-- the lines the lift found and the total, and the series parenthetical taken from the caller or kept from the header; a header that
-- cannot carry the counts is refused; and the counts a set says are checked against the lines it holds. Our own fixture, pure Lua:
-- no SDK, no clang, nothing written. Run: xmake l tests/addon/lift_remeasure_test.lua (exits 1 on any failure).

local function expect_equal(found, what, got, wanted)
    if got ~= wanted then
        table.insert(found, string.format("%s was %s, not %s", what, tostring(got), tostring(wanted)))
    end
end

-- The header of a set as the committed ones carry it: the prose, then the three counts and the total, with stale numbers in them.
local BEFORE = table.concat({
    "# What lift() leaves alone against iPhoneOS99.0.sdk: one full lift of the registry of an earlier series",
    "# (old names), none dropped: 9 lines.",
    "# Each is a name the lift did not reach.",
    "#  - class (7): a class no header declares.",
    "#  - undeclared (5): a registered member its class reaches no declaration of.",
    "#  - unmatched (0): a name the headers do not declare.",
    "class\tOldClass\t",
    "undeclared\t-[OldClass gone]\tdeclared nowhere",
}, "\n") .. "\n"

-- What the lift found this time: one class, one undeclared member, two other names. Written in the order the lift sorts them.
local ALONE = table.concat({
    "class\tCharonNewClass\t",
    "undeclared\t-[NSX member]\tdeclared nowhere",
    "unmatched\t__newFunction\tfunction or constant",
    "unmatched\tNewProtocol\tprotocol",
}, "\n") .. "\n"

local function lines_of(text)
    local lines = {}
    for line in text:gmatch("[^\n]+") do
        table.insert(lines, line)
    end
    return lines
end

function failures(opt)
    local found = {}
    local assemble = import("assemble", {rootdir = path.join(path.directory(opt.modules), "tools", "lift-remeasure"), anonymous = true})

    -- the counts and the total are recounted from the lines; the prose stays, and so does every header line that is not a count
    local out = assemble.set_text(opt.modules, BEFORE, ALONE, "new series")
    local lines = lines_of(out)
    local header, body = {}, {}
    for _, line in ipairs(lines) do
        if line:startswith("#") then table.insert(header, line) else table.insert(body, line) end
    end
    expect_equal(found, "the class count", header[4], "#  - class (1): a class no header declares.")
    expect_equal(found, "the undeclared count", header[5], "#  - undeclared (1): a registered member its class reaches no declaration of.")
    expect_equal(found, "the unmatched count", header[6], "#  - unmatched (2): a name the headers do not declare.")
    expect_equal(found, "the total and the series", header[2], "# (new series), none dropped: 4 lines.")
    expect_equal(found, "the prose above the counts is kept", header[3], "# Each is a name the lift did not reach.")

    -- the body is the lines the lift found, and nothing of the old set
    expect_equal(found, "the body is the measured lines", table.concat(body, "\n") .. "\n", ALONE)

    -- an empty series keeps the parenthetical the header already carries
    local kept = assemble.set_text(opt.modules, BEFORE, ALONE, "")
    expect_equal(found, "an empty series keeps the header's own parenthetical", lines_of(kept)[2], "# (old names), none dropped: 4 lines.")

    -- a header that says no total cannot carry one: refused, not invented
    local no_total = BEFORE:gsub("none dropped: 9 lines%.", "dropped nothing.")
    local accepted = try { function () assemble.set_text(opt.modules, no_total, ALONE, "new series") return true end }
    expect_equal(found, "a header with no total is refused", accepted, nil)

    -- the counts a set says are checked against the lines it holds: the set just written holds, the stale one does not
    expect_equal(found, "a freshly assembled set has no contradiction", #assemble.mismatches(out), 0)
    local stale = #assemble.mismatches(BEFORE .. ALONE)
    expect_equal(found, "a set whose header counts do not match its lines is named", stale > 0, true)

    return found
end

function main()
    local found = failures({modules = path.join(os.scriptdir(), "..", "..", "modules")})
    for _, failure in ipairs(found) do
        print("FAIL " .. failure)
    end
    if #found > 0 then
        os.exit(1)
    end
    print("lift_remeasure_test: OK")
end
