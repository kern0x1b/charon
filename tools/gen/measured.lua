-- The measured constants of a framework: the objects that carry values read out of the held dyld caches, not out of a header. The table
-- is tools/corpus/uikit-constants.tsv (one row per constant: its api, the node's own C type, its value as the cache holds it, the first
-- held release that exports it, and the floor a typedef's own release needs). Each release of it is one object, written by gen beside
-- the spec-derived objects into .gen/<F>/, so the build produces the sources and nothing of them is committed.
--
-- It replaces the python writer that stood here before. Its objects are the same bytes as that writer's, except the producer line
-- of the header. Its literal rules and its clean_type are kept. What it does not do is the registry write: the python rewrote the
-- framework's registry rows and removed the objects it no longer needed, one time, and the registry those writes left is committed
-- (registry/UIKit/uikit-constants.json and the rest). The facts files of each release (facts/UIKit/UIKitConstants<tag>.md) are
-- committed too: the registry cites them.

local order = import("order", {anonymous = true})
local files = import("files", {anonymous = true})

-- The framework's table, relative to the tree, and the committed objects whose names the table must not repeat.
-- extras: the hand-written text a release's object carries beside its rows. A function in one object that reaches a constant in another
-- breaks in exactly the bands where the two land on opposite sides of the release split (charon/AGENTS.md, "A C function shared between
-- backport files"), so the 13.4 object carries the function that reads UIGuidedAccessErrorDomain, which is in the same object, and the
-- text is the file's own, read as it is.
local SOURCES = {
    UIKit = {
        table = "tools/corpus/uikit-constants.tsv",
        exported = "packages/a/apple-backports/UIKit/UIKitExportedConstants-*.m",
        extras = {["13.4"] = "tools/corpus/uikit-extras-13.4.txt"},
    },
}

local ATTRS = {"API_AVAILABLE", "API_UNAVAILABLE", "API_DEPRECATED", "NS_SWIFT_NAME", "NS_REFINED_FOR_SWIFT", "NS_SWIFT_UNAVAILABLE",
               "UIKIT_AVAILABLE", "NS_CLASS_AVAILABLE", "NS_AVAILABLE", "API_DEPRECATED_WITH_REPLACEMENT"}

-- The rows of a tab-separated table with CSV quoting, as Python's csv reader reads it with delimiter "\t": a field that starts with a
-- quote runs to the closing quote, a doubled quote inside it is one quote, and a line that holds no field is no row. The table holds
-- no carriage return and no quoted newline, which is checked by the caller's column count.
local function csv_rows(text)
    local rows, row, field = {}, {}, {}
    local state = "start"
    local i, n = 1, #text
    local function end_field()
        table.insert(row, table.concat(field))
        field = {}
    end
    local function end_row()
        end_field()
        if not (#row == 1 and row[1] == "") then
            table.insert(rows, row)
        end
        row = {}
    end
    while i <= n do
        local c = string.sub(text, i, i)
        if state == "start" then
            if c == '"' then
                state = "quoted"
            elseif c == "\t" then
                end_field()
            elseif c == "\n" then
                end_row()
            else
                table.insert(field, c)
                state = "plain"
            end
        elseif state == "plain" then
            if c == "\t" then
                end_field()
                state = "start"
            elseif c == "\n" then
                end_row()
                state = "start"
            else
                table.insert(field, c)
            end
        elseif state == "quoted" then
            if c == '"' then
                if string.sub(text, i + 1, i + 1) == '"' then
                    table.insert(field, '"')
                    i = i + 1
                else
                    state = "after"
                end
            else
                table.insert(field, c)
            end
        else
            -- after a closing quote: a delimiter or a line end closes the field, anything else is kept as the field's text
            if c == "\t" then
                end_field()
                state = "start"
            elseif c == "\n" then
                end_row()
                state = "start"
            else
                table.insert(field, c)
                state = "plain"
            end
        end
        i = i + 1
    end
    if state ~= "start" or #field > 0 or #row > 0 then
        end_row()
    end
    return rows
end

-- The table's rows as records keyed by its header, a missing trailing field read as "" (the header row names the keys).
local function records(text)
    local rows = csv_rows(text)
    local header = table.remove(rows, 1)
    local out = {}
    for _, row in ipairs(rows) do
        local record = {}
        for k, key in ipairs(header) do
            record[key] = row[k] or ""
        end
        table.insert(out, record)
    end
    return out
end

-- The declaration's type, with the attribute macros off and nothing else: each attribute, with the parenthesised argument that follows it
-- directly, is replaced by a space (re.sub(r"\b%s\b(\([^)]*\))?")), then the whitespace is collapsed. The nullability stays: it is part of
-- the type clang compares a redefinition against, and dropping it makes every _Nonnull declaration in the SDK a redefinition of ours.
local function is_word(c)
    return c ~= "" and string.find(c, "^[%w_]") ~= nil
end

local function clean_type(text)
    for _, attr in ipairs(ATTRS) do
        local out, pos = {}, 1
        while true do
            local start = string.find(text, attr, pos, true)
            if not start then
                break
            end
            local stop = start + #attr - 1
            local before = start > 1 and string.sub(text, start - 1, start - 1) or ""
            local after = string.sub(text, stop + 1, stop + 1)
            if is_word(before) or is_word(after) then
                table.insert(out, string.sub(text, pos, start))
                pos = start + 1
            else
                table.insert(out, string.sub(text, pos, start - 1))
                table.insert(out, " ")
                pos = stop + 1
                if string.sub(text, pos, pos) == "(" then
                    local close = string.find(text, ")", pos, true)
                    if close then
                        pos = close + 1
                    end
                end
            end
        end
        table.insert(out, string.sub(text, pos))
        text = table.concat(out)
    end
    text = string.gsub(text, "^%s+", "")
    text = string.gsub(text, "%s+$", "")
    text = string.gsub(text, "%s+", " ")
    return text
end

-- A C string literal's body: the backslash, the double quote, newline and tab escaped, every other control byte as a three-digit octal.
-- Bytes above 0x7f pass through, as the python wrote the characters' utf-8.
local function c_quote(text)
    return (string.gsub(text, "[%c\\\"]", function(c)
        if c == "\127" then
            return c
        elseif c == "\\" then
            return "\\\\"
        elseif c == '"' then
            return '\\"'
        elseif c == "\n" then
            return "\\n"
        elseif c == "\t" then
            return "\\t"
        end
        return string.format("\\%03o", string.byte(c))
    end))
end

-- An optionally signed decimal with an optional fraction of at least one digit and an optional exponent: [0-9]+(\.[0-9]+)?([eE][+-]?[0-9]+)?
local function is_number(text)
    local rest = string.match(text, "^%-?%d+(.*)$")
    if rest == nil then
        return false
    end
    if string.sub(rest, 1, 1) == "." then
        local after = string.match(rest, "^%.%d+(.*)$")
        if after == nil then
            return false
        end
        rest = after
    end
    return rest == "" or string.match(rest, "^[eE][+-]?%d+$") ~= nil
end

-- The C literal a row carries, or nil when the value is not one: a string, a number, a constant name, or a struct of numbers and names.
-- A block's value is the address of the release's own code, which is not a value, so it is refused here rather than written out as one.
local function literal(row)
    local value = row["value"]
    if row["kind"] == "constant string" then
        if #value >= 2 and string.sub(value, 1, 1) == '"' and string.sub(value, -1) == '"' then
            value = string.sub(value, 2, -2)
        end
        return '@"' .. c_quote(value) .. '"'
    end
    if is_number(value) or string.match(value, "^%-?[A-Z][A-Z0-9_]*$") then
        return value
    end
    if string.sub(value, 1, 1) == "{" and string.sub(value, -1) == "}" then
        local members = {}
        for member in string.gmatch(string.sub(value, 2, -2) .. ",", "([^,]*),") do
            table.insert(members, (string.gsub(string.gsub(member, "^%s+", ""), "%s+$", "")))
        end
        local ok = #members > 0
        for _, member in ipairs(members) do
            local name, number = string.match(member, "^([A-Za-z_][%w_]*) = (.+)$")
            if name == nil then
                ok = false
                break
            end
            local plain = string.match(number, "^%-?[%d%.]+$") or string.match(number, "^%-?[%d%.]+[eE][+-]?%d+$")
                or string.match(number, "^%-?[A-Z][A-Z0-9_]*$")
            if plain == nil then
                ok = false
                break
            end
        end
        if ok then
            local parts = {}
            for _, member in ipairs(members) do
                table.insert(parts, "." .. member)
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        end
    end
    return nil
end

-- The name a line of an object declares with "=", as the python's ^\s*[\w \*]+?\b(\w+)\s*= reads it: the word before the first "=",
-- when only word bytes, spaces and stars come before it on the line (after its leading whitespace) and the word is not the first thing.
local function declared_name(line)
    local body = string.match(line, "^%s*(.*)$")
    local eq = string.find(body, "=", 1, true)
    if eq == nil then
        return nil
    end
    local head = string.gsub(string.sub(body, 1, eq - 1), "[ \t]+$", "")
    local word = string.match(head, "([%w_]+)$")
    if word == nil then
        return nil
    end
    local before = string.sub(head, 1, #head - #word)
    if before == "" or string.match(before, "[^%w_ %*]") or string.match(before, "[%w_]$") then
        return nil
    end
    return word
end

-- The names the committed exported-constant objects define: they are carried elsewhere, so the table's rows for them are not written again.
local function carried_elsewhere(tree, pattern)
    local found = {}
    for _, path in ipairs(files.glob(path.join(tree, pattern))) do
        for line in io.lines(path) do
            local name = declared_name(line)
            if name then
                found[name] = true
            end
        end
    end
    return found
end

-- The release's sort key, its dotted numbers as numbers.
local function release_key(release)
    local key = {}
    for part in string.gmatch(release, "[^%.]+") do
        table.insert(key, tonumber(part))
    end
    return key
end

local function release_less(a, b)
    local ka, kb = release_key(a), release_key(b)
    for i = 1, math.max(#ka, #kb) do
        if (ka[i] or 0) ~= (kb[i] or 0) then
            return (ka[i] or 0) < (kb[i] or 0)
        end
    end
    return false
end

local function api_less(a, b)
    return order.less(a.api, b.api)
end

-- The guard of a floor: __IPHONE_OS_VERSION_MAX_ALLOWED for the floor's major and minor, as 10000 * major + 100 * minor.
local function floor_guard(floor)
    local major, minor = string.match(floor, "^(%d+)%.(%d+)")
    if major == nil then
        major, minor = string.match(floor .. ".0", "^(%d+)%.(%d+)")
    end
    return tonumber(major) * 10000 + tonumber(minor) * 100
end

-- The object of one release: the header, the rows of the release sorted by name, the extra text the release carries (extra, or nil),
-- and a final newline.
local function object_text(release, items, extra)
    local tag = string.gsub(release, "%.", "")
    local source = "UIKitConstants" .. tag .. ".m"
    local facts = "UIKitConstants" .. tag .. ".md"
    local lines = {
        "// The UIKit constants first exported by iOS " .. release .. " (" .. facts .. ").",
        "//",
        "// Generated:  xmake l tools/gen.lua gen --framework UIKit",
        "// from tools/corpus/uikit-constants.tsv. Do not edit this file by hand; regenerate it.",
        "//",
        "// One object carries one release: every symbol here is first exported by the oldest",
        "// held release that has it, so a band from " .. release .. " on re-exports the release's own and the",
        "// bands below keep this one.",
        "//",
        "// Every value below was read out of a real dyld shared cache - the " .. release .. " rung of the",
        "// machine's held ladder - and never from a header and never from a host framework.",
        "",
        "#import <UIKit/UIKit.h>",
        "",
    }
    local sorted = table.move(items, 1, #items, 1, {})
    table.sort(sorted, api_less)
    for _, item in ipairs(sorted) do
        local written = literal(item)
        assert(written ~= nil, string.format("the table's %s carries %q, which is not a C literal: a block or a function has no value to carry, "
            .. "and its implementation is a hand-written file", item.api, item.value))
        if item.floor ~= "" then
            -- A typedef the SDK being built against may not have: the release it arrived in is the SDK's own API_AVAILABLE on the typedef,
            -- and the two spellings differ only in the type, so the value is written once under a guard on __IPHONE_OS_VERSION_MAX_ALLOWED.
            table.insert(lines, "#if __IPHONE_OS_VERSION_MAX_ALLOWED >= " .. floor_guard(item.floor))
            table.insert(lines, clean_type(item["c-type"]) .. " " .. item.api .. " = " .. written .. ";")
            table.insert(lines, "#else")
            table.insert(lines, item.underlying .. " " .. item.api .. " = " .. written .. ";")
            table.insert(lines, "#endif")
        else
            table.insert(lines, clean_type(item["c-type"]) .. " " .. item.api .. " = " .. written .. ";")
        end
    end
    if extra ~= nil then
        table.insert(lines, "")
        table.insert(lines, extra)
    end
    table.insert(lines, "")
    return source, table.concat(lines, "\n")
end

-- The objects of a framework that the measured table defines: name -> text, each name a file of .gen/<F>/. Empty for a framework
-- with no table. A row the committed exported-constant objects already define is left out of the table's releases.
function objects(tree, fw)
    local spec = SOURCES[fw]
    local out = {}
    if spec == nil then
        return out
    end
    local text = files.read_text(path.join(tree, spec.table))
    assert(text ~= nil, "the measured table is missing: " .. spec.table)
    local elsewhere = carried_elsewhere(tree, spec.exported)
    local by_release, releases = {}, {}
    for _, row in ipairs(records(text)) do
        if not elsewhere[row.api] then
            if by_release[row["from-release"]] == nil then
                by_release[row["from-release"]] = {}
                table.insert(releases, row["from-release"])
            end
            table.insert(by_release[row["from-release"]], row)
        end
    end
    table.sort(releases, release_less)
    for _, release in ipairs(releases) do
        local extra = nil
        if (spec.extras or {})[release] ~= nil then
            extra = files.read_text(path.join(tree, spec.extras[release]))
            assert(extra ~= nil, "the extra text of " .. release .. " is missing: " .. spec.extras[release])
            -- the file ends with its line feed, which the object's last line does not carry
            extra = string.gsub(extra, "\n$", "")
        end
        local name, body = object_text(release, by_release[release], extra)
        assert(out[name] == nil, "two releases name the object " .. name)
        out[name] = body
    end
    return out
end
