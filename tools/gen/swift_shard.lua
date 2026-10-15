-- The Swift declaration snapshot: one shard per Swift module of the SDK, spec/<F>/swift.tsv. A module's declarations are its API digester
-- dump (swift-api-digester -dump-sdk), run through coordination/heavy.sh and read from the dump's standard output by stream.lua: no file
-- is written. A row is one declaration of the dump in the IR's shape: the surface kind the scope matches (class, struct, enum, protocol,
-- typealias, method, property, constant, function), the Swift USR (the precise identifier), the container, the name, the side, the
-- declared type and the parameter types, the platform introductions, and the declaration hash (design section 5.3, the same canonical
-- text with nullability and attrs and value "-": Swift has none of them). The dump carries no declaration text and no availability
-- message, and it has the deprecation as a flag with no version: the availability cell holds the platform introductions only, and the
-- message is "-".

local layout = import("layout", {anonymous = true})
local stream = import("stream", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local files = import("files", {anonymous = true})
local digest = import("digest", {anonymous = true})
local strings = import("strings", {anonymous = true})
local emit = import("emit", {anonymous = true})
local order = import("order", {anonymous = true})
local json = import("core.base.json")

local SHARD_FILE = "swift.tsv"
local COLUMNS = {"framework", "kind", "usr", "container", "name", "side", "type", "params", "availability", "message", "declhash"}
local NO_VALUE = "-"
local KIND_PREFIX = "swift-"
local DIGESTER = "swift-api-digester"
-- The digester's declaration kinds that are types, and the surface kind each is.
local TYPE_KINDS = {Class = "class", Struct = "struct", Enum = "enum", Protocol = "protocol", TypeAlias = "typealias"}
-- The declarations that have a type (a result or a variable's type) and parameter types, in the dump's children.
local SIGNED_KINDS = {Func = true, Var = true, Constructor = true, Subscript = true}
-- The platform names the digester writes as intro_<name> (lower-cased; the Mac is "Macosx" there and "macos" in the IR).
local PLATFORM_NAMES = {macosx = "macos"}
-- The modules the snapshot leaves out, each with its reason: Accelerate is an umbrella whose Swift rows another band owns.
local LEFT_OUT = {Accelerate = "not this band's (the Accelerate umbrella's Swift rows)"}

-- The surface kind of a digester declaration, or nil when the declaration is not one the snapshot holds (an accessor, an associated type,
-- an import, a macro). in_type says whether the declaration sits in a type: a function there is a method, a variable a property.
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
        -- an enum case is a constant of its enum, the surface table's kind for it (measured on the unnamed rows: the 3,807 surface
        -- constants the shard held as property all sit under an enum, and none sits under a non-enum)
        return "constant"
    end
    return nil
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

-- The declared type and the parameter types of a signed declaration: a variable and a function have their result or type first, a
-- constructor's children are its parameters. Anything else has neither ("-").
local function signature_of(node, decl)
    if not SIGNED_KINDS[decl] then
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

-- The row of one declaration: the cells COLUMNS names. container is the api of the type the declaration sits in ("-" at module level).
local function row_of(framework, decl, node, container, kind, name)
    local usr = node.usr or NO_VALUE
    local side = node.static and "+" or "-"
    local result, params = signature_of(node, decl)
    local availability = availability_of(node)
    local declhash = digest.digest(KIND_PREFIX .. kind, usr, container, name, side, result, params, NO_VALUE, NO_VALUE, NO_VALUE, "")
    return {framework, KIND_PREFIX .. kind, usr, container, name, side, result, params, availability, NO_VALUE, declhash}
end

-- The qualified names of the types the dump spells: a type's usr maps to the name its uses print, without the module that declares it
-- ("AVFAudio.AVAudioSession.Location" is "AVAudioSession.Location", "SwiftUI.AccessibilityHeadingLevel" in SwiftUICore is the bare
-- "AccessibilityHeadingLevel"). A nested type the importer places in another type is declared at the top of the dump with its own name
-- alone; its uses carry the qualified name. A generic or tuple spelling is not a name and is not taken.
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

-- The api of a type declaration: its qualified name when the dump's uses give one whose last part is the declaration's own name, else the
-- container and the name.
local function type_api(node, label, container, qualified)
    local name = node.usr and qualified[node.usr]
    if name and string.match(name, "([^.]+)$") == label then
        return name
    end
    return container ~= NO_VALUE and (container .. "." .. label) or label
end

-- Walks the declarations of a node list, appending a row for each. container is the api of the type the declarations sit in, or "-".
-- A clang importer's declaration (moduleName "__ObjC", "__C": the module's own imports of the C and Objective-C types) is not the framework's
-- and is left out. A Swift declaration of another module is kept: a framework's public surface includes the declarations it re-exports
-- (SwiftUI's members that SwiftUICore declares).
local function walk(framework, nodes, container, qualified, rows)
    for _, node in ipairs(nodes or {}) do
        local decl = node.declKind
        local label = node.printedName or node.name
        local foreign = node.moduleName ~= nil and string.sub(node.moduleName, 1, 2) == "__"
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

-- The rows of one module's dump. Returns the rows, or nil and the reason the module has none (the digester writes an empty tree for a
-- module it cannot load, and exits 0).
local function dump_rows(heavy, sdk, triple, framework)
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
    local rows = {}
    walk(framework, root.children, NO_VALUE, qualified_names(root, {}), rows)
    if #rows == 0 then
        return nil, "the digester holds no Swift declaration of the module's own (an overlay of C or Objective-C types only, or not loaded)"
    end
    return rows
