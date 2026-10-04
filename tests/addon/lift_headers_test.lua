-- The headers a module map reaches for a symbol, with the compiler that decides which of them cannot be included alone. SDK 26.2's
-- dispatch.modulemap lists every dispatch header (block.h among them, which #errors unless dispatch.h includes it); SDK 16.4's
-- dispatch/module.modulemap names the umbrella header dispatch.h. Either way the include is dispatch/dispatch.h. A listed header
-- another one includes but that compiles alone (os/lock.h under Darwin.modulemap, included by OSSpinLockDeprecated.h) stays, as does
-- a header of its own (solo.h), and one whose #include is not the first line of its includer (spin.h).
function failures(opt)
    local lift = import("apple.lift", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local function expect(what, got, wanted)
        if got ~= wanted then
            table.insert(found, string.format("%s was %s, not %s", what, tostring(got), tostring(wanted)))
        end
    end
    local function raises(action)
        return try {function () action() return false end, catch {function () end}} ~= false
    end
    -- Both folders belong to the run alone (measured in lift_test, 2026-10-04: a fixture folder a second run
    -- removes is a lift that cannot open its own SDK), so the run's own id is in each of their names.
    local sdk = path.join(os.tmpdir(), "lift_headers_test_sdk-" .. os.getpid())
    local work = path.join(os.tmpdir(), "lift_headers_test_work-" .. os.getpid())
    os.tryrm(sdk)
    os.tryrm(work)
    os.mkdir(work)
    local function put(name, text)
        io.writefile(path.join(sdk, "usr", "include", name), text)
    end
    put("dispatch.modulemap", "module Dispatch [system] {\n\theader \"dispatch/dispatch.h\"\n\theader \"dispatch/block.h\"\n\texport *\n}\n")
    put("dispatch/dispatch.h", "#define __DISPATCH_INDIRECT__\n#include <dispatch/block.h>\nvoid dispatch_main(void);\n")
    put("dispatch/block.h", "#ifndef __DISPATCH_INDIRECT__\n#error \"Please #include <dispatch/dispatch.h>\"\n#endif\nvoid dispatch_block_create(void);\n")
    put("os/module.modulemap", "module os [system] {\n\tumbrella header \"os.h\"\n}\n")
    put("os/os.h", "#include <os/lock.h>\n")
    put("os/lock.h", "void os_unfair_lock_lock(void);\n")
    put("plain.modulemap", "module Plain [system] {\n\theader \"solo.h\"\n}\n")
    put("solo.h", "void solo_fn(void);\n")
    -- a header that cannot stand alone is reached through the one that includes it, whether that #include is the first line of the includer or
    -- comes after a comment (measured: an includer scan that skips the first line does not change the answer here, so the two are not a control
    -- of it; the block-only symbol below is what fails against the earlier versions)
    put("pair.modulemap", "module Pair [system] {\n\theader \"spin.h\"\n\theader \"lock2.h\"\n\theader \"spin3.h\"\n\theader \"lock4.h\"\n}\n")
    put("spin.h", "#define SPIN_INDIRECT\n#include <lock2.h>\nvoid spin_fn(void);\n")
    put("lock2.h", "#ifndef SPIN_INDIRECT\n#error \"lock2.h is not a header of its own\"\n#endif\nvoid lock2_fn(void);\n")
    put("spin3.h", "// the spin lock\n#define SPIN_INDIRECT\n#include <lock4.h>\nvoid spin3_fn(void);\n")
    put("lock4.h", "#ifndef SPIN_INDIRECT\n#error \"lock4.h is not a header of its own\"\n#endif\nvoid lock4_fn(void);\n")
    put("needs.h", "#include <config_of_its_folder>\n")
    -- an includer the compiler cannot read alone brings nothing: no map lists it as a header of a language the umbrella reads
    put("cxx.modulemap", "module Cxx [system] {\n\theader \"cxxall.h\"\n\theader \"cxxpart.h\"\n}\n")
    put("cxxall.h", "#define CXX_INDIRECT\n#include <cxxconfig_not_here>\n#include <cxxpart.h>\n")
    put("cxxpart.h", "#ifndef CXX_INDIRECT\n#error \"cxxpart.h is not a header of its own\"\n#endif\nvoid cxxpart_fn(void);\n")
    local probe = {clang = opt.clang, triple = "armv7-apple-ios6.1.3", sdk = sdk, outputdir = work}
    local function standalone(name)
        return lift.stands_alone(probe, name)
    end

    -- the probe itself: the compiler's word on real headers, and a raise where it cannot answer
    expect("dispatch.h alone", standalone("dispatch/dispatch.h"), true)
    expect("block.h alone", standalone("dispatch/block.h"), false)
    expect("os/lock.h alone", standalone("os/lock.h"), true)
    expect("a header whose own include is not there cannot stand alone", standalone("needs.h"), false)
    expect("a header that is not there raises", raises(function () standalone("no/such.h") end), true)
    local mute = {clang = path.join(work, "no-such-clang"), triple = probe.triple, sdk = sdk, outputdir = work}
    expect("a compiler that is not there raises", raises(function () lift.stands_alone(mute, "dispatch/dispatch.h") end), true)
    -- an error of the driver has no place in a file: a triple the compiler does not know is not the header's fault
    local bogus = {clang = opt.clang, triple = "bogus-none-none", sdk = sdk, outputdir = work}
    expect("a triple the compiler does not know raises", raises(function () lift.stands_alone(bogus, "dispatch/dispatch.h") end), true)

    local function reached(symbols)
        return table.concat(lift.system_headers(sdk, symbols, standalone), ", ")
    end
    expect("the headers reached", reached({"dispatch_main", "dispatch_block_create", "os_unfair_lock_lock", "solo_fn", "spin_fn", "lock2_fn",
                                                       "spin3_fn", "lock4_fn", "cxxpart_fn"}),
           "dispatch/dispatch.h, os/os.h, solo.h, spin.h, spin3.h")
    -- block.h is where the symbol is, and no map names an umbrella of dispatch: it is reached through the header that includes it
    expect("a symbol only a header that cannot stand alone declares", reached({"dispatch_block_create"}), "dispatch/dispatch.h")
    os.tryrm(sdk)
    os.tryrm(work)
    return found
end
