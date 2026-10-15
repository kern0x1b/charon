-- The headers of one framework, rendered from the typed columns of the declaration IR (design-foundation.md 5.1), in our own layout.
-- Pure: the rows of a framework and the definitions of the whole IR go in, the files' text comes out; cmd_headers.lua reads and
-- writes. The columns read are 1 to 16 (framework, kind, usr, container, name, side, header, line, availability, nullability, type,
-- params, attrs, value, declhash, availhash). The declaration as written (17) and the messages (18) are never read, and no comment
-- and no SDK header text is: the text is ours, from the typed cells only.
--
-- defs_of(all_rows) indexes the whole IR by the names it defines (an import is resolved from it). render(framework, rows, defs,
-- has_map, has_sdk_headers, usr_dirs) returns { files = {path under the framework's folder -> text}, counts = {...} }, the paths
-- being Headers/<header> and Modules/module.modulemap (the module map only when has_map: the SDK's framework has one). has_sdk_headers
-- says the SDK's folder holds headers: a framework with no module map and no declaration then keeps one empty header, so decls can
-- read the folder when the fallback list names it. usr_dirs maps each usr/include module to its import prefix. compare(ir_rows,
-- decl_rows) matches the IR's rows with the rows decls prints for the same framework, by the key (kind, usr, container, name,
-- side), and groups each difference by its cause.

local COL = {framework = 1, kind = 2, usr = 3, container = 4, name = 5, side = 6, header = 7, line = 8, avail = 9,
             nullability = 10, type = 11, params = 12, attrs = 13, value = 14, declhash = 15, availhash = 16}

-- Nullability letters of column 10 (n nonnull, l nullable, L nullable result, u unspecified, - none): the declarator keyword, and the
-- property attribute.
local DECLARATOR = {n = "_Nonnull", l = "_Nullable", L = "_Nullable", u = "_Null_unspecified"}
local ATTRIBUTE = {n = "nonnull", l = "nullable", L = "nullable", u = "null_unspecified"}

-- Every generated header is a system header, as the SDK's framework headers are (they are read through the sysroot). clang gives a
-- typedef in a header that is not a system header a USR with the file's name (c:File.h@T@Name), where the SDK's is c:@T@Name, and
-- the declhash covers the USR (measured on Speech: the enum typedefs differ until the pragma is there).
local SYSTEM_HEADER = "#pragma clang system_header"

-- The kinds that define a name a type can use: the definitions an import is resolved from.
local DEFINING = {interface = true, protocol = true, typedef = true, enum = true, struct = true, union = true}
-- The rows that are not declarations of the headers: the IR's bookkeeping. Accessors are not rendered (clang synthesises them).
local BOOKKEEPING = {census = true, unparsed = true, meta = true}
-- The words of the C type grammar and of Objective-C's type keywords: never a name a file has to declare.
local KEYWORDS = {void = true, char = true, int = true, long = true, short = true, unsigned = true, signed = true, float = true,
                  double = true, const = true, volatile = true, _Bool = true, bool = true, id = true, Class = true, SEL = true,
                  instancetype = true, struct = true, union = true, enum = true, _Nullable = true, _Nonnull = true,
                  _Null_unspecified = true}

-- The first n cells of a line. The cells after them are not split, so the declaration and the message are never read.
local function split_cells(line, n)
    local cells, pos = {}, 1
    for i = 1, n do
        local tab = string.find(line, "\t", pos, true)
        if tab then
            cells[i] = string.sub(line, pos, tab - 1)
            pos = tab + 1
        else
            cells[i] = string.sub(line, pos)
            pos = #line + 2
        end
    end
    return cells
end

-- The pieces of a text between a plain separator.
local function split(text, sep)
    local out, pos = {}, 1
    while true do
        local at = string.find(text, sep, pos, true)
        if not at then
            out[#out + 1] = string.sub(text, pos)
            return out
        end
        out[#out + 1] = string.sub(text, pos, at - 1)
        pos = at + #sep
    end
end

local function trim(text)
    return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end

-- A parameter entry ("NSURL * languageModel") as its type and its name. The name is the last word of the entry, unless that word is
-- a C word ("unsigned int") or the entry ends in a sign ("NSURL *", "void (^)(NSError *)"): then the parameter is unnamed.
local function parameter(entry)
    entry = trim(entry)
    local name = string.match(entry, "([%a_][%w_]*)$")
    if name == nil or KEYWORDS[name] or name == entry then return entry, "" end
    return trim(string.sub(entry, 1, #entry - #name)), name
end

-- The parameters of a row, each { type, name, nullability }; the nullability letters are one per parameter, comma separated.
local function parameters_of(params, nullability)
    local out = {}
    if params == "-" then return out end
    local nulls = split(nullability, ",")
    for i, entry in ipairs(split(params, " | ")) do
        local ty, name = parameter(entry)
        out[i] = {type = ty, name = name, nullability = nulls[i] or "-"}
    end
    return out
end

-- A declarator: the type with its name and nullability. A keyword follows a pointer or a typedef name ("NSURL * _Nonnull name"),
-- and sits inside a block's declarator ("void (^ _Nullable name)(...)"). A name of "" is the bare type of a parameter or a result.
local function declare(ty, name, nullability)
    local keyword = DECLARATOR[nullability]
    if string.find(ty, "(^)", 1, true) then
        local inner = (keyword and (" " .. keyword) or "") .. name
        return (string.gsub(ty, "%(%^%)", "(^" .. inner .. ")", 1))
    end
    local out = ty
    if keyword then out = out .. " " .. keyword end
    if name ~= "" then out = out .. " " .. name end
    return out
end

-- A method's result. instancetype carries its nullability as a prefix: "nonnull instancetype".
local function result_of(ty, nullability)
    if ty == "instancetype" and ATTRIBUTE[nullability] then return ATTRIBUTE[nullability] .. " instancetype" end
    return declare(ty, "", nullability)
end

-- A function's type is "RESULT (ARGUMENT TYPES)": the result, and the argument list (the text of the last balanced parentheses).
local function split_suffix(ty)
    if string.sub(ty, -1) ~= ")" then return ty, "" end
    local depth = 0
    for i = #ty, 1, -1 do
        local ch = string.sub(ty, i, i)
        if ch == ")" then
            depth = depth + 1
        elseif ch == "(" then
            depth = depth - 1
            if depth == 0 then return trim(string.sub(ty, 1, i - 1)), string.sub(ty, i) end
        end
    end
    return ty, ""
end

-- The availability of column 9 as attributes. *unavailable and *deprecated are for every platform; a platform token is
-- platform=introduced/deprecated/obsoleted/unavailable, - when absent, and 1 for an unavailable platform. Attributes come in the
-- order of the column.
local function availability(text)
    if text == "-" then return "" end
    local out = {}
    for token in string.gmatch(text, "[^,]+") do
        -- a flag for every platform leads the column, alone or before the first platform ("*unavailable ios=10.0/-/-/0")
        local star, rest = string.match(token, "^%*(%a+)%s*(.*)$")
        if star == "unavailable" or star == "deprecated" then
            out[#out + 1] = "__attribute__((" .. star .. "))"
            token = rest
        end
        if token ~= "" then
            local plat, intro, dep, obs, flag = string.match(token, "^([^=]+)=([^/]+)/([^/]+)/([^/]+)/(%d+)$")
            assert(plat, "availability token: " .. token)
            local parts = {}
            if flag == "1" then parts[#parts + 1] = "unavailable" end
            if intro ~= "-" then parts[#parts + 1] = "introduced=" .. intro end
            if dep ~= "-" then parts[#parts + 1] = "deprecated=" .. dep end
            if obs ~= "-" then parts[#parts + 1] = "obsoleted=" .. obs end
            if #parts > 0 then
                out[#out + 1] = "__attribute__((availability(" .. plat .. "," .. table.concat(parts, ",") .. ")))"
            end
        end
    end
    return table.concat(out, " ")
end

-- The names a type text uses, into out: name -> "def" (its definition is needed: a typedef, a tag, a non-pointer use), "class" (a
-- word followed by *: a forward declaration is enough), or "protocol" (a word inside <...>).
local function type_names(text, out)
    for start, word in string.gmatch(text, "()([%a_][%w_]*)") do
        if not KEYWORDS[word] then
            local before = string.match(string.sub(text, 1, start - 1), "(%S+)%s*$") or ""
            local after = string.match(text, "^%s*(.)", start + #word) or ""
            -- inside <...>: a protocol list (id<P>) names a protocol, a generic argument (NSArray<C *> *) a class, as a pointer does
            local inside_angles = string.match(string.sub(text, 1, start - 1), "<[^>]*$") ~= nil
            local kind
            if before == "struct" or before == "union" or before == "enum" then
                kind = "def"
            elseif after == "*" then
                kind = "class"
            elseif inside_angles then
                kind = "protocol"
            else
                kind = "def"
            end
            if out[word] ~= "def" then out[word] = kind end
        end
    end
    return out
end

-- The names of the whole IR: name -> the rows that define it (framework and header), in IR order.
function defs_of(rows)
    local defs = {}
    for _, row in ipairs(rows) do
        local name = row[COL.name]
        if DEFINING[row[COL.kind]] and row[COL.header] ~= "-" and name ~= "-" then
            local list = defs[name] or {}
            list[#list + 1] = {framework = row[COL.framework], header = row[COL.header], kind = row[COL.kind]}
            defs[name] = list
        end
    end
    return defs
end

-- The definition a name is imported from: the framework's own when it has one, else the first one of another framework.
local function pick(list, framework)
    if list == nil then return nil end
    for _, def in ipairs(list) do
        if def.framework == framework then return def end
    end
    return list[1]
end

-- A framework is imported by its last name segment (Outer/Inner is Inner).
local function module_name(framework)
    return string.match(framework, "([^/]+)$")
end

-- The #import of a definition, or nil. A definition whose header is an absolute path is one of the SDK's own headers: a framework's
-- Headers/ folder (<Name>/<header>, the innermost framework of a nested path) or usr/include (<header>). This framework's own header
-- is quoted, another framework's is <Name/header>.
local function import_of(def, framework, header, usr_dirs)
    local dir = usr_dirs[def.framework]
    if dir then return "#import <" .. dir .. "/" .. def.header .. ">" end
    if string.sub(def.header, 1, 1) == "/" then
        local name, rest = string.match(def.header, "([^/]+)%.framework/Headers/(.+)$")
        if name then return "#import <" .. name .. "/" .. rest .. ">" end
        rest = string.match(def.header, "/usr/include/(.+)$")
        if rest then return "#import <" .. rest .. ">" end
        return nil
    end
    if def.framework == framework then
        if def.header == header then return nil end
        return '#import "' .. def.header .. '"'
    end
    return "#import <" .. module_name(def.framework) .. "/" .. def.header .. ">"
end

-- The owner of a member by its USR: cs:<class> or pl:<protocol>; a category member's class is its (cs) name too.
local function owner_of(usr)
    local name = string.match(usr, "%(cs%)([^%(]+)")
    if name then return "cs:" .. name end
    name = string.match(usr, "%(pl%)([^%(]+)")
    if name then return "pl:" .. name end
    return nil
end

local function class_of(usr)
    return string.match(usr, "%(cs%)([^%(]+)")
end

local function is_optional(row)
    for attr in string.gmatch(row[COL.attrs], "[^,]+") do
        if attr == "optional" then return true end
    end
    return false
end

-- A method or a property as its declaration (without the section it sits in).
local function member_text(row)
    local avail = availability(row[COL.avail])
    local suffix = avail ~= "" and (" " .. avail) or ""
    if row[COL.kind] == "property" then
        local attrs, has_class = {}, false
        for attr in string.gmatch(row[COL.attrs], "[^,]+") do
            if attr == "class" then has_class = true end
            if attr ~= "optional" and attr ~= "-" then attrs[#attrs + 1] = attr end
        end
        if ATTRIBUTE[row[COL.nullability]] then attrs[#attrs + 1] = ATTRIBUTE[row[COL.nullability]] end
        if row[COL.side] == "+" and not has_class then attrs[#attrs + 1] = "class" end
        local head = #attrs > 0 and ("@property (" .. table.concat(attrs, ", ") .. ") ") or "@property "
        return head .. declare(row[COL.type], row[COL.name], "-") .. suffix .. ";"
    end
    local sign = row[COL.side] == "+" and "+" or "-"
    local result_nullability, param_nullability = string.match(row[COL.nullability], "^([^|]*)|(.*)$")
    assert(result_nullability, "nullability column without |: " .. row[COL.nullability])
    local params = parameters_of(row[COL.params], param_nullability)
    local selector = row[COL.name]
    local result = "(" .. result_of(row[COL.type], result_nullability) .. ")"
    if #params == 0 then
        return sign .. " " .. result .. selector .. suffix .. ";"
    end
    local pieces = {}
    for piece in string.gmatch(selector, "[^:]*:") do pieces[#pieces + 1] = piece end
    assert(#pieces == #params, "selector " .. selector .. " has " .. #pieces .. " parts for " .. #params .. " parameters")
    local out = {sign .. " " .. result}
    for i, param in ipairs(params) do
        out[#out + 1] = pieces[i] .. "(" .. declare(param.type, "", param.nullability) .. ")" .. param.name
    end
    return table.concat(out, " ") .. suffix .. ";"
end

-- The member declarations of one owner: the required ones, then an @optional section when some are optional.
local function members_text(list)
    local required, optional = {}, {}
    for _, row in ipairs(list or {}) do
        local target = is_optional(row) and optional or required
        target[#target + 1] = "  " .. member_text(row)
    end
    local lines = required
    if #optional > 0 then
        lines[#lines + 1] = "@optional"
        for _, text in ipairs(optional) do lines[#lines + 1] = text end
    end
    return lines
end

-- The attribute text after a declarator (a space and it, or nothing).
local function suffix_of(attributes)
    return attributes ~= "" and (" " .. attributes) or ""
end

-- A file's names: a definition it needs wins over a forward declaration.
-- Each name keeps both facts a use can give: that its definition is needed (def), and the forward declaration its class or protocol
-- use needs (forward). A use may come before the definition in the same header, so a definition does not replace a forward.
local function note(deps, name, use)
    if name == nil or KEYWORDS[name] then return end
    local entry = deps[name] or {}
    if use == "def" then
        entry.def = true
    else
        entry.forward = entry.forward or use
    end
    deps[name] = entry
end

local function note_type(deps, text)
    for name, use in pairs(type_names(text, {})) do note(deps, name, use) end
end

-- The names a method or a property uses: its result or type, and its parameters' types.
local function note_member(deps, row)
    note_type(deps, row[COL.type])
    if row[COL.kind] == "method" and row[COL.params] ~= "-" then
        for _, p in ipairs(parameters_of(row[COL.params], "-")) do note_type(deps, p.type) end
    end
end

function render(framework, rows, defs, has_map, has_sdk_headers, usr_dirs)
    local counts = {declarations = {}, skipped = {}}
    local function count(kind, n)
        counts.declarations[kind] = (counts.declarations[kind] or 0) + (n or 1)
    end
    local function skip(reason)
        counts.skipped[reason] = (counts.skipped[reason] or 0) + 1
    end

    -- sort the rows: the ones a top-level declaration owns, and the ones its block takes
    local enumconsts, fields, supers, conforms, members, cat_members, tops = {}, {}, {}, {}, {}, {}, {}
    for _, row in ipairs(rows) do
        local kind = row[COL.kind]
        if BOOKKEEPING[kind] then
            if kind ~= "meta" then skip(kind) end
        elseif kind == "accessor" then
            skip("accessor (synthesised by clang)")
        elseif kind == "enumconst" then
            local list = enumconsts[row[COL.container]] or {}
            list[#list + 1] = row
            enumconsts[row[COL.container]] = list
        elseif kind == "field" then
            local list = fields[row[COL.container]] or {}
            list[#list + 1] = row
            fields[row[COL.container]] = list
        elseif kind == "super" then
            supers[row[COL.container]] = supers[row[COL.container]] or row[COL.name]
        elseif kind == "conforms" then
            local list = conforms[row[COL.container]] or {}
            list[#list + 1] = row[COL.name]
            conforms[row[COL.container]] = list
        elseif kind == "method" or kind == "property" then
            if row[COL.container] == "-" then
                local owner = owner_of(row[COL.usr])
                if owner == nil then
                    skip("member without an owner")
                else
                    local list = members[owner] or {}
                    list[#list + 1] = row
                    members[owner] = list
                end
            else
                local key = (class_of(row[COL.usr]) or "?") .. "@" .. row[COL.container]
                local list = cat_members[key] or {}
                list[#list + 1] = row
                cat_members[key] = list
            end
        elseif row[COL.header] == "-" then
            skip("no header (" .. kind .. ")")
        elseif string.sub(row[COL.header], 1, 1) == "/" then
            -- an absolute path: the typedef is declared by another SDK header, and this framework's headers do not declare it
            skip("typedef from another SDK header (absolute path)")
        else
            tops[#tops + 1] = row
        end
    end

    -- the blocks of each header, in IR order: text, the names it needs, and the names it defines
    local blocks, header_order = {}, {}
    local function block_of(header)
        if blocks[header] == nil then
            blocks[header] = {text = {}, deps = {}, defined = {}}
            header_order[#header_order + 1] = header
        end
        return blocks[header]
    end

    -- the tags this framework defines (enum, struct, union), with the header of each; a typedef of one waits for it (see typedef)
    local tags, emitted_tags, pending = {}, {}, {}
    for _, row in ipairs(tops) do
        local kind = row[COL.kind]
        if (kind == "enum" or kind == "struct" or kind == "union") and row[COL.name] ~= "-" then
            tags[row[COL.name]] = row[COL.header]
        end
    end

    for _, row in ipairs(tops) do
        local kind = row[COL.kind]
        local block = block_of(row[COL.header])
        local name = row[COL.name]
        local avail = availability(row[COL.avail])
        local prefix = avail ~= "" and (avail .. "\n") or ""
        local text
        if kind == "enum" then
            if name == "-" then
                skip("anonymous enum")
            else
                local base = row[COL.type]
                local lines = {prefix .. "enum " .. name .. (base ~= "-" and (" : " .. base) or "") .. " {"}
                if base ~= "-" then note_type(block.deps, base) end
                for _, c in ipairs(enumconsts[name] or {}) do
                    local attr = availability(c[COL.avail])
                    local value = c[COL.value] ~= "-" and (" = " .. c[COL.value]) or ""
                    lines[#lines + 1] = "  " .. c[COL.name] .. (attr ~= "" and (" " .. attr) or "") .. value .. ","
                end
                lines[#lines + 1] = "};"
                text = table.concat(lines, "\n")
                count("enumconst", #(enumconsts[name] or {}))
            end
        elseif kind == "typedef" then
            if string.find(row[COL.type], "unnamed", 1, true) then
                skip("typedef of an anonymous tag")
            else
                text = "typedef " .. declare(row[COL.type], name, row[COL.nullability]) .. suffix_of(avail) .. ";"
                note_type(block.deps, row[COL.type])
                -- a typedef of a tag the same header defines comes after the tag's definition (clang reads a typedef of an enum
                -- before its definition as a fixed-type enum otherwise), so it waits for the definition
                local tag = string.match(row[COL.type], "^%a+ (%S+)$")
                if tag and tags[tag] == row[COL.header] and not emitted_tags[tag] then
                    pending[tag] = text
                    text = nil
                end
            end
        elseif kind == "struct" or kind == "union" then
            if name == "-" then
                skip("anonymous " .. kind)
            else
                local lines = {prefix .. kind .. " " .. name .. " {"}
                for _, f in ipairs(fields[name] or {}) do
                    local attr = availability(f[COL.avail])
                    lines[#lines + 1] = "  " .. declare(f[COL.type], f[COL.name], f[COL.nullability])
                        .. (attr ~= "" and (" " .. attr) or "") .. ";"
                    note_type(block.deps, f[COL.type])
                end
                lines[#lines + 1] = "};"
                text = table.concat(lines, "\n")
                count("field", #(fields[name] or {}))
            end
        elseif kind == "function" then
            local result, suffix = split_suffix(row[COL.type])
            local result_nullability = string.match(row[COL.nullability], "^([^|]*)") or "-"
            local args = parameters_of(row[COL.params], string.match(row[COL.nullability], "|(.*)$") or "-")
            local decls = {}
            for i, a in ipairs(args) do
                decls[i] = declare(a.type, a.name, a.nullability)
                note_type(block.deps, a.type)
            end
            if string.find(row[COL.attrs], "variadic", 1, true) then decls[#decls + 1] = "..." end
            note_type(block.deps, result)
            text = "extern " .. declare(result, "", result_nullability) .. " " .. name
                .. "(" .. (#decls > 0 and table.concat(decls, ", ") or "void") .. ")" .. suffix_of(avail) .. ";"
        elseif kind == "var" then
            text = "extern " .. declare(row[COL.type], name, row[COL.nullability]) .. suffix_of(avail) .. ";"
            note_type(block.deps, row[COL.type])
        elseif kind == "interface" then
            local super = supers[name]
            local protocols, seen = {}, {}
            for _, p in ipairs(conforms[name] or {}) do
                if not seen[p] then
                    seen[p] = true
                    protocols[#protocols + 1] = p
                    note(block.deps, p, "def")
                end
            end
            local head = prefix
            if super == nil then head = head .. "__attribute__((objc_root_class))\n" end
            head = head .. "@interface " .. name .. (super and (" : " .. super) or "")
            if #protocols > 0 then head = head .. " <" .. table.concat(protocols, ", ") .. ">" end
            if super then note(block.deps, super, "def") end
            local lines = {head}
            for _, line in ipairs(members_text(members["cs:" .. name])) do lines[#lines + 1] = line end
            for _, m in ipairs(members["cs:" .. name] or {}) do note_member(block.deps, m) end
            count("member", #(members["cs:" .. name] or {}))
            lines[#lines + 1] = "@end"
            text = table.concat(lines, "\n")
        elseif kind == "protocol" then
            local protocols = {}
            for _, p in ipairs(conforms[name] or {}) do
                protocols[#protocols + 1] = p
                note(block.deps, p, "def")
            end
            local head = prefix .. "@protocol " .. name
            if #protocols > 0 then head = head .. " <" .. table.concat(protocols, ", ") .. ">" end
            local lines = {head}
            for _, line in ipairs(members_text(members["pl:" .. name])) do lines[#lines + 1] = line end
            for _, m in ipairs(members["pl:" .. name] or {}) do note_member(block.deps, m) end
            count("member", #(members["pl:" .. name] or {}))
            lines[#lines + 1] = "@end"
            text = table.concat(lines, "\n")
        elseif kind == "category" and name == "-" then
            -- a class extension (c:objc(ext)Class): its members are rows of the class's own (cs) owner, so the class block takes them
            skip("class extension (its members are the class's)")
        elseif kind == "category" then
            local class = string.match(row[COL.usr], "%(cy%)([^@]+)@")
            assert(class, "category USR without a class: " .. row[COL.usr])
            note(block.deps, class, "def")
            local key = class .. "@" .. name
            local lines = {prefix .. "@interface " .. class .. " (" .. name .. ")"}
            for _, line in ipairs(members_text(cat_members[key])) do lines[#lines + 1] = line end
            for _, m in ipairs(cat_members[key] or {}) do note_member(block.deps, m) end
            count("member", #(cat_members[key] or {}))
            lines[#lines + 1] = "@end"
            text = table.concat(lines, "\n")
        else
            skip("unknown kind " .. kind)
        end
        if text then
            block.text[#block.text + 1] = text
            count(kind)
            if DEFINING[kind] or kind == "function" or kind == "var" then
                block.defined[name] = true
            end
            if (kind == "enum" or kind == "struct" or kind == "union") and name ~= "-" then
                emitted_tags[name] = true
                if pending[name] then
                    block.text[#block.text + 1] = pending[name]
                    pending[name] = nil
                    count("typedef")
                end
            end
        end
    end

    for tag in pairs(pending) do
        error("typedef of " .. tag .. " waits for a definition that was never emitted")
    end

    -- the files: each header's imports (a definition from another header, or from another framework) and forward declarations,
    -- then its blocks
    local files = {}
    local headers = {}
    for _, header in ipairs(header_order) do headers[#headers + 1] = header end
    table.sort(headers)
    local base = module_name(framework)
    for _, header in ipairs(headers) do
        local block = blocks[header]
        local names = {}
        for name in pairs(block.deps) do names[#names + 1] = name end
        table.sort(names)
        local imports, forwards = {}, {}
        for _, name in ipairs(names) do
            local entry = block.deps[name]
            if entry.def and not block.defined[name] then
                local def = pick(defs[name], framework)
                local line = def and import_of(def, framework, header, usr_dirs)
                if line then imports[#imports + 1] = line end
            end
            -- a class or protocol is forward-declared even when this header defines it, since a use may come before the definition
            if entry.forward == "class" then
                forwards[#forwards + 1] = "@class " .. name .. ";"
            elseif entry.forward == "protocol" then
                forwards[#forwards + 1] = "@protocol " .. name .. ";"
            end
        end
        local head, seen = {}, {}
        for _, line in ipairs(imports) do
            if not seen[line] then
                seen[line] = true
                head[#head + 1] = line
            end
        end
        if #head > 0 and #forwards > 0 then head[#head + 1] = "" end
        for _, line in ipairs(forwards) do head[#head + 1] = line end
        local parts = {}
        if #head > 0 then parts[#parts + 1] = table.concat(head, "\n") end
        parts[#parts + 1] = table.concat(block.text, "\n\n")
        files["Headers/" .. header] = SYSTEM_HEADER .. "\n" .. table.concat(parts, "\n\n") .. "\n"
    end

    if not has_map and #headers == 0 and has_sdk_headers then
        -- a framework with no module map and no declaration of its own: its SDK folder holds headers that decls reads when the
        -- fallback list names the framework, so the folder keeps one empty header (no declaration in it)
        files["Headers/" .. base .. ".h"] = SYSTEM_HEADER .. "\n"
        counts.placeholder = true
    end
    if has_map then
        -- the umbrella: the IR's own <base>.h when it has one, else a header that imports the others
        local umbrella = base .. ".h"
        if files["Headers/" .. umbrella] == nil then
            local lines = {}
            for _, header in ipairs(headers) do lines[#lines + 1] = '#import "' .. header .. '"' end
            files["Headers/" .. umbrella] = SYSTEM_HEADER .. "\n" .. table.concat(lines, "\n") .. "\n"
            counts.generated_umbrella = true
        end
        local map = {"framework module " .. base .. " {", '  umbrella header "' .. umbrella .. '"', "  export *"}
        for _, header in ipairs(headers) do
            if header ~= umbrella then map[#map + 1] = '  header "' .. header .. '"' end
        end
        map[#map + 1] = "}"
        files["Modules/module.modulemap"] = table.concat(map, "\n") .. "\n"
    end
    counts.files = 0
    for path_name, text in pairs(files) do
        counts.files = counts.files + 1
        local _, newlines = string.gsub(text, "\n", "\n")
        counts.lines = (counts.lines or 0) + newlines
    end
    return {files = files, counts = counts}
end

-- The key of a row: kind, usr, container, name and side (columns 2 to 6).
local function key_of(row)
    return table.concat({row[COL.kind], row[COL.usr], row[COL.container], row[COL.name], row[COL.side]}, "\t")
end

-- The first column (of those the hash covers) where two rows with one key differ, for the cause of a declhash difference.
local COMPARED = {{COL.avail, "availability"}, {COL.nullability, "nullability"}, {COL.type, "type"}, {COL.params, "params"},
                  {COL.attrs, "attrs"}, {COL.value, "value"}}
local function differing_column(a, b)
    for _, c in ipairs(COMPARED) do
        if a[c[1]] ~= b[c[1]] then return c[2] end
    end
    return "no column"
end

-- The comparison of the IR's rows of one framework with decls' rows for it. Census and the other bookkeeping rows are not compared.
-- The result: ir and decls (the row counts), equal (rows with the key and the declhash), and causes: label -> count.
function compare(ir_rows, decl_rows)
    local expected = {}
    local report = {ir = 0, decls = 0, equal = 0, causes = {}}
    local function cause(label)
        report.causes[label] = (report.causes[label] or 0) + 1
    end
    for _, row in ipairs(ir_rows) do
        if not BOOKKEEPING[row[COL.kind]] then
            report.ir = report.ir + 1
            local key = key_of(row)
            expected[key] = expected[key] or {}
            table.insert(expected[key], row)
        end
    end
    for _, row in ipairs(decl_rows) do
        if not BOOKKEEPING[row[COL.kind]] then
            report.decls = report.decls + 1
            local list = expected[key_of(row)]
            if list and #list > 0 then
                local ir = table.remove(list, 1)
                if ir[COL.declhash] == row[COL.declhash] then
                    report.equal = report.equal + 1
                else
                    cause("declhash differs, " .. row[COL.kind] .. ": " .. differing_column(ir, row))
                end
            else
                cause("extra from decls, " .. row[COL.kind])
            end
        end
    end
    for _, list in pairs(expected) do
        for _, ir in ipairs(list) do cause("missing from decls, " .. ir[COL.kind]) end
    end
    return report
end

-- The rows of a text (the decls output or the IR), each the first 16 cells; decls' 17th and 18th cells are not read.
function rows_of(text)
    local rows = {}
    for line in string.gmatch(text, "[^\n]+") do
        rows[#rows + 1] = split_cells(line, 16)
    end
    return rows
end
