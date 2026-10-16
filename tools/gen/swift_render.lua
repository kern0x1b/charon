-- The Swift skeleton renderer: from the full model (swift_model.lua), the text of a module's declarations. Every line is built from
-- the model's own fields (kind, container, name, side, type, params, generic_sig, conformances, superclass, throwing, async,
-- mutating, attributes, accessors, storage, is_let, is_open, requirement, in_extension, owner_module, raw, availability); no
-- .swiftinterface is read, no comment of Apple's is copied and no layout of theirs is reproduced. A function body traps with the
-- member's name; a stored value is rendered as a computed property that traps, so the skeleton compiles without an initializer.

local order = import("order", {anonymous = true})

local NO_VALUE = "-"
local TYPE_KINDS = {["class"] = true, ["struct"] = true, ["enum"] = true, ["protocol"] = true, ["typealias"] = true}
-- The surface kinds whose name is a whole declaration (a member name is the printedName, e.g. "moved(dx:)") for a member, and the
-- bare name for a type.
local MEMBER_KINDS = {method = true, property = true, constant = true, ["function"] = true, ["associatedtype"] = true}
-- The Swift keywords a declared name cannot take bare: the digester gives the bare name, so a declaration named one of them is
-- spelled between backticks (an identifier in backticks is always legal, so the list may be generous). Initializers are not named.
local KEYWORDS = {}
for word in string.gmatch("Any Self as await associatedtype break case catch class continue default defer deinit do else enum "
                          .. "extension fallthrough false fileprivate for func guard if import in inout internal is let nil open "
                          .. "operator private protocol public repeat rethrows return self static struct subscript super switch "
                          .. "throw throws true try typealias var where while", "%S+") do
    KEYWORDS[word] = true
end

-- The name of a declaration as Swift spells it: a keyword is wrapped in backticks.
local function ident(name)
    if KEYWORDS[name] then
        return "`" .. name .. "`"
    end
    return name
end

-- The pieces of a name: the leaf before the first "(" and the label of each parameter, read from the printedName ("moved(dx:)",
-- "init(locale:preset:)", "hash(into:)", "==(_:_:)"). A name with no parenthesis has no labels.
local function name_parts(name)
    local open = string.find(name, "(", 1, true)
    if open == nil then
        return name, {}
    end
    local leaf = string.sub(name, 1, open - 1)
    local labels = {}
    for label in string.gmatch(string.sub(name, open + 1), "([^:]*):") do
        table.insert(labels, label)
    end
    return leaf, labels
end

-- The dump spells builtin types with their module ("Swift.Int"), but `Any` is a keyword, not a member of Swift: `Swift.Any` does
-- not parse. The frontier keeps a name beginning with "Any" (AnyObject, ...) untouched. The dump pads some of its names with
-- spaces ("Locale ,"), so the text is trimmed as well.
local function spell(text)
    if text == nil then
        return text
    end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    return (string.gsub(text, "Swift%.Any%f[%A]", "Any"))
end

-- The cells of a " | " joined list ("-"), or an empty list.
local function pipe_list(text)
    if text == nil or text == NO_VALUE then
        return {}
    end
    local out = {}
    for item in string.gmatch(text, "[^|]+") do
        table.insert(out, spell(item))
    end
    return out
end

-- The module qualifier of a type name (the first dotted part when it is a name), or nil. `Self` is a keyword, not a module.
local function module_of(name)
    local head = string.match(name, "^([_%a][%w_]*)%.")
    if head == nil or head == "any" or head == "some" or head == "Self" then
        return nil
    end
    return head
end

