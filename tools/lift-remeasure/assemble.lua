-- The set file of one SDK, assembled from a measurement: the header the committed set carries, with the counts and the total
-- recounted from the lines the lift found (apple.lift's set_with_counts() does the counting, so the numbers are the code the
-- build reads them with), under those lines as the lift wrote them. Which lines are the known exceptions, and why, is prose
-- that no count derives: the header keeps it, and a line the header still names but the set no longer holds is a sentence
-- to write, which the driver reports.

-- The lines of a text that the set's header holds: the comments, in order.
local function header_of(text)
    local header = {}
    for line in text:gmatch("[^\n]+") do
        if line:startswith("#") then
            table.insert(header, line)
        end
    end
    return header
end

-- The lines of a text that are not comments: the set's body.
local function body_of(text)
    local body = {}
    for line in text:gmatch("[^\n]+") do
        if not line:startswith("#") then
            table.insert(body, line)
        end
    end
    return body
end

-- The set text that measured holds: the header of before, with its counts and total recounted from the lines of alone (the lift's
-- left-alone.txt), series as the header's parenthetical unless series is given. Refuses (raises) a header that cannot carry the
-- counts, rather than inventing a line for them.
function set_text(modules, before, alone, series)
    local apple_lift = import("apple.lift", {rootdir = modules, anonymous = true})
    return apple_lift.set_with_counts(header_of(before), body_of(alone), series)
end

-- What a set's header says about its own lines and the lines it holds, where they disagree: the three counts and the total, each
-- against what the body counts. An empty list is a set whose header is true.
function mismatches(text)
    local said, total = {}, nil
    for _, line in ipairs(header_of(text)) do
        for _, kind in ipairs({"class", "undeclared", "unmatched"}) do
            local count = line:match("^#  %- " .. kind .. " %((%d+)%):")
            if count then
                said[kind] = tonumber(count)
            end
        end
        local lines = line:match("^# %(.*%), none dropped: (%d+) lines%.$")
        if lines then
            total = tonumber(lines)
        end
    end
    local counted, lines = {}, 0
    for _, line in ipairs(body_of(text)) do
        local kind = line:match("^(%a+)\t")
        counted[kind] = (counted[kind] or 0) + 1
        lines = lines + 1
    end
    local out = {}
    for _, kind in ipairs({"class", "undeclared", "unmatched"}) do
        if said[kind] ~= nil and said[kind] ~= (counted[kind] or 0) then
            table.insert(out, string.format("the header says %s (%d), the set has %d", kind, said[kind], counted[kind] or 0))
        end
    end
    if total == nil then
        table.insert(out, "the header says no total of lines")
    elseif total ~= lines then
        table.insert(out, string.format("the header says %d lines, the set has %d", total, lines))
    end
    return out
end
