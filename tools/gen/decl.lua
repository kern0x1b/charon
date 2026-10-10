-- The declaration text the trace layer reads: the nullability words and the platform macros after a declaration, the trailing
-- macros of a property, the selector a statement names, a property's name and getter, the type a property declares, and the
-- kind of a declared type. Each function is an oracle regular expression spelled as a scan (Lua patterns have no alternation
-- and no optional group); the words and the sets are the oracle's.

local strings = import("strings", {anonymous = true})

-- The C scalar types: a declared type of one of them is a scalar.
local SCALAR_TYPES = strings.set({"BOOL", "bool", "char", "unsigned char", "short", "unsigned short", "int", "unsigned",
                                  "unsigned int", "long", "unsigned long", "long long", "unsigned long long", "float", "double",
                                  "NSInteger", "NSUInteger", "CGFloat", "NSTimeInterval", "size_t", "int8_t", "int16_t",
                                  "int32_t", "int64_t", "uint8_t", "uint16_t", "uint32_t", "uint64_t"})

-- The words the SDK's nullability annotations spell: removed from a declaration by strip_nullability.
local NULLABILITY_WORDS = strings.set({"_Nullable", "_Nonnull", "__nullable", "__nonnull", "_Null_unspecified", "nullable",
                                       "nonnull", "null_resettable", "null_unspecified"})

-- A typedef chain longer than this is not followed: the kind is then read from the name.
local MAX_TYPEDEF_DEPTH = 6

-- The spellings a type can begin with when it is an enum or an option set: a scalar.
local ENUM_SPELLINGS = {"NS_ENUM", "NS_OPTIONS", "enum"}

-- A word of identifier characters (\w) that a scan of a declaration can end at: the next character is not one of them.
local function is_word_char(c)
    return c ~= "" and string.find(c, "[%w_]") ~= nil
end

-- The text with each innermost parenthesised group (no parenthesis inside it) replaced by fill, scanning left to right once:
-- re.sub(r"\([^()]*\)", fill, text).
local function remove_groups(text, fill)
    local out, copied, pos = {}, 1, 1
    while true do
        local open = string.find(text, "(", pos, true)
        if open == nil then
            break
        end
        local nextparen = string.find(text, "[()]", open + 1)
        if nextparen ~= nil and string.sub(text, nextparen, nextparen) == ")" then
            table.insert(out, string.sub(text, copied, open - 1))
            table.insert(out, fill)
            copied = nextparen + 1
            pos = copied
        else
            pos = open + 1
        end
    end
    table.insert(out, string.sub(text, copied))
    return table.concat(out)
end

-- The platform macros the SDK puts after a declaration: \b__[A-Z][A-Z0-9_]*(?:\([^()]*\))?, each replaced by a space.
local function strip_platform_macros(text)
    local out, copied, pos = {}, 1, 1
    while true do
        local at = string.find(text, "__", pos, true)
        if at == nil then
            break
        end
        local bounded = at == 1 or not is_word_char(string.sub(text, at - 1, at - 1))
        local stop = bounded and string.match(text, "^__[A-Z][A-Z0-9_]*()", at)
        if stop then
            stop = string.match(text, "^%([^()]*%)()", stop) or stop
            table.insert(out, string.sub(text, copied, at - 1))
            table.insert(out, " ")
            copied, pos = stop, stop
        else
            pos = at + 1
        end
    end
    table.insert(out, string.sub(text, copied))
    return table.concat(out)
end

-- The declaration without its nullability words and the platform macros the SDK puts after it (__TVOS_PROHIBITED and the like),
-- as single-spaced text: the stub compiles whether or not the header's audit and availability macros are in scope.
function strip_nullability(decl)
    local words = (string.gsub(decl, "[%w_]+", function(word)
        if NULLABILITY_WORDS[word] then
            return " "
        end
    end))
    return strings.collapse(strip_platform_macros(words))
end

-- The position after an identifier of the trailing-macro form at i ([A-Z][A-Z0-9]* then one or more _[A-Z0-9]+), or nil.
local function macro_name_end(s, i)
    local stop = string.match(s, "^[A-Z][A-Z0-9]*()", i)
    if stop == nil then
        return nil
    end
    local groups = 0
    while true do
        local after = string.match(s, "^_[A-Z0-9]+()", stop)
        if after == nil then
            break
        end
        stop = after
        groups = groups + 1
    end
    if groups == 0 then
        return nil
    end
    return stop
end

-- The position after the argument list whose "(" is at i, or nil: the list ends at the first ")" that no nested "(...)" holds.
local function arguments_end(s, i)
    local pos = i + 1
    while true do
        local stop = string.match(s, "^[^()]*()", pos)
        local c = string.sub(s, stop, stop)
        if c == ")" then
            return stop + 1
        end
        if c ~= "(" then
            return nil
        end
        local inner = string.match(s, "^%([^()]*%)()", stop)
        if inner == nil then
            return nil
        end
        pos = inner
    end
