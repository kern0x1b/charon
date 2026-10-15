-- `headers`: the SDK-shaped headers of the frameworks, rendered from the declaration IR by render_headers.lua (design-sdk-generator.md
-- step 3a). Two modes:
--   xmake l tools/gen.lua headers --tree T --ir FULL --sdk SDK --out D [--framework F]
--     writes D/Frameworks/<F>.framework/Headers/<header> and, where the SDK's framework has a module map, its Modules/module.modulemap
--     (a SubFramework goes under D/SubFrameworks, as the SDK has it; a nested Outer/Inner under Outer's Frameworks/). Every framework
--     of the IR is written unless --framework names one. A framework the SDK does not hold as a framework (usr/include modules) is
--     counted and not written.
--   xmake l tools/gen.lua headers --tree T --ir FULL --framework F --compare DECLS
--     compares the IR's rows of F with DECLS, the rows decls prints for F over the tree (IR_FRAMEWORKS=D, IR_SDK=SDK), and prints
--     the counts and every difference grouped by its cause.
-- --tree is required by the driver; nothing is written into the tree. The IR is the full 18-column file (IR_FULL of ir.lua).
-- Returns the exit status: 0, or 2 for a bad argument.

local render = import("render_headers", {anonymous = true})
local emit = import("emit", {anonymous = true})

local function read_text(filepath)
    local handle = assert(io.open(filepath, "rb"), "cannot open " .. filepath)
    local text = handle:read("a")
    handle:close()
    return text
end

-- The IR's rows, grouped by framework (the meta row left out), and the rows of every framework for the definitions an import needs.
local function read_ir(filepath)
    local rows, by_framework = {}, {}
    for _, row in ipairs(render.rows_of(read_text(filepath))) do
        if row[2] ~= "meta" then
            rows[#rows + 1] = row
            local list = by_framework[row[1]] or {}
            list[#list + 1] = row
            by_framework[row[1]] = list
        end
    end
    return rows, by_framework
end

-- Where the SDK holds a framework: "Frameworks" or "SubFrameworks" and the top-level folder, or nil when the SDK has no such framework.
local function location_of(sdk, framework)
    local top = string.match(framework, "^([^/]+)")
    for _, folder in ipairs({"Frameworks", "SubFrameworks"}) do
        local dir = path.join(sdk, "System", "Library", folder, top .. ".framework")
        if os.isdir(dir) then return folder, dir end
    end
    return nil
end

-- The SDK's folder of a framework, nested ones under their outer framework's Frameworks/ folder.
local function sdk_folder(dir, framework)
    local base = dir
    for segment in string.gmatch(framework, "/([^/]+)") do
        base = path.join(base, "Frameworks", segment .. ".framework")
    end
    return base
end

-- Two tables read from the usr/include module maps, not from any header. prefix: the import prefix of each module, the umbrella folder
-- its top-level module map line names (ObjectiveC's is objc, so its NSObject.h is imported as <objc/NSObject.h>). umbrella: the
-- folder's own umbrella header, where a module lists it (Dispatch lists dispatch/dispatch.h, and its other headers refuse a direct
-- import: "Please #include <dispatch/dispatch.h> instead of this file directly").
local function usr_dirs_of(sdk)
    local dirs, umbrellas = {}, {}
    for _, file in ipairs(os.files(path.join(sdk, "usr", "include", "*.modulemap"))) do
        local module = nil
        for line in io.lines(file) do
            local name = string.match(line, "^module%s+([%w_]+)")
            if name then module = name end
            local umbrella = string.match(line, '^%s*umbrella%s+"([^"]+)"')
            if module and umbrella and dirs[module] == nil then dirs[module] = umbrella end
            local folder, base = string.match(line, '^%s*header%s+"([^"/]+)/([^"/]+)"')
            if folder and base == folder .. ".h" then umbrellas[folder] = folder .. "/" .. base end
        end
    end
    return {prefix = dirs, umbrella = umbrellas}
end

-- The tree folder a framework is written to: <folder>/<top>.framework, nested frameworks under their outer one's Frameworks/.
local function destination_of(folder, framework)
    local out = folder .. "/" .. string.match(framework, "^([^/]+)") .. ".framework"
    for segment in string.gmatch(framework, "/([^/]+)") do
        out = out .. "/Frameworks/" .. segment .. ".framework"
    end
    return out
end

local function write_all(out, folder, framework, result)
    local dest = path.join(out, destination_of(folder, framework))
    for relative, text in pairs(result.files) do
        emit.file(path.join(dest, relative), text)
    end
end

local function print_causes(report)
    local labels = {}
    for label in pairs(report.causes) do labels[#labels + 1] = label end
    table.sort(labels)
    for _, label in ipairs(labels) do
        print(string.format("  %6d  %s", report.causes[label], label))
    end
end

local function compare_mode(args, by_framework)
    local framework = args.framework
    local ir_rows = by_framework[framework] or {}
    local decl_rows = render.rows_of(read_text(args.compare))
    local report = render.compare(ir_rows, decl_rows)
    print(string.format("%s: IR rows %d, decls rows %d, equal %d", framework, report.ir, report.decls, report.equal))
    local differences = 0
    for _, n in pairs(report.causes) do differences = differences + n end
    print(string.format("%s: differences %d", framework, differences))
    print_causes(report)
    return 0
end

local function write_mode(args, rows, by_framework)
    local out = args.out
    local sdk = args.sdk
    if out == nil or sdk == nil then
        print("headers: writing needs --out and --sdk")
        return 2
    end
    local defs, arities = render.defs_of(rows)
    local usr_dirs = usr_dirs_of(sdk)
    local names = {}
    if args.framework then
        names = {args.framework}
    else
        for name in pairs(by_framework) do names[#names + 1] = name end
        table.sort(names)
    end
    local totals = {frameworks = 0, not_in_sdk = 0, files = 0, lines = 0, declarations = {}, skipped = {}}
    local started = os.time()
    for _, framework in ipairs(names) do
        local folder, dir = location_of(sdk, framework)
        if folder == nil then
            totals.not_in_sdk = totals.not_in_sdk + 1
        else
            local has_map = os.isfile(path.join(sdk_folder(dir, framework), "Modules", "module.modulemap"))
            local has_sdk_headers = #os.files(path.join(dir, "Headers", "*.h")) > 0
            local result = render.render(framework, by_framework[framework] or {}, defs, arities, has_map, has_sdk_headers, usr_dirs)
            write_all(out, folder, framework, result)
            totals.frameworks = totals.frameworks + 1
            totals.files = totals.files + result.counts.files
            totals.lines = totals.lines + (result.counts.lines or 0)
            for kind, n in pairs(result.counts.declarations) do
                totals.declarations[kind] = (totals.declarations[kind] or 0) + n
            end
            for reason, n in pairs(result.counts.skipped) do
                totals.skipped[reason] = (totals.skipped[reason] or 0) + n
            end
        end
    end
    local kinds = {}
    for kind in pairs(totals.declarations) do kinds[#kinds + 1] = kind end
    table.sort(kinds)
    print(string.format("headers: %d frameworks written, %d not in the SDK's frameworks (usr/include), %d files, %d lines, %d s",
        totals.frameworks, totals.not_in_sdk, totals.files, totals.lines, os.time() - started))
    for _, kind in ipairs(kinds) do
        print(string.format("  declarations %-10s %d", kind, totals.declarations[kind]))
    end
    local reasons = {}
    for reason in pairs(totals.skipped) do reasons[#reasons + 1] = reason end
    table.sort(reasons)
    for _, reason in ipairs(reasons) do
        print(string.format("  skipped %-30s %d", reason, totals.skipped[reason]))
    end
    return 0
end

function run(args)
    if args.ir == nil then
        print("headers: needs --ir (the full 18-column IR)")
        return 2
    end
    local rows, by_framework = read_ir(args.ir)
    if args.compare then
        if args.framework == nil then
            print("headers: --compare needs --framework")
            return 2
        end
        return compare_mode(args, by_framework)
    end
    return write_mode(args, rows, by_framework)
end
