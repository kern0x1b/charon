-- The member rows of a framework from its shard facts (headers.shard_facts, design-foundation.md 5.7): the port of member_rows in
-- tools/gen.py on the IR. One row per member, the first occurrence per api. A member's api is side, "[", the class, a space, the
-- name and "]": the class is the one the USR names (a category member keeps its class), and the side is the shard's: "+" for a
-- class method or class property (section 3.5). Protocol members are not in the shards (the protocols transcriber owns them).
-- The declaration text is not a spec column (ruling D8: the docs generator re-derives it at doc time), so decl is "-"; the
-- availability is the text rendered from the IR's fields (ruling D7); the hash is the declaration hash (the IR's declhash).

-- The mangled key of an api: a C identifier. A class member's key starts with class_, so it never collides with an instance member
-- of the same selector (mangle in tools/gen.py).
function mangle(api)
    local body = string.gsub(string.gsub(api, "[^A-Za-z0-9]+", "_"), "^_+", "")
    body = string.gsub(body, "_+$", "")
    if string.sub(api, 1, 1) == "+" then
        return "class_" .. body
    end
    return body
end

-- The spec rows of a framework's members, from its shard facts. classes is the set of the class names the arm64 slice exports
-- (tbd.exports); tbd is "class-exported" for a member whose class is in it, else "class-not-exported".
function rows(members, classes, framework)
    local out, seen = {}, {}
    for _, m in ipairs(members) do
        if not seen[m.api] then
            seen[m.api] = true
            table.insert(out, {kind = m.kind, api = m.api, cls = m.cls, key = mangle(m.api), introduced = "-", decl = "-",
                               availability = m.text ~= "" and m.text or "-", hash = m.hash, value_status = "-", value = "-",
                               host_value = "-", value_source = "-", owned = "-",
                               tbd = classes[m.cls] and "class-exported" or "class-not-exported", shape = "-", measured = "-"})
        end
    end
    return out
end