-- The imports a module needs: the module qualifiers of every type, conformance, superclass and generic signature that name a Swift
-- module of the SDK (known: the set of their names), less the module's own name and the Swift standard library (its declarations
-- are in scope without an import). A qualifier that is no module (a generic parameter such as T, the clang importer's C) is not
-- imported. public maps an implementation module to its public one: the compiler refuses an import of the first ("is an
-- implementation detail of"), and the public module re-exports its declarations, so the qualifier stays and only the import
-- changes.
local function imports_of(rows, framework, known, public)
    local seen, out = {}, {}
    local function import_of(module)
        return public[module] or module
    end
    local function add(module)
        if seen[module] == nil then
            seen[module] = true
            table.insert(out, module)
        end
    end
    local function scan(text)
        if text == nil then
            return
        end
        for name in string.gmatch(text, "[%.%w_]*[%w_]+") do
            local module = module_of(name)
            module = module and import_of(module)
            if module and known[module] and module ~= framework and module ~= "Swift" then
                add(module)
            end
        end
    end
    for _, r in ipairs(rows) do
        -- an extension of another module's type needs that module imported even when no member names it
        local owner = r.owner_module
        if owner ~= NO_VALUE then
            owner = import_of(owner)
            if owner ~= framework then
                add(owner)
            end
        end
        scan(r.type)
        scan(r.params)
        scan(r.conformances)
        scan(r.superclass)
        scan(r.generic_sig)
    end
    table.sort(out, order.less)
    return out
end

-- The generic clause and where clause of a type from its generic signature. A signature over Self (a protocol) yields no angle
-- brackets; the caller turns the Self constraints into inheritance. Returns params (angle-bracket text or nil) and whereclause.
local function generic_clause(signature)
    if signature == nil or signature == NO_VALUE then
        return nil, nil
    end
    signature = spell(signature)
    local body = string.match(signature, "^<(.*)>$")
    if body == nil then
        return nil, nil
    end
    local where_at = string.find(body, " where ", 1, true)
    local head = where_at and string.sub(body, 1, where_at - 1) or body
    local tail = where_at and string.sub(body, where_at + 7) or nil
    local terms = {}
    for term in string.gmatch(head, "[^,]+") do
        table.insert(terms, (string.gsub(term, "^%s+", "")))
    end
    local params = {}
    for _, term in ipairs(terms) do
        -- a parameter pack is "each T" in the signature, and the clause spells it so (the name alone would be "each")
        local pack, name = string.match(term, "^(each)%s+([%w_]+)")
        if name == nil then
            name = string.match(term, "^([%w_%.]+)")
        end
        if name and name ~= "Self" and string.find(term, ":") == nil and string.find(term, "==") == nil then
            table.insert(params, (pack and "each " or "") .. name)
        end
    end
    if #params == 0 then
        return nil, tail
    end
    return "<" .. table.concat(params, ", ") .. ">", tail
end

-- The constraints a protocol's generic signature puts on Self, as inheritance terms ("AnyObject", "Sendable").
local function protocol_self_inheritance(signature)
    if signature == nil or signature == NO_VALUE then
        return {}
    end
    local body = string.match(signature, "^<(.*)>$") or ""
    local out = {}
    for term in string.gmatch(body, "[^,]+") do
        term = (string.gsub(term, "^%s+", ""))
        local rest = string.match(term, "^Self%s*:%s*(.+)$")
        if rest then
            table.insert(out, (string.gsub(rest, "^%s+", "")))
        end
    end
    return out
end

-- The " : A, B" clause of a declaration from its superclass, its conformances (a list) and any extra terms.
local function inheritance_of(superclass, conformances, extra)
    local out = {}
    if superclass ~= nil and superclass ~= NO_VALUE then
        for s in string.gmatch(superclass, "[^,]+") do
            table.insert(out, spell(s))
        end
    end
    for _, c in ipairs(extra or {}) do
        table.insert(out, spell(c))
    end
    for _, c in ipairs(conformances) do
        table.insert(out, spell(c))
    end
    if #out == 0 then
        return ""
    end
    return ": " .. table.concat(out, ", ")
end

-- The `@available` attribute a row's availability asks for, or nil. The platform names are the IR's (ios, macos, ...).
local function availability_of(row)
    if row.availability == nil or row.availability == NO_VALUE then
        return nil
    end
    local names = {ios = "iOS", macos = "macOS", tvos = "tvOS", watchos = "watchOS", xros = "visionOS",
                   maccatalyst = "macCatalyst"}
    local parts = {}
    for token in string.gmatch(row.availability, "[^,]+") do
        local platform, version = string.match(token, "^(.-)=(.+)$")
        if platform and version and names[platform] then
            table.insert(parts, names[platform] .. " " .. version)
        end
    end
    if #parts == 0 then
        return nil
    end
    return "@available(" .. table.concat(parts, ", ") .. ", *)"
end

-- A body that traps with the declaration's name: the stub of a method, a function or a computed property.
local function trap(label)
    return ' { fatalError("' .. label .. '") }'
end

-- The declaration of one member: a method, a function, a property, a constant or an associated type. indent spaces lead each line.
-- access is the modifier the enclosing declaration needs ("public ", "open ") so the digester sees the member again; a protocol
-- requirement carries none (it is public by nature), and neither does an enum case or an associated type, which take none.
local function render_member(row, indent, access)
    local pad = string.rep(" ", indent)
    local avail = availability_of(row)
    local lines = {}
    local label = (row.container ~= NO_VALUE and (row.container .. "." .. row.name) or row.name)
    access = access or ""

    if row.kind == "swift-associatedtype" then
        table.insert(lines, pad .. "associatedtype " .. ident(row.name))
        return lines
    end
    if row.kind == "swift-constant" and row.container ~= NO_VALUE then
        -- an enum case: the surface kind is constant and the container is the enum
        table.insert(lines, pad .. "case " .. ident(row.name))
        return lines
    end
    -- a property, or a module-level constant (a variable with no container): a computed variable whose getter traps, since a
    -- constant needs its value and the skeleton has none
    if row.kind == "swift-property" or row.kind == "swift-constant" then
        local has_set = row.accessors ~= NO_VALUE and string.find(row.accessors, "set", 1, true)
        local override = row.overriding == "yes" and "override " or ""
        local head = pad .. access .. (row.side == "+" and "static " or "") .. override .. "var " .. ident(row.name) .. ": " .. spell(row.type)
        if avail then
            table.insert(lines, pad .. avail)
        end
        if access == "" then
            -- a protocol requirement has no body
            table.insert(lines, head .. (has_set and " { get set }" or " { get }"))
        elseif has_set then
            table.insert(lines, head .. " {")
            table.insert(lines, pad .. "    get" .. trap(label))
            table.insert(lines, pad .. "    set" .. trap(label))
            table.insert(lines, pad .. "}")
        else
            -- the shorthand getter, whose body traps
            table.insert(lines, head .. trap(label))
        end
        return lines
    end

    -- a method or a function
    local leaf, labels = name_parts(row.name)
    local types = pipe_list(row.params)
    local params = {}
    local first = leaf == "init" and 2 or 1
    for i = first, #types do
        local label_name = labels[i - first + 1]
        if label_name == nil or label_name == "" or label_name == "_" then
            table.insert(params, "_ p" .. (i - first) .. ": " .. types[i])
        else
            table.insert(params, label_name .. ": " .. types[i])
        end
    end
    local prefix = access
    if leaf ~= "init" and row.side == "+" then prefix = prefix .. "static " end
    if row.overriding == "yes" then prefix = prefix .. "override " end
    -- an initializer of a class: required when the dump says so, convenience when its init kind is (a protocol's has no access
    -- and takes neither)
    if leaf == "init" and access ~= "" then
        if string.find(row.attributes, "Required", 1, true) then prefix = prefix .. "required " end
        if row.init_kind == "Convenience" then prefix = prefix .. "convenience " end
    end
    if row.mutating == "Mutating" then prefix = prefix .. "mutating " end
    local gparams, gwhere = generic_clause(row.generic_sig)
    local signature
    if leaf == "init" then
        signature = "init" .. (gparams or "") .. "(" .. table.concat(params, ", ") .. ")"
    elseif leaf == "subscript" then
        signature = "subscript" .. (gparams or "") .. "(" .. table.concat(params, ", ") .. ")"
    else
        signature = "func " .. ident(leaf) .. (gparams or "") .. "(" .. table.concat(params, ", ") .. ")"
    end
    if row.async == "yes" then signature = signature .. " async" end
    if row.throwing == "yes" then signature = signature .. " throws" end
    if leaf ~= "init" and row.type ~= NO_VALUE then
        signature = signature .. " -> " .. spell(row.type)
    end
    if gparams and gwhere then signature = signature .. " where " .. gwhere end
    if avail then
        table.insert(lines, pad .. avail)
    end
    table.insert(lines, pad .. prefix .. signature .. (access == "" and "" or trap(label)))
    return lines
end

-- The conformances of a class row as a list, less the Actor conformance: an actor is declared with its keyword, not with a
-- conformance. Returns the list and whether the class is an actor.
local function conformances_of_row(row)
    local out, actor = {}, false
    if row.conformances == NO_VALUE then
        return out, false
    end
    for c in string.gmatch(row.conformances, "[^,]+") do
        if row.kind == "swift-class" and string.match(c, "([^.]+)$") == "Actor" then
            actor = true
        else
            table.insert(out, c)
        end
    end
    return out, actor
end

-- The conformances a class's superclass chain provides, as a set (name -> true): the conformances of each class above the class,
-- read from classes (the class rows of the SDK's modules keyed "Module.Api", swift_model.class_index). A superclass the index does
-- not hold provides none, and a chain that loops is cut where it meets itself.
local function chain_provides(superclass, classes)
    local provided, seen = {}, {}
    local function climb(names)
        if names == nil or names == NO_VALUE then
            return
        end
        for name in string.gmatch(names, "[^,]+") do
            local row = classes[name]
            if row ~= nil and not seen[name] then
                seen[name] = true
                for _, c in ipairs(conformances_of_row(row)) do
                    provided[c] = true
                end
                climb(row.superclass)
            end
        end
    end
    climb(superclass)
    return provided
end

-- The names of a generic signature's parameters, in order ("<T, each U>" gives {"T", "U"}; none when it has none).
local function parameter_names(signature)
    local names = {}
    local clause = generic_clause(signature)
    for term in string.gmatch(clause and string.match(clause, "^<(.*)>$") or "", "[^,]+") do
        table.insert(names, (string.gsub(string.gsub(term, "^%s+", ""), "^each ", "")))
    end
    return names
end

-- A superclass with the digester's canonical parameters spelled as the subclass's own. The digester writes a superclass's
-- argument that is the subclass's parameter as tau_0_I (the Greek letter, in UTF-8): the I-th parameter of the subclass's
-- generic signature. A canonical parameter the signature does not give is left as it is.
local function spell_canonical(superclass, signature)
    if superclass == nil or superclass == NO_VALUE then
        return superclass
    end
    local names = parameter_names(signature)
    return (string.gsub(superclass, "\207\132_0_(%d+)", function(index)
        return names[tonumber(index) + 1] or ("\207\132_0_" .. index)
    end))
end

-- The inheritance of a type row: its raw type, superclass and conformances, plus any extra. provided (a set, or nil) names the
-- conformances the superclass chain already gives: Swift rejects a class that lists one of them again, so the class does not.
local function type_inheritance(row, extra, provided)
    local conformances = conformances_of_row(row)
    if row.raw ~= NO_VALUE and row.kind == "swift-enum" then
        table.insert(conformances, 1, row.raw)
    end
    if provided ~= nil then
        local kept = {}
        for _, c in ipairs(conformances) do
            if not provided[c] then
                table.insert(kept, c)
            end
        end
        conformances = kept
    end
    return inheritance_of(spell_canonical(row.superclass, row.generic_sig), conformances, extra)
end

-- Renders one node (a type row, its nested types and its members). Own types get a declaration; a type of another module gets an
-- extension, since its declaration belongs to its module.
local function render_node(node, indent, framework, classes)
    local row = node.row
    local pad = string.rep(" ", indent)
    local lines = {}
    local avail = availability_of(row)

    if row.kind == "swift-typealias" then
        -- a typealias cannot spell an opaque type ("some P"): the digester gives a witness of that form as an alias, and none is
        -- rendered for it (the round trip reports it as missing)
        if string.find(row.alias, "^some ") then
            return lines
        end
        if avail then table.insert(lines, pad .. avail) end
        table.insert(lines, pad .. "public typealias " .. ident(row.name) .. " = " .. spell(row.alias))
        return lines
    end

    local external = row.owner_module ~= NO_VALUE
    local member_access = "public "
    if external then
        if avail then table.insert(lines, pad .. avail) end
        table.insert(lines, pad .. "extension " .. row.owner_module .. "." .. ident(row.name) .. type_inheritance(row) .. " {")
    else
        local keyword = ({["swift-class"] = "class", ["swift-struct"] = "struct", ["swift-enum"] = "enum",
                          ["swift-protocol"] = "protocol"})[row.kind]
        local is_protocol = row.kind == "swift-protocol"
        local _, actor = conformances_of_row(row)
        local access = "public "
        if actor then
            -- an actor is final and cannot be open: its keyword replaces the class's
            keyword = "actor"
        elseif row.attributes ~= NO_VALUE and string.find(row.attributes, "Final", 1, true) then
            access = "public final "
        elseif row.is_open == "yes" then
            access = "open "
        end
        -- a protocol's own signature constrains Self to the protocol itself (spelled <Name>P); that is not an inheritance term
        local extra = {}
        if is_protocol then
            for _, term in ipairs(protocol_self_inheritance(row.generic_sig)) do
                local last = string.match(term, "([^.]+)$")
                if last ~= row.name and last ~= (row.name .. "P") then
                    table.insert(extra, term)
                end
            end
            member_access = ""
        end
        local params, where = generic_clause(row.generic_sig)
        if is_protocol then where = nil end
        local provided = nil
        if classes ~= nil and row.kind == "swift-class" then
            provided = chain_provides(row.superclass, classes)
        end
        local inheritance = type_inheritance(row, extra, provided)
        local head = access .. keyword .. " " .. ident(row.name) .. (params or "") .. inheritance
        if where then head = head .. " where " .. where end
        if avail then table.insert(lines, pad .. avail) end
        table.insert(lines, pad .. head .. " {")
    end

    local requirements, extensions = {}, {}
    local raw_enum = row.kind == "swift-enum" and row.raw ~= NO_VALUE
    for _, member in ipairs(node.members) do
        -- a raw-value enum synthesizes these two itself; declaring them again is a redeclaration
        if raw_enum and (member.name == "rawValue" or member.name == "init(rawValue:)") then
            -- skip
        elseif row.kind == "swift-protocol" and member.in_extension == "yes" then
            table.insert(extensions, member)
        else
            table.insert(requirements, member)
        end
    end
    for _, member in ipairs(requirements) do
        for _, l in ipairs(render_member(member, indent + 4, member_access)) do
            table.insert(lines, l)
        end
    end
    for _, child in ipairs(node.children) do
        for _, l in ipairs(render_node(child, indent + 4, framework, classes)) do
            table.insert(lines, l)
        end
    end
    table.insert(lines, pad .. "}")

    -- a protocol's extension members live in an extension of their own
    if #extensions > 0 then
        local name = external and (row.owner_module .. "." .. ident(row.name)) or ident(row.name)
        table.insert(lines, "")
        table.insert(lines, pad .. "extension " .. name .. " {")
        for _, member in ipairs(extensions) do
            for _, l in ipairs(render_member(member, indent + 4, "public ")) do
                table.insert(lines, l)
            end
        end
        table.insert(lines, pad .. "}")
    end
    return lines
end

-- Groups the model rows into a tree: a type row becomes a node keyed by its api, its members and nested types attach to it, and a
-- declaration whose container is a type the model has no row for attaches to nothing (it is not rendered). Returns the top nodes and
-- the top-level members (functions, constants at module level).
function group(rows)
    local nodes, top, top_members = {}, {}, {}
    for _, row in ipairs(rows) do
        if TYPE_KINDS[string.match(row.kind, "^swift%-(.*)$")] then
            local api = row.container ~= NO_VALUE and (row.container .. "." .. row.name) or row.name
            local node = {row = row, members = {}, children = {}}
            nodes[api] = node
            local parent = row.container ~= NO_VALUE and nodes[row.container] or nil
            if parent then
                table.insert(parent.children, node)
            else
                table.insert(top, node)
            end
        else
            local parent = row.container ~= NO_VALUE and nodes[row.container] or nil
            if parent then
                table.insert(parent.members, row)
            elseif row.container == NO_VALUE then
                table.insert(top_members, row)
            end
        end
    end
    return top, top_members
end

-- The text of a module's Swift skeleton: a header, the imports, the module-level declarations and the types. known is the set of the
-- SDK's Swift module names (a set: name -> true). classes is the class index (swift_model.class_index) or nil: with it, a class lists
-- only the conformances its superclass chain does not already provide. public is the implementation modules' public modules
-- (swift_model.public_modules), or nil for none.
function render(rows, framework, known, classes, public)
    local lines = {
        "// GENERATED by tools/gen.lua swiftcode. Do not edit.",
        "// The Swift skeleton of " .. framework .. ", rendered from the declaration model.",
    }
    for _, module in ipairs(imports_of(rows, framework, known, public or {})) do
        table.insert(lines, "import " .. module)
    end
    local top, top_members = group(rows)
    for _, row in ipairs(top_members) do
        table.insert(lines, "")
        for _, l in ipairs(render_member(row, 0, "public ")) do
            table.insert(lines, l)
        end
    end
    for _, node in ipairs(top) do
        -- a declaration that renders to nothing (an opaque typealias) leaves no blank line behind
        local block = render_node(node, 0, framework, classes)
        if #block > 0 then
            table.insert(lines, "")
            for _, l in ipairs(block) do
                table.insert(lines, l)
            end
        end
    end
    return table.concat(lines, "\n") .. "\n"
end
