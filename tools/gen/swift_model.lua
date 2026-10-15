-- The full Swift declaration model of the SDK's Swift modules: the same digester dump swift_shard.lua reads through stream.lua
-- (swift-api-digester -dump-sdk), walked into one row per declaration, holding every field the dump gives that a compilable
-- declaration needs and the shard has no column for: the mangled name, the generic signature, the conformances, the superclass,
-- throws/async/mutating, the accessors, attributes, protocol-requirement and extension state, storage and raw type. The committed
-- shard (spec/<F>/swift.tsv) is NOT touched: this is a build product, never committed (like ir.lua's IR_FULL). The container and
-- name of a row are the same the shard computes, so the declhash column is the shard's own digest.
--
-- async has no key of its own in the dump: the mangled name carries it, and it is read from there by swift-demangle in one batch per
-- module (the ABI encoding is the model's own data, not the interface text). A declaration the digester lists whose mangled name has
-- the async marker gets async="yes".

local swift_shard = import("swift_shard", {anonymous = true})
local stream = import("stream", {anonymous = true})
local digest = import("digest", {anonymous = true})
local order = import("order", {anonymous = true})
local files = import("files", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local json = import("core.base.json")

local DIGESTER = "swift-api-digester"
local DEMANGLER = "swift-demangle"
local NO_VALUE = "-"
local KIND_PREFIX = "swift-"
local ASYNC_MARKER = " async"
-- The digester's declaration kinds that are types, and the surface kind each is.
local TYPE_KINDS = {Class = "class", Struct = "struct", Enum = "enum", Protocol = "protocol", TypeAlias = "typealias"}
-- The platform names the digester writes as intro_<name> (lower-cased; the Mac is "Macosx" there).
local PLATFORM_NAMES = {macosx = "macos"}
-- The full model's columns: the shard's eleven (framework, kind, usr, container, name, side, type, params, availability, message,
-- declhash) first, so a model row carries the shard row as its prefix, then the fields the shard has no column for.
local MODEL_COLUMNS = {"framework", "kind", "usr", "container", "name", "side", "type", "params", "availability", "message",
                       "declhash", "mangled", "generic_sig", "conformances", "superclass", "throwing", "async", "mutating",
                       "attributes", "accessors", "storage", "is_let", "is_open", "requirement", "in_extension", "owner_module",
                       "raw", "alias", "overriding", "init_kind", "implicit"}

-- The model's columns, in order.
function columns()
    return MODEL_COLUMNS
end

-- The Swift module names of the SDK, in byte order (the same list the shard's command uses).
function modules(sdk)
    return swift_shard.modules(sdk)
end

-- The target triple of the SDK's deployment target.
function triple_of(sdk)
    return swift_shard.triple_of(sdk)
end

-- The digester's JSON root of one module, or nil and the reason it has none. A module the digester cannot load gets an empty tree
-- and an exit 0, so an empty root is a reason, not a failure.
function dump(heavy, sdk, triple, framework)
    local status, out, errors = stream.text(heavy, {"xcrun", DIGESTER, "-dump-sdk", "-module", framework, "-target", triple,
                                                     "-sdk", sdk, "-avoid-location", "-avoid-tool-args", "-o", "/dev/stdout"})
    if status ~= 0 then
        return nil, string.format("the digester exited %s: %s", tostring(status), string.sub(errors or "", -300))
    end
    local payload = json.decode(out)
    local root = payload and payload.ABIRoot
    if root == nil then
        return nil, "the digester wrote no ABI root"
    end
    return root
end

-- A cell as the model writes it: an absent field is "-".
local function dash(value)
    if value == nil or value == "" then
        return NO_VALUE
    end
    if value == true then
        return "yes"
    end
    return value
end

-- The platform introductions of a declaration, as "platform=version" tokens in byte order; "-" when it has none.
local function availability_of(node)
    local tokens = {}
    for key, value in pairs(node) do
        local platform = type(key) == "string" and string.match(key, "^intro_(.+)$")
        if platform and type(value) == "string" then
            table.insert(tokens, (PLATFORM_NAMES[string.lower(platform)] or string.lower(platform)) .. "=" .. value)
        end
    end
    if #tokens == 0 then
        return NO_VALUE
    end
    table.sort(tokens)
    return table.concat(tokens, ",")
end

-- The surface kind of a digester declaration, or nil when the snapshot holds no row for it. in_type says whether the declaration
-- sits in a type: a function there is a method, a variable a property (the same rule as the shard).
local function surface_kind(decl, in_type)
    if TYPE_KINDS[decl] then
        return TYPE_KINDS[decl]
    end
    if decl == "Func" then
        return in_type and "method" or "function"
    end
    if decl == "Constructor" or decl == "Subscript" then
        return "method"
    end
    if decl == "Var" then
        return in_type and "property" or "constant"
    end
    if decl == "EnumElement" then
        return "constant"
    end
    if decl == "AssociatedType" then
        return "associatedtype"
    end
    return nil
end

-- The declared type and the parameter types of a signed declaration, the shard's own rule (a variable's type, a function's result
-- then its parameters, a constructor's children are its parameters).
local function signature_of(node, decl)
    if decl ~= "Func" and decl ~= "Var" and decl ~= "Constructor" and decl ~= "Subscript" then
        return NO_VALUE, NO_VALUE
    end
    local children = {}
    for _, child in ipairs(node.children or {}) do
        table.insert(children, child.printedName or child.name or NO_VALUE)
    end
    if decl == "Constructor" then
        return NO_VALUE, #children > 0 and table.concat(children, " | ") or NO_VALUE
    end
    local params = {}
    for i = 2, #children do
        table.insert(params, children[i])
    end
    return children[1] or NO_VALUE, #params > 0 and table.concat(params, " | ") or NO_VALUE
end

-- The conformances a type declares, as their printed names in the dump's order; "-" when it declares none.
local function conformances_of(node)
    local out = {}
    for _, c in ipairs(node.conformances or {}) do
        table.insert(out, c.printedName or c.name or NO_VALUE)
    end
    return #out > 0 and table.concat(out, ",") or NO_VALUE
end

-- The superclass of a class, from the dump's superclassNames (the qualified spelling the uses print), or "-".
local function superclass_of(node)
    local names = node.superclassNames
    if type(names) == "table" and #names > 0 then
        return table.concat(names, ",")
    end
    return NO_VALUE
end

-- The accessor kinds of a variable or subscript, as "get,set"; "-" when the dump lists none.
local function accessors_of(node)
    local out = {}
    for _, a in ipairs(node.accessors or {}) do
        if a.accessorKind then
            table.insert(out, a.accessorKind)
        end
    end
    return #out > 0 and table.concat(out, ",") or NO_VALUE
end

-- The attributes the dump lists, in its order; "-" when there are none.
local function attributes_of(node)
    local out = {}
    for _, a in ipairs(node.declAttributes or {}) do
        table.insert(out, a)
    end
    return #out > 0 and table.concat(out, ",") or NO_VALUE
end

-- The qualified names of the types the dump spells, the shard's own reading.
local function qualified_names(node, out)
    if node.kind == "TypeNominal" and node.usr and node.printedName and out[node.usr] == nil then
        local name = string.match(node.printedName, "^[^.]+%.(.+)$")
        if name and not string.find(name, "[<%(%[ ]") then
            out[node.usr] = name
        end
    end
    for _, child in ipairs(node.children or {}) do
        qualified_names(child, out)
    end
    return out
end

-- The api of a type declaration: its qualified name when the dump's uses give one whose last part is the declaration's own name,
-- else the container and the name (the shard's type_api).
local function type_api(node, label, container, qualified)
    local name = node.usr and qualified[node.usr]
    if name and string.match(name, "([^.]+)$") == label then
        return name
    end
    return container ~= NO_VALUE and (container .. "." .. label) or label
end

-- The owner module of a declaration: the dump's moduleName, or the framework when it carries none. "-" when it is the framework's
-- own (not an extension of another module).
local function owner_module(node, framework)
    local module = node.moduleName
    if module == nil or module == framework then
        return NO_VALUE
    end
    return module
end

-- The type a typealias aliases, from its single child; "-" otherwise.
local function alias_of(node, decl)
    if decl ~= "TypeAlias" then
        return NO_VALUE
    end
    local child = (node.children or {})[1]
    return child and (child.printedName or child.name) or NO_VALUE
end

-- The row of one declaration, a record keyed by MODEL_COLUMNS. decl is the digester's declKind.
local function row_of(framework, decl, node, container, kind, name, async)
    local usr = node.usr or NO_VALUE
    local side = node.static and "+" or "-"
    local result, params = signature_of(node, decl)
    local availability = availability_of(node)
    local declhash = digest.digest(KIND_PREFIX .. kind, usr, container, name, side, result, params, NO_VALUE, NO_VALUE, NO_VALUE, "")
    local module = node.moduleName
    local foreign = module ~= nil and string.sub(module, 1, 2) == "__"
    return {
        framework = framework, kind = KIND_PREFIX .. kind, usr = usr, container = container, name = name, side = side,
        type = result, params = params, availability = availability, message = NO_VALUE, declhash = declhash,
        mangled = dash(node.mangledName), generic_sig = dash(node.genericSig), conformances = conformances_of(node),
        superclass = superclass_of(node), throwing = node.throwing and "yes" or NO_VALUE, async = async or NO_VALUE,
        mutating = dash(node.funcSelfKind), attributes = attributes_of(node), accessors = accessors_of(node),
        storage = node.hasStorage and "yes" or NO_VALUE, is_let = node.isLet and "yes" or NO_VALUE,
        is_open = node.isOpen and "yes" or NO_VALUE, requirement = node.protocolReq and "yes" or NO_VALUE,
        in_extension = node.isFromExtension and "yes" or NO_VALUE,
        owner_module = foreign and NO_VALUE or owner_module(node, framework),
        raw = dash(node.enumRawTypeName), alias = alias_of(node, decl), overriding = node.overriding and "yes" or NO_VALUE,
        init_kind = dash(node.init_kind), implicit = node.implicit and "yes" or NO_VALUE,
    }
end

-- Walks the declarations of a node list, appending a row for each. container is the api of the type the declarations sit in, or
-- "-". A clang importer's declaration (moduleName "__ObjC", "__C") is left out (the shard's rule).
local function walk(framework, nodes, container, qualified, rows)
    for _, node in ipairs(nodes or {}) do
        local decl = node.declKind
        local label = node.printedName or node.name
        local module = node.moduleName
        local foreign = module ~= nil and string.sub(module, 1, 2) == "__"
        local kind = surface_kind(decl, container ~= NO_VALUE)
        if kind and label and not foreign then
            if TYPE_KINDS[decl] then
                local api = type_api(node, label, container, qualified)
                local parent = string.match(api, "^(.*)%.[^.]+$") or NO_VALUE
                local leaf = string.match(api, "([^.]+)$")
                table.insert(rows, row_of(framework, decl, node, parent, kind, leaf))
                walk(framework, node.children, api, qualified, rows)
            else
                table.insert(rows, row_of(framework, decl, node, container, kind, label))
            end
        end
    end
end

-- The full model of one module's dump: a list of rows (records), or nil and the reason the module has none.
function rows(root, framework)
    local out = {}
    walk(framework, root.children, NO_VALUE, qualified_names(root, {}), out)
    if #out == 0 then
        return nil, "the digester holds no Swift declaration of the module's own"
    end
    return out
end

-- Fills each row's async cell from the demangled signature of its mangled name: the ABI encoding is where the dump keeps the async
-- marker. The demangler is given the mangled spelling ("$s...") and echoes one line per name, in order. It runs in chunks, so an
-- argument list stays under the system's limit whatever a module's count; the lines are joined in order. A row with no mangled name
-- keeps "-".
local DEMANGLE_CHUNK = 500
function annotate_async(rows, batch)
    local demangle = batch or function(names)
        local out, at = {}, 1
        while at <= #names do
            local chunk = {}
            for i = at, math.min(at + DEMANGLE_CHUNK - 1, #names) do
                table.insert(chunk, names[i])
            end
            local text = os.iorunv("xcrun", table.join({DEMANGLER}, chunk))
            for line in string.gmatch(text or "", "[^\n]+") do
                table.insert(out, line)
            end
            at = at + DEMANGLE_CHUNK
        end
        return out
    end
    local names = {}
    for _, r in ipairs(rows) do
        if r.mangled ~= NO_VALUE then
            table.insert(names, r.mangled)
        end
    end
    local lines = demangle(names)
    if #lines ~= #names then
        raise(string.format("swift-demangle answered %d lines for %d names", #lines, #names))
    end
    local index = 0
    for _, r in ipairs(rows) do
        if r.mangled ~= NO_VALUE then
            index = index + 1
            if string.find(lines[index], ASYNC_MARKER, 1, true) then
                r.async = "yes"
            end
        end
    end
    return rows
end

-- The row as a list of cells, in MODEL_COLUMNS order.
local function cells(row)
    local out = {}
    for i, name in ipairs(MODEL_COLUMNS) do
        out[i] = row[name]
    end
    return out
end

-- The TSV text of a model: the header, then one line per row, in ASCII.
function text(rows)
    local out = {}
    for _, r in ipairs(rows) do
        table.insert(out, cells(r))
    end
    return tsv.table_text(MODEL_COLUMNS, out)
end

-- The model of one module, read from the digester (async filled from the mangled names), or nil and the reason.
function model(heavy, sdk, triple, framework)
    local root, reason = dump(heavy, sdk, triple, framework)
    if root == nil then
        return nil, reason
    end
    local out, why = rows(root, framework)
    if out == nil then
        return nil, why
    end
    annotate_async(out)
    return out
end

-- Writes the model of one module under out_dir/<F>.tsv through emit. Returns the number of rows, or nil and the reason.
function write_model(heavy, sdk, triple, out_dir, framework)
    local out, reason = model(heavy, sdk, triple, framework)
    if out == nil then
        return nil, reason
    end
    emit_file(path.join(out_dir, framework .. ".tsv"), text(out))
    return #out
end

-- emit is imported lazily so the model can be tested without the writer.
local emit_module = nil
function emit_file(filepath, contents)
    if emit_module == nil then
        emit_module = import("emit", {anonymous = true})
    end
    emit_module.file(filepath, contents)
end