end

-- True when the text from position p is a run of trailing macros to its end: (?:\s+IDENT(?:\s*\(ARGS\))?)+\s*$ (see
-- without_trailing_macros).
local function macro_run_to_end(s, p)
    local pos, units = p, 0
    while true do
        local name = string.match(s, "^%s+()", pos)
        if name == nil then
            break
        end
        local stop = macro_name_end(s, name)
        if stop == nil then
            break
        end
        local open = string.match(s, "^%s*()", stop)
        if string.sub(s, open, open) == "(" then
            stop = arguments_end(s, open)
            if stop == nil then
                return false
            end
        end
        pos = stop
        units = units + 1
    end
    return units > 0 and string.match(s, "^%s*$", pos) ~= nil
end

-- The declaration without the project macros after it (CS_TVOS_UNAVAILABLE, UI_APPEARANCE_SELECTOR, FILEPROVIDER_API_AVAILABILITY_
-- DESKTOP): the oracle's TRAILING_MACRO, removed from the end of " " .. text .. " " and stripped.
function without_trailing_macros(text)
    local s = " " .. strings.rstrip(text, "[ ;]") .. " "
    -- every unit of the run spells a name with an underscore, so a text without one has no run to remove
    if string.find(s, "_", 1, true) then
        for p = 1, #s do
            if string.match(s, "^%s", p) and macro_run_to_end(s, p) then
                return strings.strip(string.sub(s, 1, p - 1))
            end
        end
    end
    return strings.strip(s)
end

-- The name a property declaration gives its property: the name in a block's or function pointer's parentheses, else the last
-- identifier once the trailing macros are gone.
function property_name(decl)
    local core = without_trailing_macros(decl)
    local named = string.match(core, "%(%s*%^%s*([%w_]+)%s*%)")
    if named then
        return named
    end
    local last = string.match(core, "([A-Za-z_][%w_]*)%s*$")
    assert(last, "a property declaration names no property: " .. decl)
    return last
end

-- The name a member row's api ends in: its last word once the closing brackets are gone (api.rstrip("]").split()[-1]).
function member_name(api)
    local trimmed = string.gsub(api, "%]+$", "")
    return string.match(trimmed, "(%S+)%s*$")
end

-- The selector a statement names: the words before each colon, each with its colon, or the last word of a selector with none.
-- Parenthesised groups (the types and the parameter names) go first; nil or "" when the statement names none.
function selector_of(statement)
    local s = strings.strip((string.gsub(statement, "^[%-%+ ]+", "")))
    local done = false
    while not done do
        local nxt = remove_groups(s, " ")
        done = nxt == s
        s = nxt
    end
    if string.find(s, ":", 1, true) == nil then
        local word = nil
        for run in string.gmatch(s, "[%w_]+") do
            word = string.match(run, "[%a_][%w_]*") or word
        end
        return word
    end
    local parts = {}
    for run, stop in string.gmatch(s, "([%w_]+)()") do
        local word = string.match(run, "[%a_][%w_]*")
        if word and string.match(s, "^%s*:", stop) then
            table.insert(parts, word .. ":")
        end
    end
    return table.concat(parts)
end

-- The selector a property's getter= names, or the property's name when it names none.
function getter_of(decl, name)
    return string.match(decl, "getter%s*=%s*([%w_]+)") or name
end

