-- The surface computed from the model (tools/gen/surface_model.lua) on a fixture tree: which declarations arrived after iOS 6.1, with
-- the via, the unavailability, the getter and the deprecation each one gets. The rules under test: an own availability; a member's
-- class in the same framework (container); an ObjC category member's class floor, across frameworks (class-floor); a Swift member's
-- nearest type (container, through a nested type); the boundary (6.1 is not after 6.1); and the order of the rows. The fixture is
-- written into .agent-work/runs of this checkout with a copy of tools/, as gen_test does. Run: xmake l tests/gen/surface_test.lua
-- (exits 1 on any failure).

local TOOLS = path.join(os.scriptdir(), "..", "..", "tools")
local SNAP = "packages/a/apple-backports/spec"
local OBJC_HEADER = "#libclang=fixture\tsdk=fixture\tcolumns=kind,usr,container,name,side,type,params,attrs,availability,message,declhash,value\n"
local SWIFT_HEADER = "framework\tkind\tusr\tcontainer\tname\tside\ttype\tparams\tavailability\tmessage\tdeclhash\n"

-- One ObjC declaration row: the cells the shard's columns name, with the side, type, params, message and value fixed.
local function decl(kind, usr, container, name, attrs, availability)
    return table.concat({kind, usr, container or "-", name or "", "-", "-", "-", attrs or "-", availability or "-", "-", "h", "-"}, "\t")
end

-- One Swift row of a framework's Swift shard, in the column order of the dump.
local function swift(fw, kind, usr, container, name, availability)
    return table.concat({fw, "swift-" .. kind, usr, container or "-", name, "-", "-", "-", availability or "-", "-", "h"}, "\t")
end

local ALPHA_OBJC = {
    decl("interface", "c:objc(cs)FXOld", nil, nil, nil, "ios=6.0/-/-/0"),
    decl("interface", "c:objc(cs)FXNew", nil, nil, nil, "ios=7.0/-/-/0,macos=10.9/-/-/0"),
    decl("method", "c:objc(cs)FXNew(im)doThing", nil, nil, nil, "-"),
    decl("method", "c:objc(cs)FXNew(cm)make", nil, nil, nil, "ios=9.0/-/-/0"),
    decl("method", "c:objc(cs)FXOld(im)legacy", nil, nil, nil, "-"),
    decl("property", "c:objc(cs)FXNew(py)label", nil, "", "nonatomic,getter=isLabelled", "-"),
    decl("category", "c:objc(cy)FXOld@Ext", nil, nil, nil, "ios=9.0/-/-/0"),
    decl("method", "c:objc(cs)FXOld(im)extOld", "FXOld@Ext", nil, nil, "-"),
    decl("method", "c:objc(cs)FXNew(im)extNew", "FXNew@Ext2", nil, nil, "-"),
    decl("var", "c:@FXConstant", nil, nil, nil, "ios=8.0/-/-/0"),
    decl("var", "c:@FXOldConst", nil, nil, nil, "ios=5.0/-/-/0"),
    decl("function", "c:FXHeader.h@F@FXFunction", nil, nil, nil, "ios=10.0/-/-/0"),
    decl("interface", "c:objc(cs)FXGone", nil, nil, nil, "ios=-/-/-/1,macos=10.9/-/-/0"),
    decl("method", "c:objc(cs)FXNew(im)gone", nil, nil, nil, "ios=9.0/-/-/1"),
    decl("struct", "c:@S@FXStruct", nil, nil, nil, "ios=8.0/-/-/0"),
    decl("interface", "c:objc(cs)FXDep", nil, nil, nil, "ios=7.0/8.0/-/0"),
    decl("enum", "c:@E@FXEnum", nil, nil, nil, "ios=9.0/-/-/0"),
    decl("enumconst", "c:@E@FXEnum@FXEnum_A", "FXEnum", nil, nil, "-"),
    decl("protocol", "c:objc(pl)FXProto", nil, nil, nil, "ios=7.5/-/-/0"),
    decl("method", "c:objc(pl)FXProto(im)protoDo", nil, nil, nil, "-"),
    decl("interface", "c:objc(cs)FXEdge", nil, nil, nil, "ios=6.1/-/-/0"),
}

