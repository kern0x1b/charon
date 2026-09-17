import("fixtures")

function failures(opt)
    local architectures = import("apple.architectures", {rootdir = opt.modules, anonymous = true})
    local found = {}
    for _, case in ipairs({{"armv6", "2.0"}, {"armv6", "2.2.1"}, {"armv6", "4.2.1"}, {"armv7", "3.0"}, {"armv7", "6.1.3"},
                           {"armv7s", "6.0"}, {"arm64", "7.0"}}) do
        local kept = architectures.deployment(case[1], case[2])
        if kept ~= case[2] then
            table.insert(found, string.format("a %s port for %s builds for the release it declares, not %s", case[1], case[2], tostring(kept)))
        end
    end
    for _, case in ipairs({{"armv7", "2.0", "apple_minimum 2.0 is older than 3.0, the first release an armv7 device runs"},
                           {"armv7", "2.0", "armv6 runs it, so build that architecture, or raise apple_minimum to 3.0"},
                           {"armv7", "1.1.4", "no architecture this toolchain builds runs it, so raise apple_minimum to 3.0"},
                           {"armv7s", "5.1.1", "older than 6.0, the first release an armv7s device runs"},
                           {"arm64", "6.1.3", "older than 7.0, the first release an arm64 device runs"},
                           {"armv6", "6.0", "apple_minimum 6.0 is newer than 4.2.1, the last release an armv6 device runs"},
                           {"armv8", "6.0", "toolchain(apple-ios) builds arm64, armv6, armv7, armv7s, not armv8"}}) do
        local errors = fixtures.refusal(function () architectures.deployment(case[1], case[2]) end)
        if not errors then
            table.insert(found, string.format("a %s port for %s must be refused, not quietly built for another release", case[1], case[2]))
        elseif not errors:find(case[3], 1, true) then
            table.insert(found, string.format("a %s port for %s must be refused saying %s, and said: %s", case[1], case[2], case[3], errors))
        end
    end
    return found
end
