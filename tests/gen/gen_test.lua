-- Behaviour of the generator's support modules: the SHA-256 digest, the one writer (emit), the pipe stream, and the zero-writes rule
-- of a second gen on an unchanged tree. Run:
--   xmake l tests/gen/gen_test.lua
-- The writer's test works in a scratch directory under .agent-work/runs of this checkout, removed when the test ends.

local TOOLS = path.join(os.scriptdir(), "..", "..", "tools")

-- True when fn raises an error.
local function raises(fn)
    local raised = false
    try {
        fn,
        catch {
            function() raised = true end
        }
    }
    return raised
end

local function checks()
    local failures = 0
    local function check(ok, label)
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end
    return check, function() return failures end
end

local function test_sha256(check)
    local sha256 = import("gen.sha256", {rootdir = TOOLS, anonymous = true})
    check(sha256.hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256 of the empty string")
    check(sha256.hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 of abc")
    check(sha256.hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq")
          == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1", "sha256 of the two-block vector")
end

local function test_emit(check)
    local emit = import("gen.emit", {rootdir = TOOLS, anonymous = true})
    local dir = path.join(os.scriptdir(), "..", "..", ".agent-work", "runs", "gen-test-" .. tostring(os.time()) .. "-"
                          .. tostring(math.random(1000000)))
    os.mkdir(dir)
    local target = path.join(dir, "nested", "out.txt")
    local before = emit.count()
    check(emit.file(target, "alpha\n") == true, "a new file is written")
    check(emit.count() == before + 1, "the write is counted")
    local mtime = os.mtime(target)
    os.sleep(1100)
    check(emit.file(target, "alpha\n") == false, "unchanged text writes nothing")
    check(emit.count() == before + 1, "an unchanged file is not counted")
    check(os.mtime(target) == mtime, "an unchanged file keeps its mtime")
    check(emit.file(target, "beta\n") == true, "changed text is written")
    check(os.isfile(target .. ".charon-new") == false, "the sibling of a write is renamed away")
    local handle = io.open(target, "rb")
    check(handle:read("a") == "beta\n", "the new bytes are on disk")
    handle:close()
    check(raises(function() emit.file(path.join(dir, "bad.txt"), "caf\195\169\n") end), "non-ASCII text is refused")
    os.rm(dir)
end

-- A second `gen --all` on an unchanged tree writes no file: the emitter compares before it writes (design-spec-driven.md D2).
local function test_zero_writes(check)
    local gen = import("gen.cmd_gen", {rootdir = TOOLS, anonymous = true})
    local emit = import("gen.emit", {rootdir = TOOLS, anonymous = true})
    local tree = path.absolute(path.join(os.scriptdir(), "..", ".."))
    local args = {tree = tree, all = true}
    gen.run(args)
    local before = emit.count()
    check(gen.run(args) == 0, "gen --all on the tree succeeds")
    check(emit.count() == before, "a second gen --all on the unchanged tree writes no file")
end

local function test_stream(check)
    local stream = import("gen.stream", {rootdir = TOOLS, anonymous = true})
    local lines = {}
    local status = stream.lines("printf", {"one\\ntwo\\n"}, function(line) table.insert(lines, line) end)
    check(status == 0 and #lines == 2 and lines[1] == "one" and lines[2] == "two", "lines come in order, exit 0")
    local count, last = 0, nil
    status = stream.lines("seq", {"1", "200000"}, function(line) count = count + 1; last = line end)
    check(status == 0 and count == 200000 and last == "200000", "a long stream spans many chunks")
    local seen = 0
    status = stream.lines("sh", {"-c", "echo x; exit 3"}, function() seen = seen + 1 end)
    check(status == 3 and seen == 1, "the exit status of the program comes back")
    check(raises(function() stream.lines("sh", {"-c", "echo partial; kill -9 $PPID"}, function() end) end),
          "a program that dies before its sentinel raises, instead of spinning")
end

function main()
    local check, failures = checks()
    test_sha256(check)
    test_emit(check)
    test_stream(check)
    test_zero_writes(check)
    print("gen support test: " .. (failures() == 0 and "OK" or ("FAIL " .. failures())))
    if failures() > 0 then
        os.exit(1)
    end
end