local BETA_OBJC = {
    decl("method", "c:objc(cs)FXNew(im)betaExt", "FXNew@BetaExt", nil, nil, "-"),
}

-- A nested framework's shard: its rows are the outer framework's.
local SUB_OBJC = {
    decl("interface", "c:objc(cs)FXSub", nil, nil, nil, "ios=8.0/-/-/0"),
}

local ALPHA_SWIFT = {
    swift("FixAlpha", "struct", "s:FXSwift", "-", "FXSwift", "ios=8.0,tvos=9.0"),
    swift("FixAlpha", "method", "s:FXSwift.doIt", "FXSwift", "doIt(x:)", "-"),
    swift("FixAlpha", "struct", "s:FXSwiftOld", "-", "FXSwiftOld", "ios=5.0"),
    swift("FixAlpha", "method", "s:FXSwiftOld.old", "FXSwiftOld", "old()", "-"),
    swift("FixAlpha", "struct", "s:FXSwift.Inner", "FXSwift", "Inner", "-"),
    swift("FixAlpha", "method", "s:FXSwift.Inner.run", "FXSwift.Inner", "run()", "-"),
    swift("FixAlpha", "function", "s:fxSwiftFunc", "-", "fxSwiftFunc(_:)", "ios=12.0"),
    swift("FixAlpha", "protocol", "s:FXSwiftProto", "-", "FXSwiftProto", "ios=13.0"),
    swift("FixAlpha", "typealias", "s:FXAlias", "-", "FXAlias", "ios=6.0"),
    swift("FixAlpha", "constant", "s:FXSwift.FXEnumNew", "FXSwift", "FXEnumNew", "-"),
    swift("FixAlpha", "method", "s:FXSwift.eq", "FXSwift", "==(_:_:)", "-"),
}

local GAMMA_SWIFT = {
    swift("FixGamma", "struct", "s:GSwift", "-", "GSwift", "ios=14.0"),
}

-- The rows the surface holds, as "framework kind lang api introduced via unavailable getter deprecated" ("-" where empty).
local EXPECTED = {
    "FixAlpha class objc FXNew 7.0 own - - -",
    "FixAlpha method objc -[FXNew doThing] 7.0 container - - -",
    "FixAlpha method objc +[FXNew make] 9.0 own - - -",
    "FixAlpha property objc FXNew.label 7.0 container - isLabelled -",
    "FixAlpha method objc -[FXNew extNew] 7.0 class-floor - - -",
    "FixAlpha constant objc FXConstant 8.0 own - - -",
    "FixAlpha function objc FXFunction() 10.0 own - - -",
    "FixAlpha method objc -[FXNew gone] 9.0 own yes - -",
    "FixAlpha struct objc FXStruct 8.0 own - - -",
    "FixAlpha class objc FXDep 7.0 own - - 8.0",
    "FixAlpha protocol objc FXProto 7.5 own - - -",
    "FixAlpha method objc -[FXProto protoDo] 7.5 container - - -",
    "FixBeta method objc -[FXNew betaExt] 7.0 class-floor - - -",
    "FixAlpha struct swift FXSwift 8.0 own - - -",
    "FixAlpha method swift FXSwift.doIt(x:) 8.0 container - - -",
    "FixAlpha struct swift FXSwift.Inner 8.0 container - - -",
    "FixAlpha method swift FXSwift.Inner.run() 8.0 container - - -",
    "FixAlpha function swift fxSwiftFunc(_:) 12.0 own - - -",
    "FixAlpha protocol swift FXSwiftProto 13.0 own - - -",
    "FixAlpha constant swift FXSwift.FXEnumNew 8.0 container - - -",
    "FixGamma struct swift GSwift 14.0 own - - -",
    "FixAlpha enum objc FXEnum 9.0 own - - -",
    "FixAlpha constant objc FXEnum_A 9.0 container - - -",
    "FixAlpha class objc FXSub 8.0 own - - -",
    "FixAlpha method swift FXSwift.==(_:_:) 8.0 container - - -",
}

