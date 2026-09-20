-- What the swift rule must do for a library of Swift, which no test here builds (a build needs the runtime), so the facts that
-- were found by building one are held in the rule's text: the archiver of xmake's Swift language has flags of its own, empty by
-- default; a program whose Swift is all in libraries needs the runtime its libraries import; and what calls Swift through the header
-- the compiler writes must be compiled after it.
function failures(opt)
    local found = {}
    local text = io.readfile(path.join(opt.modules, "..", "rules", "swift", "xmake.lua"))
    if not text:find('target:add("scarflags", "-cr"', 1, true) then
        table.insert(found, "a static library of Swift is archived by the Swift language's archiver, whose flags (scarflags) are empty: given the library's path and no -cr, ar reads the path as options")
    end
    local hook = text:match("before_link%(function %(target%)(.-)\n    end%)") or ""
    if not hook:find("target:orderdeps()", 1, true) or not hook:find("swift.objectfile", 1, true) then
        table.insert(found, "a program whose Swift is all in a library must name the runtime libraries that library imports, or they come after the frameworks on the link line and bind to the system's Foundation")
    end
    if not text:find('target:set("policy", "build.fence", true)', 1, true) or not text:find("-emit-objc-header", 1, true) then
        table.insert(found, "a target that has the compiler write an Objective-C header must be built before what depends on it compiles, or the Objective-C finds no header")
    end
    return found
end