end

-- The module names of the SDK: every .swiftinterface's module (its .swiftmodule folder), once each, in byte order.
function modules(sdk)
    local seen, names = {}, {}
    for _, filepath in ipairs(files.glob(path.join(sdk, "**", "*.swiftinterface"))) do
        local module = string.match(filepath, "([^/]+)%.swiftmodule/[^/]+%.swiftinterface$")
        if module and not seen[module] then
            seen[module] = true
            table.insert(names, module)
        end
    end
    table.sort(names, order.less)
    return names
end

-- The target triple of the SDK's deployment target (SDKSettings.json: DefaultDeploymentTarget, read as the SDK states it).
function triple_of(sdk)
    local settings = json.decode(files.read_text(path.join(sdk, "SDKSettings.json")))
    assert(settings and settings.DefaultDeploymentTarget, "no DefaultDeploymentTarget in " .. sdk .. "/SDKSettings.json")
    return "arm64e-apple-ios" .. settings.DefaultDeploymentTarget
end

-- The shard path of a module under the package tree.
function shard_path(tree, framework)
    return path.join(tree, layout.constants().SNAP_ROOT, framework, SHARD_FILE)
end

-- Writes the shard of one module. Returns the number of rows, or nil and the reason the module has no shard.
function write_shard(tree, heavy, sdk, triple, framework)
    local rows, reason = dump_rows(heavy, sdk, triple, framework)
    if rows == nil then
        return nil, reason
    end
    emit.file(shard_path(tree, framework), strings.backslash_replace(tsv.table_text(COLUMNS, rows)))
    return #rows
end

-- The index of a framework's shard the scope reads: each declaration's surface kind and api, as "kind\tapi" keys, or nil when the framework
-- has no shard. The api is the scope's: the container, a dot, the name (the name alone at module level).
function index(tree, framework)
    local file = shard_path(tree, framework)
    if not os.isfile(file) then
        return nil
    end
    local keys = {}
    for _, r in ipairs(tsv.records(files.read_text(file))) do
        local api = r.container ~= NO_VALUE and (r.container .. "." .. r.name) or r.name
        keys[string.sub(r.kind, #KIND_PREFIX + 1) .. "\t" .. api] = true
    end
    return keys
end

-- The heavy.sh path (beside the corpus folder), the triple, and the modules the run covers (LEFT_OUT excluded): one module when framework
-- is given.
function plan(corpus, sdk, framework)
    local heavy = path.join(path.directory(corpus), "heavy.sh")
    assert(os.isfile(heavy), "no heavy.sh beside the corpus folder: " .. heavy)
    local names = framework and {framework} or modules(sdk)
    local out = {}
    for _, name in ipairs(names) do
        if LEFT_OUT[name] == nil then
            table.insert(out, name)
        end
    end
    return heavy, out, triple_of(sdk)
end