-- The type text of a property: the declaration without its attributes, its name and the semicolon. decl is strip_nullability's
-- output (the nullability words are gone already, so the oracle's second nullability pass has nothing to remove).
function property_type_text(decl, name)
    local text = remove_groups((string.gsub(decl, "@property", " ")), " ")
    text = strings.collapse(strings.rstrip(text, ";"))
    local at = strings.last_index(text, name)
    if at == nil then
        return text
    end
    return strings.collapse(string.sub(text, 1, at - 1))
end

-- 'void', 'object', 'scalar' or 'struct' for a declared type, through its typedefs (index: typedef name -> the text it defines).
function resolve_kind(type_text, index, depth)
    depth = depth or 0
    local text = strings.collapse((string.gsub(type_text, "%*", " * ")))
    if text == "void" then
        return "void"
    end
    if string.find(text, "*", 1, true) or text == "id" or text == "instancetype" or string.find(text, "<.*>") then
        return "object"
    end
    local name = string.match(text, "(%S+)$") or text
    if SCALAR_TYPES[text] or SCALAR_TYPES[name] then
        return "scalar"
    end
    local target = index[name]
    if target ~= nil and depth < MAX_TYPEDEF_DEPTH then
        if target == "struct" or string.sub(target, 1, 6) == "struct" then
            return "struct"
        end
        return resolve_kind(target, index, depth + 1)
    end
    for _, spelling in ipairs(ENUM_SPELLINGS) do
        if string.sub(text, 1, #spelling) == spelling and not is_word_char(string.sub(text, #spelling + 1, #spelling + 1)) then
            return "scalar"
        end
    end
    if string.sub(name, 1, 2) == "NS" and string.sub(name, -7) == "Options" then
        return "scalar"
    end
    return "struct"
end

-- The scans of strip_macros: each is run on every run of word characters (the \b positions of the oracle's patterns). scan(text, a, b)
-- returns the position after a match that starts at the run a..b, or nil. The classes are ASCII ranges, not the locale's.

-- The availability macro of a declaration: a word that holds AVAILABLE, DEPRECATED or OBSOLETED, with its argument list.
local function availability_scan(text, a, b)
    local word = string.sub(text, a, b)
    if not (string.find(word, "AVAILABLE", 1, true) or string.find(word, "DEPRECATED", 1, true)
            or string.find(word, "OBSOLETED", 1, true)) then
        return nil
    end
    local open = string.match(text, "^[ \t\n\r\f\v]*()", b + 1)
    if string.sub(text, open, open) ~= "(" then
        return nil
    end
    return arguments_end(text, open)
end

-- The prefixes of the SDK's call-like macros: API_DEPRECATED("..."), NS_REFINED_FOR_SWIFT, __TVOS_PROHIBITED and the like.
local CALL_MACRO_PREFIXES = {"API", "NS", "OS", "CF", "__"}

-- A call-like macro: a prefix, an optional _, one capital and then capitals, digits and _, then its argument list.
local function call_macro_scan(text, a, b)
    for _, prefix in ipairs(CALL_MACRO_PREFIXES) do
        if string.sub(text, a, a + #prefix - 1) == prefix then
            local r = a + #prefix
            if string.sub(text, r, r) == "_" then
                r = r + 1
            end
            if not string.match(text, "^[A-Z]", r) then
                return nil
            end
            local stop = string.match(text, "^[A-Z0-9_]*()", r)
            local open = string.match(text, "^[ \t\n\r\f\v]*()", stop)
            if string.sub(text, open, open) ~= "(" then
                return nil
            end
            return arguments_end(text, open)
        end
    end
    return nil
end

-- A name macro with no argument list: a whole word of API_, NS_, OS_ or CF_ and capitals, or of __ and capitals.
local NAME_MACRO_PATTERNS = {"^API_[A-Z][A-Z0-9_]*$", "^NS_[A-Z][A-Z0-9_]*$", "^OS_[A-Z][A-Z0-9_]*$", "^CF_[A-Z][A-Z0-9_]*$",
                             "^__[A-Z][A-Z0-9_]*$"}

local function name_macro_scan(text, a, b)
    local word = string.sub(text, a, b)
    for _, pattern in ipairs(NAME_MACRO_PATTERNS) do
        if string.match(word, pattern) then
            return b + 1
        end
    end
    return nil
end

-- __attribute__((...)) of the compiler, with its two argument lists.
local function attribute_scan(text, a, b)
    if string.sub(text, a, b) ~= "__attribute__" then
        return nil
    end
    local open = string.match(text, "^[ \t\n\r\f\v]*()", b + 1)
    if string.sub(text, open, open + 1) ~= "((" then
        return nil
    end
    local stop = arguments_end(text, open + 1)
    if stop and string.sub(text, stop, stop) == ")" then
        return stop + 1
    end
    return nil
end

-- An NS_ enumeration or option macro (NS_ENUM, NS_OPTIONS and the like), with its argument list when it has one.
local function enum_macro_scan(text, a, b)
    if not string.match(string.sub(text, a, b), "^NS_[A-Z_]+$") then
        return nil
    end
    local open = string.match(text, "^[ \t\n\r\f\v]*()", b + 1)
    if string.sub(text, open, open) == "(" then
        local stop = arguments_end(text, open)
        if stop then
            return stop
        end
    end
    return b + 1
end

-- The text with each match of a scan replaced by a space. The scan is tried at each run of word characters, left to right.
local function blank_matches(text, scan)
    local out, copied, pos = {}, 1, 1
    while true do
        local a, b = string.find(text, "[A-Za-z0-9_]+", pos)
        if a == nil then
            break
        end
        local stop = scan(text, a, b)
        if stop then
            table.insert(out, string.sub(text, copied, a - 1))
            table.insert(out, " ")
            copied, pos = stop, stop
        else
            pos = b + 1
        end
    end
    table.insert(out, string.sub(text, copied))
    return table.concat(out)
end

-- The declaration without the availability and SDK macros in it (the oracle's strip_macros, its clean text): the availability
-- macros, the call-like and name macros, __attribute__ and the NS_ enumeration macros are each replaced by a space, and the
-- whitespace is single-spaced. The availability text the oracle also returns is not needed by the callers and is not kept.
function strip_macros(text)
    local clean = blank_matches(text, availability_scan)
    clean = blank_matches(clean, call_macro_scan)
    clean = blank_matches(clean, name_macro_scan)
    clean = blank_matches(clean, attribute_scan)
    clean = blank_matches(clean, enum_macro_scan)
    return strings.collapse(clean)
end
