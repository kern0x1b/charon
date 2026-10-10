-- The classes of the cells where a constant record differs from its reference (Round 14, decision 1). The reference is the oracle's
-- shard (the Python port's spec.sdk-26.2-headers.tsv, whose decl column stands for the record's type) or a committed record. Every
-- differing cell gets exactly one class from CLASSES, by a rule that is checked against an independent truth: the header text (a
-- scanner of each framework's declaration statements, comments removed), the iOS 26.2 cache table, the held-caches snapshot and the
-- owned snapshot. A cell no rule explains is unclassified, and the run fails while any remain.
--
-- A class rule is one function over the cell and its api's other cells (the decl and availability classes come first, the value
-- fields and the hash follow them). Nothing here reads the Lua record's derivation: the truth is read from the header and the tables.

local files = import("files", {anonymous = true})
local stream = import("stream", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local digest = import("digest", {anonymous = true})


-- The classes, in the order the ledger reports them. A rule that is switched off in a mutant leaves its cells unclassified.
CLASSES = {
    {"decl-whitespace", "the spelling differs only in whitespace"},
    {"decl-const-order", "the same tokens in another order (const before or after the type)"},
    {"decl-typedef-const", "the reference drops a const that the header's typedef supplies"},
    {"decl-oracle-macro-prefix", "the reference keeps the API and linkage macros written before the type"},
    {"decl-oracle-macro-trailing", "the reference keeps a macro written after the type (CV_NONNULL)"},
    {"decl-oracle-bleed", "the reference's line holds a quoted macro argument and runs into the next name"},
    {"decl-oracle-no-decl", "the reference finds no declaration line; the header declares the name"},
    {"decl-ir-macro-token", "the record's type spells a macro the reference's text does not; the header names that macro"},
    {"avail-next-line", "the reference reads the name's line only; the macros are on a later line"},
    {"avail-string-literal", "the reference's macro carries a string literal and stops at the name's line"},
    {"avail-name-line-prefix", "the reference holds the macros of the name's line; the rest are on later lines"},
    {"avail-reference-missed", "the reference reads no macros; the header's statement carries exactly the record's, on the name's line"},
    {"avail-name-line-subset", "the reference holds a run of the record's macros; the rest are on other lines of the statement"},
    {"avail-conditional-branch", "the reference adds a macro the header writes in a visionOS-only #if branch (the SDK takes the #else)"},
    {"hash-follows-inputs", "the hash differs because the declaration or availability it hashes differs"},
    {"hash-declared-text", "the record's hash recomputes from the header's declaration text (no declaration or availability differs)"},
    {"hash-leading-macro", "the record's hash keeps a macro of an earlier line and the linkage word after it; the reference's is the name's line"},
    {"value-status-decl", "a declaration the reference missed is recovered: the string shape is found"},
    {"value-follows-status", "the value, host value and source follow a recovered or owned status"},
    {"owned-input", "the owner is a snapshot input (spec/<F>/owned.tsv) the reference's run did not read"},
    {"measured-input", "the measured release is read back from measured.held-caches.tsv, not in the reference's run"},
    {"cache-drift", "the reference's iOS 26.2 cache label is not supported by the current cache table"},
    {"shape-follows-decl", "the string shape (cf or ns) follows the recovered declaration"},
}

-- The classes and their descriptions, as CLASSES holds them (an import exposes functions only)
function class_list()
    return CLASSES
end

local function is_word(c)
    return c ~= "" and string.match(c, "[%w_]") ~= nil
end

-- Comments removed; newlines and string literals kept (an availability macro's argument may be a string)
local function strip_comments(text)
    local out, i, n = {}, 1, #text
    while i <= n do
        local two = string.sub(text, i, i + 1)
        if two == "//" then
            i = string.find(text, "\n", i, true) or (n + 1)
        elseif two == "/*" then
            local e = string.find(text, "*/", i + 2, true)
            local stop = e and (e + 1) or n
            local _, newlines = string.gsub(string.sub(text, i, stop), "\n", "")
            table.insert(out, string.rep("\n", newlines))
            i = stop + 1
        else
            table.insert(out, string.sub(text, i, i))
            i = i + 1
        end
    end
    return table.concat(out)
end

-- The positions of the whole-word occurrences of name in text
local function occurrences(text, name)
    local out, init = {}, 1
    while true do
        local s, e = string.find(text, name, init, true)
        if s == nil then
            break
        end
        if not is_word(string.sub(text, s - 1, s - 1)) and not is_word(string.sub(text, e + 1, e + 1)) then
            table.insert(out, s)
        end
        init = e + 1
    end
    return out
end

-- The macro groups after a declarator: NAME(args) or an all-caps NAME; returns the groups and the character that ends them
local function parse_post(text, i)
    local groups = {}
    while true do
        local ws = string.match(text, "^%s*", i)
        local j = i + #ws
        local ident = string.match(text, "^[%a_][%w_]*", j)
        if ident == nil then
            break
        end
        local k = j + #ident
        local args = ""
        -- the arguments may follow after spaces (NS_SWIFT_NAME (automatic))
        local gap = string.match(text, "^%s*", k)
        if string.sub(text, k + #gap, k + #gap) == "(" then
            k = k + #gap
            local depth, m = 0, k
            repeat
                local c = string.sub(text, m, m)
                if c == "(" then
                    depth = depth + 1
                elseif c == ")" then
                    depth = depth - 1
                end
                m = m + 1
            until depth == 0 or m > #text
            args = string.sub(text, k, m - 1)
            k = m
        elseif string.match(ident, "^%u[%u%d_]*$") == nil then
            break
        end
        table.insert(groups, {name = ident, text = ident .. args, newline = string.find(ws, "\n", 1, true) ~= nil})
        i = k
    end
    return groups, string.match(text, "^%s*(.)", i) or ""
end

-- The declaration statement of name in text: the first whole-word occurrence whose declarator is followed by its macro groups and
-- ';' (or '=' or '['). Returns {pre = the tokens before the name, groups = the macro groups after it, raw = the statement with
-- comments removed, typedef = bool}, or nil.
local function statement_for(text, name)
    for _, s in ipairs(occurrences(text, name)) do
        local base = math.max(1, s - 3000)
        local start = base
        for pos in string.gmatch(string.sub(text, base, s - 1), "()[;{}]") do
            start = base + pos
        end
        local semi = string.find(text, ";", s + #name, true)
        if semi ~= nil then
            local window = "\n" .. strip_comments(string.sub(text, start, semi))
            window = string.gsub(window, "\n%s*#[^\n]*", "\n")
            for _, p in ipairs(occurrences(window, name)) do
                local groups, after = parse_post(window, p + #name)
                if after == ";" or after == "=" or after == "[" then
                    local pre = string.sub(window, 1, p - 1)
                    -- the window may start with an unterminated macro (NS_ASSUME_NONNULL_END), so the typedef is any word before the name
                    return {pre = pre, groups = groups, raw = string.sub(window, 2),
                            typedef = string.match(pre, "%f[%w_]typedef%f[^%w_]") ~= nil}
                end
            end
        end
    end
    return nil
end

local function tokens(s)
    local out = {}
    for w in string.gmatch(s, "%S+") do
        table.insert(out, w)
    end
    return out
end

local function sorted_key(list)
    local copy = {}
    for i, t in ipairs(list) do
        copy[i] = t
    end
    table.sort(copy)
    return table.concat(copy, " ")
end

local function nospace(s)
    return (string.gsub(s, "%s+", ""))
end

local LINKAGE = {extern = true, FOUNDATION_EXPORT = true, CF_EXPORT = true}
local NULLABILITY = {_Nonnull = true, __nonnull = true, _Nullable = true, __nullable = true}

-- The declaration text the record's hash is over, as the writer's declared_before takes it: the words before the name, without the
-- linkage word and the nullability words ("-" when the name is not in the text). The statement is read from the header, not the record.
local function declared_text(text, name)
    local s = occurrences(text, name)[1]
    if s == nil then
        return "-"
    end
    local head = string.gsub(string.sub(text, 1, s - 1), "^%s*", "")
    local first = string.match(head, "^([%w_]*)")
    if LINKAGE[first] or (first ~= "" and (string.find(first, "EXTERN", 1, true) or string.find(first, "EXPORT", 1, true))) then
        head = string.gsub(head, "^[%w_]*%s*", "", 1)
    end
    local words = {}
    for word in string.gmatch(head, "%S+") do
        if not NULLABILITY[word] then
            table.insert(words, word)
        end
    end
    return table.concat(words, " ")
end

-- The reference's declaration with its macro groups and linkage words removed; returns the tokens left and the removed ones
local function split_reference(decl)
    local rest = string.gsub(string.gsub(decl, "__attribute__%b()", " "), "[%u_][%u%d_]*%b()", " ")
    local left, removed = {}, {}
    for _, t in ipairs(tokens(rest)) do
        if LINKAGE[t] or string.match(t, "_EXPORT$") or string.match(t, "_EXTERN$") then
            table.insert(removed, t)
        else
            table.insert(left, t)
        end
    end
    return left, removed
end

-- The macros the record's availability holds: each identifier that names AVAILABLE, DEPRECATED or OBSOLETED (API_AVAILABLE,
-- API_UNAVAILABLE, MTR_DEPRECATED, NS_SWIFT_UNAVAILABLE) with its arguments, as the writer's availability_of takes them
local function is_api_macro(name)
    return string.find(name, "AVAILABLE", 1, true) ~= nil or string.find(name, "DEPRECATED", 1, true) ~= nil
           or string.find(name, "OBSOLETED", 1, true) ~= nil
end

-- The api macros written in a text (NAME(args), NAME an api macro), as the text gives them
local function api_macros_in(text)
    local out = {}
    for name, args in string.gmatch(text, "([%u_][%u%d_]*)(%b())") do
        if is_api_macro(name) then
            table.insert(out, name .. args)
        end
    end
    return out
end

local function api_groups_text(groups)
    local out = {}
    for _, g in ipairs(groups) do
        if is_api_macro(g.name) then
            table.insert(out, g.text)
        end
    end
    return nospace(table.concat(out, " "))
end

-- The availability the header gives a name: the api macros written before its declaration (on the lines above it) and the ones after
-- it, in the text's order, without spaces (the record's availability text, compared without its spacing)
local function header_avail_text(t)
    local lead = table.concat(api_macros_in(t.pre), " ")
    return nospace(lead .. " " .. api_groups_text(t.groups))
end

-- The context: the truth of one comparison. headers maps a framework to the text of its headers (the SDK's, or a test's);
-- cache maps a name to the value the 26.2 cache table holds for it (cfstring rows); held and owned map a name to a release and a
-- branch. Any of them may be empty.
function context(opts)
    local ctx = {headers = opts.headers or {}, cache = opts.cache or {}, held = opts.held or {}, owned = opts.owned or {},
                 truths = {}, typedef_consts = {}}

    function ctx.header_text(fw)
        return ctx.headers[fw] or ""
    end

    -- The declaration statement of a name in its framework's headers (false when none declares it, cached)
    function ctx.truth(fw, name)
        local key = fw .. "\n" .. name
        if ctx.truths[key] == nil then
            ctx.truths[key] = statement_for(ctx.header_text(fw), name) or false
        end
        return ctx.truths[key] or nil
    end

    -- A typedef of the header whose declarator is the name and whose declaration holds const (NSString *const X)
    function ctx.typedef_const(fw, name)
        local key = fw .. "\n" .. name
        if ctx.typedef_consts[key] == nil then
            local stmt = statement_for(ctx.header_text(fw), name)
            ctx.typedef_consts[key] = stmt ~= nil and stmt.typedef and string.match(stmt.pre, "%f[%w_]const%f[^%w_]") ~= nil
        end
        return ctx.typedef_consts[key]
    end

    return ctx
end

-- The rule of one class is applied to one cell. Returns the class name or nil. A cell carries: fw, api, column, lval (the record
-- being checked, the Lua), rval (the reference), and the per-api classes already assigned (decl, avail, status, source).
local RULES = {}

RULES["decl-whitespace"] = function(c)
    return c.column == "type" and nospace(c.lval) == nospace(c.rval)
end

RULES["decl-const-order"] = function(c)
    return c.column == "type" and sorted_key(tokens(c.lval)) == sorted_key(tokens(c.rval))
end

RULES["decl-typedef-const"] = function(c)
    if c.column ~= "type" or c.rval == "-" then
        return false
    end
    local lt = tokens(c.lval)
    if lt[1] ~= "const" or #lt < 2 then
        return false
    end
    local rest = {}
    for i = 2, #lt do
        table.insert(rest, lt[i])
    end
    local ok = sorted_key(rest) == sorted_key(tokens(c.rval))
    return ok and c.ctx.typedef_const(c.fw, rest[#rest])
end

RULES["decl-oracle-no-decl"] = function(c)
    return c.column == "type" and c.rval == "-" and c.ctx.truth(c.fw, c.api) ~= nil and c.lval ~= "-"
end

RULES["decl-oracle-macro-prefix"] = function(c)
    if c.column ~= "type" or string.find(c.rval, '"', 1, true) then
        return false
    end
    local left, removed = split_reference(c.rval)
    if #removed == 0 then
        return false
    end
    local t = c.ctx.truth(c.fw, c.api)
    local truth_pre = t and t.pre or ""
    for _, m in ipairs(removed) do
        if string.find(truth_pre, m, 1, true) == nil then
            return false
        end
    end
    return sorted_key(left) == sorted_key(tokens(c.lval))
end

RULES["decl-oracle-macro-trailing"] = function(c)
    if c.column ~= "type" or string.find(c.rval, '"', 1, true) then
        return false
    end
    local left, removed = split_reference(c.rval)
    local extra = {}
    local lt = tokens(c.lval)
    local known = {}
    for _, t in ipairs(lt) do
        known[t] = (known[t] or 0) + 1
    end
    for _, t in ipairs(left) do
        if known[t] then
            known[t] = known[t] - 1
        else
            table.insert(extra, t)
        end
    end
    if #extra == 0 or #removed > 0 then
        return false
    end
    local t = c.ctx.truth(c.fw, c.api)
    for _, m in ipairs(extra) do
        if not string.match(m, "^%u[%u%d_]*$") or t == nil or string.find(t.pre, m, 1, true) == nil then
            return false
        end
    end
    local kept = {}
    for _, tok in ipairs(left) do
        if not string.match(tok, "^%u[%u%d_]*$") then
            table.insert(kept, tok)
        end
    end
    return sorted_key(kept) == sorted_key(lt)
end

RULES["decl-oracle-bleed"] = function(c)
    if c.column ~= "type" or not string.find(c.rval, '"', 1, true) then
        return false
    end
    -- The reference's line holds a quoted macro argument and runs into another declaration: its tokens include a name that is not
    -- this constant's type. The name's own statement in the header carries the record's type before the name.
    local t = c.ctx.truth(c.fw, c.api)
    if t == nil then
        return false
    end
    -- (compared without spaces: the header spells NSString * const, the record NSString *const)
    local pre_compact = nospace(t.pre)
    for _, tok in ipairs(tokens(c.lval)) do
        if string.find(pre_compact, nospace(tok), 1, true) == nil then
            return false
        end
    end
    local known = {}
    for _, tok in ipairs(tokens(c.lval)) do
        known[tok] = true
    end
    local stray = false
    for _, tok in ipairs(tokens(string.match(c.rval, "^(.-)%s*[%u_][%u%d_]*%(") or c.rval)) do
        stray = stray or (not known[tok] and string.match(tok, "^[%a_][%w_]*$") ~= nil)
    end
    if not stray then
        return false
    end
    return true
end

-- The record's type (the IR's qualified type) spells a macro the reference does not, and the name's statement in the header carries
-- that macro (as a group after the name, or before it): the IR spelling keeps the macro, the reference's text does not.
RULES["decl-ir-macro-token"] = function(c)
    if c.column ~= "type" then
        return false
    end
    local rset, lset = {}, {}
    for _, tok in ipairs(tokens(c.rval)) do
        rset[tok] = true
    end
    local extra, kept, extra_count = {}, {}, 0
    for _, tok in ipairs(tokens(c.lval)) do
        if not rset[tok] and string.match(tok, "^%u[%u%d_]*$") then
            extra[tok] = true
            extra_count = extra_count + 1
        elseif not lset[tok] then
            lset[tok] = true
            table.insert(kept, tok)
        end
    end
    if extra_count == 0 then
        return false
    end
    local t = c.ctx.truth(c.fw, c.api)
    if t == nil then
        return false
    end
    for m in pairs(extra) do
        local in_header = string.find(t.pre, m, 1, true) ~= nil
        for _, g in ipairs(t.groups) do
            in_header = in_header or g.name == m
        end
        if not in_header then
            return false
        end
    end
    local rkept = {}
    for tok in pairs(rset) do
        table.insert(rkept, tok)
    end
    return sorted_key(kept) == sorted_key(rkept)
end

RULES["avail-next-line"] = function(c)
    if c.column ~= "availability" or c.rval ~= "-" then
        return false
    end
    local t = c.ctx.truth(c.fw, c.api)
    if t == nil then
        return false
    end
    local later = false
    for _, g in ipairs(t.groups) do
        if g.newline then
            later = true
        end
    end
    return later and nospace(c.lval) == api_groups_text(t.groups)
end

-- The reference's macro text is a prefix of the record's, and it stops at the name's line
local function prefix_of_truth(c, quoted)
    if c.column ~= "availability" or c.rval == "-" or (string.find(c.rval, '"', 1, true) ~= nil) ~= quoted then
        return false
    end
    local t = c.ctx.truth(c.fw, c.api)
    if t == nil then
        return false
    end
    local want = nospace(c.rval)
    local full = nospace(c.lval)
    return string.sub(full, 1, #want) == want and #want < #full
end

-- The reference reads no macros, and the header's statement carries exactly the record's macros, all on the name's line: the
-- reference's line match missed them (the macros of a name with its own declaration line are not the next-line case).
RULES["avail-reference-missed"] = function(c)
    if c.column ~= "availability" or c.rval ~= "-" then
        return false
    end
    local t = c.ctx.truth(c.fw, c.api)
    if t == nil then
        return false
    end
    for _, g in ipairs(t.groups) do
        if g.newline then
            return false
        end
    end
    return nospace(c.lval) == header_avail_text(t) and nospace(c.lval) ~= ""
end

-- The reference holds a run of the record's macros (a macro its line carried), and the others are written on other lines of the
-- statement: the header's statement gives the record's whole text
RULES["avail-name-line-subset"] = function(c)
    if c.column ~= "availability" or c.rval == "-" then
        return false
    end
    local t = c.ctx.truth(c.fw, c.api)
    if t == nil or header_avail_text(t) ~= nospace(c.lval) then
        return false
    end
    return string.find(nospace(c.lval), nospace(c.rval), 1, true) ~= nil
end

-- The position of the last match of a pattern in a text (0 when none); the pattern's first capture is the position
local function last_position(text, pattern)
    local at = 0
    for pos in string.gmatch(text, pattern) do
        at = pos
    end
    return at
end

-- The position of the next needle at or after from, or one past the end of the text when there is none
local function next_at(text, needle, from)
    return string.find(text, needle, from, true) or #text + 1
end

-- True when the macro m is written in the statement that declares the name, inside a conditional whose #if names TARGET_OS_VISION
-- (a branch an SDK for another platform does not take), with a #else or #elif before the next #endif. Each occurrence of m is tried,
-- since the first one in the headers may belong to another declaration.
local function in_visionos_branch(header, m, api)
    local from = 1
    while true do
        local p = string.find(header, m, from, true)
        if p == nil then
            return false
        end
        local before = string.sub(header, 1, p - 1)
        local window = string.sub(header, last_position(before, "()[;{}]") + 1, p - 1)
        local at_if, at_endif = last_position(before, "()#if"), last_position(before, "()#endif")
        local cond = at_if > at_endif and string.match(header, "^[^\n]*", at_if) or ""
        local e = math.min(next_at(header, "#else", p), next_at(header, "#elif", p))
        local endif = next_at(header, "#endif", p)
        if string.find(window, "%f[%w_]" .. api .. "%f[^%w_]") ~= nil and string.find(cond, "TARGET_OS_VISION", 1, true) ~= nil
           and e <= #header and e < endif then
            return true
        end
        from = p + 1
    end
end

-- The reference has the record's macros and one more, which the header writes in a visionOS-only conditional branch (the SDK's own
-- branch is the #else one): the extra macros are checked against the statement that declares the name, not the first match in the headers
RULES["avail-conditional-branch"] = function(c)
    if c.column ~= "availability" or c.rval == "-" then
        return false
    end
    local t = c.ctx.truth(c.fw, c.api)
    if t == nil then
        return false
    end
    local lval_macros, extra = {}, {}
    for _, m in ipairs(api_macros_in(c.lval)) do
        lval_macros[nospace(m)] = true
    end
    for _, m in ipairs(api_macros_in(c.rval)) do
        if not lval_macros[nospace(m)] then
            table.insert(extra, m)
        end
    end
    if #extra == 0 then
        return false
    end
    local header = c.ctx.header_text(c.fw)
    for _, m in ipairs(extra) do
        if not in_visionos_branch(header, m, c.api) then
            return false
        end
    end
    return true
end

-- The reference's macro came from a line whose string literal names this constant (another declaration's deprecation message), so
-- the reference matched the name inside a string; the record's macros are the name's own, as its header statement gives them.
RULES["avail-string-literal"] = function(c)
    if prefix_of_truth(c, true) then
        return true
    end
    if c.column ~= "availability" or c.rval == "-" or not string.find(c.rval, '"[^"]*' .. c.api .. '[^"]*"') then
        return false
    end
    local t = c.ctx.truth(c.fw, c.api)
    return t ~= nil and nospace(c.lval) == header_avail_text(t)
end

RULES["avail-name-line-prefix"] = function(c)
    return prefix_of_truth(c, false)
end

-- The record's hash, recomputed from the header: the declaration text (declared_text, over the statement the header declares the name
-- in) and the record's availability ("" for "-", as the writer hashes it). It holds for a record whose hash the header explains.
local function header_hash_matches(c)
    local t = c.ctx.truth(c.fw, c.api)
    if t == nil or c.lrow == nil or c.lrow.hash == nil then
        return false
    end
    local avail = c.lrow.availability == "-" and "" or c.lrow.availability
    return digest.digest("constant", c.api, declared_text(t.raw, c.api), avail) == c.lrow.hash
end

-- The record's hash is over the statement's text: a macro group written on an earlier line of the statement leads it, and the linkage
-- word after that macro stays. The reference's hash is over the name's own line (a linkage word at its start dropped). Both are
-- recomputed from the header and the record's availability, which the other cells show is the reference's.
local function hash_leading_macro(c)
    local t = c.ctx.truth(c.fw, c.api)
    if t == nil or c.lrow == nil then
        return false
    end
    local lines = {}
    for line in string.gmatch(t.pre .. "\n", "([^\n]*)\n") do
        table.insert(lines, line)
    end
    local lead = {}
    for i = 1, #lines - 1 do
        for g in string.gmatch(lines[i], "[%u_][%u%d_]*%b()") do
            table.insert(lead, g)
        end
    end
    if #lead == 0 then
        return false
    end
    local own = {}
    for word in string.gmatch(lines[#lines], "%S+") do
        if not NULLABILITY[word] then
            table.insert(own, word)
        end
    end
    local first = own[1] or ""
    local linked = LINKAGE[first] or string.find(first, "EXTERN", 1, true) or string.find(first, "EXPORT", 1, true)
    local ref = {}
    for i, word in ipairs(own) do
        if i > 1 or not linked then
            table.insert(ref, word)
        end
    end
    local avail = c.lrow.availability == "-" and "" or c.lrow.availability
    return digest.digest("constant", c.api, table.concat(ref, " "), avail) == c.rval
           and digest.digest("constant", c.api, table.concat(lead, " ") .. " " .. table.concat(own, " "), avail) == c.lval
end

-- Classify every differing cell. cells: {fw, api, column, lval, rval}. ctx: the context. disabled: a class name whose rule is
-- switched off (the mutant of a class's test). Returns the cells with .cls set (nil when unclassified) and the per-class counts.
function classify(cells, ctx, disabled)
    local by_column = {type = "decl", availability = "avail", value_status = "status", owned = "owned", measured = "measured",
                       value_source = "source", value = "value", host_value = "value", shape = "shape", hash = "hash"}
    local api_cls = {}
    for _, c in ipairs(cells) do
        c.ctx = ctx
    end
    local function try(c, names)
        for _, name in ipairs(names) do
            if name ~= disabled and RULES[name] ~= nil and RULES[name](c) then
                return name
            end
        end
        return nil
    end
    local decl_rules = {"decl-whitespace", "decl-const-order", "decl-typedef-const", "decl-oracle-no-decl",
                        "decl-oracle-macro-prefix", "decl-oracle-macro-trailing", "decl-oracle-bleed", "decl-ir-macro-token"}
    local avail_rules = {"avail-next-line", "avail-reference-missed", "avail-string-literal", "avail-name-line-prefix",
                        "avail-name-line-subset", "avail-conditional-branch"}
    for _, c in ipairs(cells) do
        if by_column[c.column] == "decl" then
            c.cls = try(c, decl_rules)
        elseif by_column[c.column] == "avail" then
            c.cls = try(c, avail_rules)
        end
        if c.cls ~= nil then
            api_cls[c.api] = api_cls[c.api] or {}
            api_cls[c.api][by_column[c.column]] = c.cls
        end
    end
    for _, c in ipairs(cells) do
        if by_column[c.column] == "status" then
            -- the reference's shape is numeric or undeclared, the record's is found, and the header declares the name
            -- (an undeclared reference that the record types as numeric is a declaration the reference missed, too)
            local recovered = (c.rval == "numeric" or c.rval == "undeclared") and (c.lval == "found" or c.lval == "numeric")
            if recovered and c.ctx.truth(c.fw, c.api) ~= nil and disabled ~= "value-status-decl" then
                c.cls = "value-status-decl"
            end
            if c.cls == nil and string.sub(c.lval, 1, 6) == "owned:" then
                local branch = c.ctx.owned[c.api]
                if branch ~= nil and c.lval == "owned:" .. branch and disabled ~= "owned-input" then
                    c.cls = "owned-input"
                end
            end
        elseif by_column[c.column] == "owned" then
            if c.ctx.owned[c.api] ~= nil and c.lval == c.ctx.owned[c.api] and disabled ~= "owned-input" then
                c.cls = "owned-input"
            end
        elseif by_column[c.column] == "measured" then
            if c.rval == "-" and c.ctx.held[c.api] ~= nil and c.lval == c.ctx.held[c.api] and disabled ~= "measured-input" then
                c.cls = "measured-input"
            end
        end
        if c.cls ~= nil then
            api_cls[c.api] = api_cls[c.api] or {}
            api_cls[c.api][by_column[c.column]] = c.cls
        end
    end
    -- An availability the reference left out is one it had no declaration line or no decl for: the decl class (oracle) or the
    -- recovered status (committed records, which keep no declaration text) says so.
    for _, c in ipairs(cells) do
        if by_column[c.column] == "avail" and c.cls == nil and c.rval == "-" and disabled ~= "decl-oracle-no-decl" and api_cls[c.api] and
           (api_cls[c.api].decl == "decl-oracle-no-decl" or api_cls[c.api].status == "value-status-decl") then
            c.cls = "decl-oracle-no-decl"
            api_cls[c.api].avail = c.cls
        end
    end
    for _, c in ipairs(cells) do
        if by_column[c.column] == "source" then
            local cached = c.ctx.cache[c.api]
            local claims_cache = string.sub(c.lval, 1, 15) == "ios-26.2-cache" or string.sub(c.rval, 1, 15) == "ios-26.2-cache"
            if claims_cache and disabled ~= "cache-drift" then
                local lcache = string.sub(c.lval, 1, 15) == "ios-26.2-cache"
                local rcache = string.sub(c.rval, 1, 15) == "ios-26.2-cache"
                -- the reference claims the cache for a name the table no longer holds, or the table holds a value the reference
                -- did not take: the reference is out of date with the table, not the record
                if lcache ~= rcache and ((rcache and cached == nil) or (lcache and cached ~= nil)) then
                    c.cls = "cache-drift"
                end
            end
            if c.cls == nil and api_cls[c.api] and (api_cls[c.api].status or api_cls[c.api].owned) then
                c.cls = "value-follows-status"
            end
        end
        if c.cls ~= nil then
            api_cls[c.api] = api_cls[c.api] or {}
            api_cls[c.api][by_column[c.column]] = c.cls
        end
    end
    for _, c in ipairs(cells) do
        local col = by_column[c.column]
        if col == "value" and c.cls == nil then
            local source = api_cls[c.api] and api_cls[c.api].source
            if source == "cache-drift" and disabled ~= "cache-drift" then
                c.cls = "cache-drift"
            elseif api_cls[c.api] and (api_cls[c.api].status or api_cls[c.api].owned) and disabled ~= "value-follows-status" then
                c.cls = "value-follows-status"
            end
        elseif col == "shape" and c.cls == nil then
            if api_cls[c.api] and api_cls[c.api].status == "value-status-decl" and disabled ~= "shape-follows-decl" then
                c.cls = "shape-follows-decl"
            end
        end
        if c.cls ~= nil then
            api_cls[c.api] = api_cls[c.api] or {}
            api_cls[c.api][col] = c.cls
        end
    end
    for _, c in ipairs(cells) do
        if by_column[c.column] == "hash" and c.cls == nil then
            local a = api_cls[c.api] or {}
            if (a.decl or a.avail or a.status or a.source) and disabled ~= "hash-follows-inputs" then
                c.cls = "hash-follows-inputs"
            elseif disabled ~= "hash-declared-text" and header_hash_matches(c) then
                c.cls = "hash-declared-text"
            elseif disabled ~= "hash-leading-macro" and hash_leading_macro(c) then
                c.cls = "hash-leading-macro"
            end
        end
    end
    local counts = {}
    for _, c in ipairs(cells) do
        local key = c.cls or "UNCLASSIFIED"
        counts[key] = (counts[key] or 0) + 1
    end
    return cells, counts
end

-- The rows of a table text, keyed by api (the constant rows only when a kind column is present)
function rows_of(text)
    local rows, header = {}, nil
    for _, line in ipairs(tsv.lines(text)) do
        local cells = tsv.fields(line)
        if header == nil then
            header = cells
        else
            local row = {}
            for i, name in ipairs(header) do
                row[name] = cells[i]
            end
            if row.api ~= nil and (row.kind == nil or row.kind == "constant") then
                rows[row.api] = row
            end
        end
    end
    return rows, header or {}
end

-- The differing cells of a framework: left is the record being checked (the Lua), right the reference. mode "oracle" maps the
-- record's type to the reference's decl and skips the declhash, which the shard does not carry.
function cells(fw, left, right, mode)
    local out = {}
    local names = {}
    for api in pairs(left) do
        names[api] = true
    end
    for api in pairs(right) do
        names[api] = true
    end
    local sorted = {}
    for api in pairs(names) do
        table.insert(sorted, api)
    end
    table.sort(sorted)
    for _, api in ipairs(sorted) do
        local l, r = left[api], right[api]
        if l == nil or r == nil then
            table.insert(out, {fw = fw, api = api, column = "row", lval = l and "present" or "-", rval = r and "present" or "-"})
        else
            for column, lv in pairs(l) do
                local rc = column
                if mode == "oracle" and column == "type" then
                    rc = "decl"
                end
                if column ~= "declhash" or mode ~= "oracle" then
                    local rv = r[rc]
                    if rv ~= nil and rv ~= lv then
                        table.insert(out, {fw = fw, api = api, column = column, lval = lv, rval = rv, lrow = l})
                    end
                end
            end
        end
    end
    return out
end

-- The iOS 26.2 cache table's cfstring values: name (leading underscore removed) -> value
function cache_values(path)
    local values, header = {}, nil
    local status = stream.lines("gzip", {"-dc", path}, function (line)
        local cells = tsv.fields(line)
        if header == nil then
            header = {}
            for i, name in ipairs(cells) do
                header[name] = i
            end
            return
        end
        if cells[header.value_kind] == "cfstring" then
            local symbol = cells[header.symbol]
            local name = string.sub(symbol, 1, 1) == "_" and string.sub(symbol, 2) or symbol
            values[name] = values[name] or cells[header.value]
        end
    end)
    assert(status == 0, "gzip failed on " .. path)
    return values
end

-- measured.held-caches.tsv or owned.tsv: a two-column snapshot (name, value) with a header line for the first
function pairs_of(text)
    local out = {}
    for _, line in ipairs(tsv.lines(text)) do
        local cells = tsv.fields(line)
        if #cells == 2 and cells[1] ~= "symbol" and cells[1] ~= "api" then
            out[cells[1]] = cells[2]
        end
    end
    return out
end

-- The text of every header of a framework under the SDK (its Headers folder, nested folders included)
function framework_headers(sdk, fw)
    local dir = path.join(sdk, "System", "Library", "Frameworks", fw .. ".framework", "Headers")
    local texts = {}
    for _, filepath in ipairs(files.glob(path.join(dir, "**.h"))) do
        table.insert(texts, files.read_text(filepath) or "")
    end
    return table.concat(texts, "\n")
end

-- The digest of a reference row's own inputs, for the check that the reference hash recomputes from its declaration and availability
function recomputed_hash(api, decl, availability)
    return digest.digest("constant", api, decl, availability)
end