-- A version as a number, for the order of the rows: 6.1 is 601, 7.5 is 705.
local function number(text)
    local major, minor = string.match(text, "^(%d+)%.?(%d*)")
    return tonumber(major) * 100 + (tonumber(minor) or 0)
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

local function write(file, text)
    local emit = import("gen.emit", {rootdir = TOOLS, anonymous = true})
    os.mkdir(path.directory(file))
    assert(emit.file(file, text), "could not write " .. file)
end

local function line_of(record)
    local function cell(value)
        return (value == nil or value == "") and "-" or value
    end
    return table.concat({record.framework, record.kind, record.lang, record.api, record.introduced, record.via,
                         cell(record.unavailable == "yes" and "yes" or nil), cell(record.getter), cell(record.deprecated)}, " ")
end

function main()
    local check, failures = checks()
    local surface_model = import("gen.surface_model", {rootdir = TOOLS, anonymous = true})
    local root = path.join(os.scriptdir(), "..", "..", ".agent-work", "runs", "surface-test-" .. tostring(os.time()) .. "-"
                           .. tostring(math.random(1000000)))
    local tree = path.join(root, "tree")
    os.mkdir(tree)
    os.cp(TOOLS, path.join(tree, "tools"))
    os.cp(path.join(TOOLS, "..", "modules"), path.join(tree, "modules"))

    write(path.join(tree, SNAP, "FixAlpha", "declarations.tsv"), OBJC_HEADER .. table.concat(ALPHA_OBJC, "\n") .. "\n")
    write(path.join(tree, SNAP, "FixAlpha", "swift.tsv"), SWIFT_HEADER .. table.concat(ALPHA_SWIFT, "\n") .. "\n")
    write(path.join(tree, SNAP, "FixBeta", "declarations.tsv"), OBJC_HEADER .. table.concat(BETA_OBJC, "\n") .. "\n")
    write(path.join(tree, SNAP, "FixGamma", "swift.tsv"), SWIFT_HEADER .. table.concat(GAMMA_SWIFT, "\n") .. "\n")
    write(path.join(tree, SNAP, "FixAlpha", "Sub", "declarations.tsv"), OBJC_HEADER .. table.concat(SUB_OBJC, "\n") .. "\n")

    local names = surface_model.frameworks(tree)
    check(#names == 3 and names[1] == "FixAlpha" and names[2] == "FixBeta" and names[3] == "FixGamma",
          "the frameworks are the three shards, in byte order (got " .. table.concat(names, ",") .. ")")

    local rows = surface_model.rows(tree)
    local got, want = {}, {}
    for _, record in ipairs(rows) do
        table.insert(got, line_of(record))
    end
    for _, text in ipairs(EXPECTED) do
        table.insert(want, text)
    end
    table.sort(got)
    table.sort(want)
    local have = {}
    for _, text in ipairs(got) do
        have[text] = (have[text] or 0) + 1
    end
    for _, text in ipairs(want) do
        if have[text] == nil or have[text] == 0 then
            check(false, "missing row: " .. text)
        else
            have[text] = have[text] - 1
        end
    end
    for text, count in pairs(have) do
        for _ = 1, count do
            check(false, "unexpected row: " .. text)
        end
    end
    check(#rows == #EXPECTED, "the surface holds " .. #EXPECTED .. " rows (got " .. #rows .. ")")

    local sorted = true
    for index = 2, #rows do
        if number(rows[index - 1].introduced) > number(rows[index].introduced) then
            sorted = false
        end
    end
    check(sorted, "the rows come out in the order of their introduction")
    check(rows[1] ~= nil and rows[1].introduced == "7.0", "the first row is the earliest introduction (7.0)")

    local text = surface_model.table_text(rows)
    local header = string.match(text, "^[^\n]*")
    check(header == "framework\tkind\tlang\tapi\tintroduced\tdeprecated\tobsoleted\tunavailable\tvia\tgetter",
          "the table's header has the surface columns in order")
    local _, lines = string.gsub(text, "\n", "\n")
    check(lines == #rows + 1, "the table has one line per row and the header")

    os.rm(root)
    print("surface test: " .. (failures() == 0 and "OK" or ("FAIL " .. failures())))
    if failures() > 0 then
        os.exit(1)
    end
end
