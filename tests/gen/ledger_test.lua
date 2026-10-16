-- The ledger's cache pass (tools/gen/ledger.lua) on fixtures, with no cache and no SDK: the readers' lines parsed (a selector's sign is not
-- part of its name, an instance and a class selector are told apart by their field), each declaration checked against the facts (an ObjC
-- class, protocol, method and property by its runtime name; a C symbol by its linker name with the underscore; an enum member not at all),
-- and the verdict rule (present when a declaration is in the cache; absent only on ObjC runtime evidence, since a C symbol missing from the
-- cache may be a static inline function; undecided otherwise). Run: xmake l tests/gen/ledger_test.lua (exits 1 on any failure).

local TOOLS = path.join(os.scriptdir(), "..", "..", "tools")

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

-- A declaration record as surface_model.declarations gives it (the fields the check reads).
local function decl(fw, kind, api, usr, getter)
    return {framework = fw, claimed_by = fw, kind = kind, lang = "objc", api = api, usr = usr or "", getter = getter or "-"}
end

function main()
    local check, failures = checks()
    local ledger = import("gen.ledger", {rootdir = TOOLS, anonymous = true})

    -- the readers' lines: objc-inventory prints each selector with a sign, the instance selectors in field 5 and the class ones in field 6
    local objc = table.concat({
        "class\tUIView\tUIResponder\t/System/Library/Frameworks/UIKit.framework/UIKit\t-setFrame:,-frame\t+animateWithDuration:\tNSCoding",
        "protocol\tNSLocking\t\t\t-lock,-unlock\t\t",
        "class\tAVPlayer\tNSObject\tAVFoundation\t\t\t",
    }, "\n")
    local exports = "_NSLog\tFoundation\n_OBJC_CLASS_$_UIView\tUIKit\n"
    local facts = ledger.parse_facts(objc, exports)
    check(facts.classes.UIView ~= nil and facts.classes.UIView.inst["setFrame:"] == true,
          "an instance selector is read without its sign (got " .. tostring(facts.classes.UIView and facts.classes.UIView.inst["setFrame:"]) .. ")")
    check(facts.classes.UIView.inst["-setFrame:"] == nil, "the sign is not kept in the name")
    check(facts.classes.UIView.cls["animateWithDuration:"] == true and facts.classes.UIView.inst["animateWithDuration:"] == nil,
          "a class selector is told apart by its field, not by its sign")
    check(facts.protocols.NSLocking.inst.lock == true, "a protocol's instance selectors are read")
    check(facts.exports._NSLog == true and facts.exports["_OBJC_CLASS_$_UIView"] == true,
          "exports are read by their linker symbol, underscore kept")

    -- each declaration against the facts
    check(ledger.check(decl("UIKit", "class", "UIView"), facts) == "present", "an ObjC class in the cache is present")
    check(ledger.check(decl("X", "class", "XYZMissing"), facts) == "absent", "an ObjC class not in the cache is absent")
    check(ledger.check(decl("UIKit", "protocol", "NSLocking"), facts) == "present", "a protocol in the cache is present")
    check(ledger.check(decl("UIKit", "method", "-[UIView setFrame:]"), facts) == "present", "an instance method in the cache is present")
    check(ledger.check(decl("UIKit", "method", "-[UIView make]"), facts) == "absent", "an instance method not in the cache is absent")
    check(ledger.check(decl("UIKit", "method", "+[UIView animateWithDuration:]"), facts) == "present",
          "a class method is checked on the class side")
    check(ledger.check(decl("UIKit", "method", "-[UIView animateWithDuration:]"), facts) == "absent",
          "an instance method is not satisfied by a class selector of the same name")
    check(ledger.check(decl("UIKit", "property", "UIView.frame", nil, "frame"), facts) == "present",
          "a property is checked by its getter")
    check(ledger.check(decl("UIKit", "property", "UIView.bounds", nil, "-"), facts) == "absent",
          "a property with no getter is checked by its name, and absent when the cache lacks it")
    check(ledger.check(decl("X", "method", "-[Gone make]"), facts) == "absent", "a method of a class not in the cache is absent")
    check(ledger.check(decl("F", "function", "NSLog()"), facts) == "present", "a function in the cache is present by its symbol")
    check(ledger.check(decl("F", "function", "NSMissing()"), facts) == "absent", "a C function missing from the cache is absent")
    check(ledger.check(decl("F", "constant", "NSMissingConst"), facts) == "absent", "a C constant missing from the cache is absent")
    check(ledger.check(decl("F", "enum", "NSThing"), facts) == nil, "an enum is not checkable by the cache")
    check(ledger.check(decl("F", "struct", "NSRect2"), facts) == nil, "a struct is not checkable by the cache")
    local member = decl("F", "constant", "kThingA", "c:@EA@thing@kThingA@")
    check(ledger.check(member, facts) == nil, "an enum member (c:@E..@..@) is not checkable: it has no symbol of its own")
    check(ledger.check(decl("F", "constant", "kGlobal", "c:@kGlobal"), facts) == "absent", "a global constant is checkable by its symbol")

    -- the verdict rule over the declarations of each framework
    -- decls is framework -> the records of its shard; a record's claimed_by is the framework that owns it, which may be another shard's
    local decls = {
        RuntimeHere = {decl("RuntimeHere", "class", "UIView"), decl("RuntimeHere", "class", "Gone")},
        RuntimeGone = {decl("RuntimeGone", "class", "Gone"), decl("RuntimeGone", "method", "-[Gone make]")},
        COnly = {decl("COnly", "function", "NSMissing()"), decl("COnly", "constant", "NSMissingConst")},
        MixedFn = {decl("MixedFn", "class", "Gone"), decl("MixedFn", "function", "NSLog()")},
        Types = {decl("Types", "enum", "NSThing")},
        -- a shard holding only a usr another framework owns: that one counts it, this one has nothing of its own
        Borrower = {decl("RuntimeGone", "class", "Gone")},
    }
    decls.Borrower[1].claimed_by = "MixedFn"
    local verdicts = ledger.verdicts(decls, facts)
    check(verdicts.RuntimeHere.verdict == "present", "a framework with a declaration in the cache is present")
    check(verdicts.RuntimeGone.verdict == "absent", "a framework whose runtime declarations are all missing is absent")
    check(verdicts.RuntimeGone.checkable == 2 and verdicts.RuntimeGone.present == 0, "absent counts its runtime declarations")
    check(verdicts.COnly.verdict == "undecided", "C symbols alone are undecided: a static inline function has none (got " .. verdicts.COnly.verdict .. ")")
    check(verdicts.MixedFn.verdict == "present", "a C symbol in the cache is presence even beside a missing class")
    check(verdicts.Types.verdict == "undecided", "a framework of types only is undecided")
    check(verdicts.Types.checkable == 0, "a type is not counted as checkable")
    check(verdicts.RuntimeGone.reason:find("Gone", 1, true) ~= nil, "an absent verdict names the first missing declaration")
    check(verdicts.Borrower.verdict == "undecided" and verdicts.Borrower.checkable == 0,
          "a shard whose only declaration another framework owns gives it nothing (got " .. verdicts.Borrower.verdict .. ")")

    -- a nested shard is its own unit, named by its folder: its declarations claimed by the outer framework count for it, and it has its
    -- own verdict beside the outer one (the trace and the input name it by its folder)
    local sub = decl("Outer", "class", "Gone")
    sub.unit = "Outer/Sub"
    local nested = {Outer = {decl("Outer", "class", "UIView"), sub}}
    local both = ledger.verdicts(nested, facts)
    check(both["Outer/Sub"] ~= nil and both["Outer/Sub"].verdict == "absent" and both["Outer/Sub"].checkable == 1,
          "a nested unit has its own verdict over its own declarations (got " .. tostring(both["Outer/Sub"] and both["Outer/Sub"].verdict) .. ")")
    check(both.Outer.verdict == "present" and both.Outer.checkable == 2 and both.Outer.present == 1,
          "the outer framework still aggregates all of its declarations (got checkable " .. tostring(both.Outer.checkable) .. ")")

    print("ledger test: " .. (failures() == 0 and "OK" or ("FAIL " .. failures())))
    if failures() > 0 then
        os.exit(1)
    end
end
