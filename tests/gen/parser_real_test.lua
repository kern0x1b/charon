-- The real header parser (headers.facts, which runs `gen.py headers` through a pipe) on the AVFAudio framework of an iOS 26.2 SDK: it
-- gives the members, the declared names and the superclasses. It needs the SDK, named by CHARON_SDK26; without it the test FAILS (it
-- does not skip and does not pass), so the gate cannot pass with the parser untested. Run:
--   CHARON_SDK26=<path to iPhoneOS26.2.sdk> xmake l tests/gen/parser_real_test.lua
-- Exits 1 on any failure.

local TOOLS = path.join(os.scriptdir(), "..", "..", "tools")

function main()
    local headers = import("gen.headers", {rootdir = TOOLS, anonymous = true})
    local failures, count = 0, 0
    local function check(ok, label)
        count = count + 1
        if not ok then
            failures = failures + 1
            print("FAIL " .. label)
        end
    end

    local sdk = os.getenv("CHARON_SDK26")
    check(sdk ~= nil and os.isdir(sdk), "CHARON_SDK26 names an iOS 26.2 SDK folder (got " .. tostring(sdk) .. ")")
    if sdk and os.isdir(sdk) then
        headers.use(nil)
        local real = headers.facts(path.join(TOOLS, ".."), "AVFAudio", sdk)
        check(#real.members > 0 and real.members[1].kind ~= nil, "the parser gives the members of AVFAudio")
        check(real.declared.AVAudioApplication == true, "the parser gives the declared names")
        check(real.superclasses.AVAudioApplication == "NSObject", "the parser gives the superclass each class names")
    end

    print(string.format("parser real test: %s (%d checks)", failures == 0 and "OK" or ("FAIL " .. failures), count))
    if failures > 0 then
        os.exit(1)
    end
end
