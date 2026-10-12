-- xmake l tools/sdk-verbatim.lua SDKROOT FILE...
--
-- Finds the comment lines of FILE... that occur verbatim among the header lines of the SDK at SDKROOT.
-- A comment copied from an SDK header is Apple's expression in our tree, which the workspace rule keeps
-- out of a repository (2026-10-12). This is the mechanical half of that rule: it names each hit by file
-- and line, and a person decides whether the line is a fact (a declaration, a measured value) or prose.
--
-- A comment line is the text one comment run holds on a source line: the part of `//` or `///` after
-- the marker, or the part of a `/* */` comment on the line, outside string and character literals.
-- Both sides are normalised the same way before they are compared: a trailing `*/`, the leading marker
-- characters (`/`, `!`, `*`), and whitespace runs (collapsed to one space) are dropped, and the text is
-- trimmed. A comment line is compared when it has a letter or digit, and at least 20 characters or 4
-- words after that; shorter lines are too common to mean a copy, and a ruler is a shape, not prose.
--
-- The SDK side is the comment text of every .h under System/Library/Frameworks and usr/include, read the
-- same way. Declarations are not compared: a signature is a fact, and a port comment that repeats one is
-- not a copy of Apple's expression. Matching is equality of the whole normalised comment run: a substring
-- of a longer SDK comment is not a hit.
--
-- Exit status: 0 when nothing matched; 1 when at least one comment line matched; 2 when the SDK root is
-- unreadable, a file cannot be read, or no comment line or no SDK line was compared. The text of a hit is
-- not printed, only its file and line: the output of a run is kept in a verdict file.
local MIN_CHARS, MIN_WORDS = 20, 4
local SDK_DIRS = {"System/Library/Frameworks", "usr/include"}

local function normalise(text)
    text = text:gsub("%s*%*/%s*$", "")
    text = text:gsub("^%s*[/!*]+", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^ ", ""):gsub(" $", "")
    return text
end

local function count_words(text)
    local n = 0
    for _ in text:gmatch("%S+") do n = n + 1 end
    return n
end

-- A ruler (a line of dashes or stars) has no words in it and is not compared: it is a shape, not prose.
local function compared(text)
    if not text:find("%w") then return false end
    return #text >= MIN_CHARS or count_words(text) >= MIN_WORDS
end

-- The comment runs of one line, given whether the line starts inside a block comment. Returns the runs
-- and whether the line ends inside a block comment. String and character literals are skipped, so a
-- `//` inside a string is not read as a comment.
local function comment_runs(line, in_block)
    local runs, i, n = {}, 1, #line
    while i <= n do
        if in_block then
            local close = line:find("*/", i, true)
            runs[#runs + 1] = line:sub(i, close and close - 1 or n)
            if not close then return runs, true end
            in_block = false
            i = close + 2
        else
            local one, two = line:sub(i, i), line:sub(i, i + 1)
            if one == '"' or one == "'" then
                local j = i + 1
                while j <= n and line:sub(j, j) ~= one do
                    if line:sub(j, j) == "\\" then j = j + 1 end
                    j = j + 1
                end
                i = j + 1
            elseif two == "//" then
                runs[#runs + 1] = line:sub(i + 2)
                return runs, false
            elseif two == "/*" then
                in_block = true
                i = i + 2
            else
                i = i + 1
            end
        end
    end
    return runs, in_block
end

function scan(root, files)
    local report = {errors = {}, hits = {}, comments = 0, files = 0, sdk_headers = 0, sdk_lines = 0, sdk_comments = 0}
    local frameworks = path.join(root, SDK_DIRS[1])
    if not os.isdir(frameworks) then
        table.insert(report.errors, "SDK root unreadable: no " .. frameworks)
        return report
    end

    -- Our comment lines, by normalised text: text -> the "file:line" places it occurs.
    local ours = {}
    for _, file in ipairs(files) do
        local handle = io.open(file, "r")
        if not handle then
            table.insert(report.errors, "cannot read " .. file)
        else
            report.files = report.files + 1
            local in_block, n = false, 0
            for line in handle:lines() do
                n = n + 1
                local runs
                runs, in_block = comment_runs(line, in_block)
                for _, run in ipairs(runs) do
                    local text = normalise(run)
                    if compared(text) then
                        report.comments = report.comments + 1
                        ours[text] = ours[text] or {}
                        table.insert(ours[text], file .. ":" .. n)
                    end
                end
            end
            handle:close()
        end
    end

    -- The SDK's comment lines, each header read once, against our texts. Only comment text is compared:
    -- the declarations an SDK header carries are facts (2026-10-12), and a port comment that repeats one
    -- is not a copy of Apple's expression. Counted separately so the two readings can be told apart.
    local matched = {}
    for _, dir in ipairs(SDK_DIRS) do
        for _, header in ipairs(os.files(path.join(root, dir, "**.h"))) do
            local handle = io.open(header, "r")
            if not handle then
                table.insert(report.errors, "cannot read SDK header " .. header)
            else
                report.sdk_headers = report.sdk_headers + 1
                local in_block = false
                for line in handle:lines() do
                    report.sdk_lines = report.sdk_lines + 1
                    local runs
                    runs, in_block = comment_runs(line, in_block)
                    for _, run in ipairs(runs) do
                        local text = normalise(run)
                        if compared(text) then report.sdk_comments = report.sdk_comments + 1 end
                        if ours[text] then matched[text] = true end
                    end
                end
                handle:close()
            end
        end
    end

    for text in pairs(matched) do
        for _, where in ipairs(ours[text]) do table.insert(report.hits, where) end
    end
    table.sort(report.hits)
    if report.comments == 0 then table.insert(report.errors, "no comment line compared") end
    if report.sdk_comments == 0 then table.insert(report.errors, "no SDK comment line compared") end
    return report
end

function main(root, ...)
    local files = {...}
    if not root or #files == 0 then
        print("usage: xmake l tools/sdk-verbatim.lua SDKROOT FILE...")
        os.exit(2)
    end
    local report = scan(root, files)
    for _, e in ipairs(report.errors) do print("sdk-verbatim: FAIL " .. e) end
    print(string.format("sdk-verbatim: compared %d comment line(s) of %d file(s) with %d SDK comment line(s) (of %d SDK header line(s) in %d header(s))",
        report.comments, report.files, report.sdk_comments, report.sdk_lines, report.sdk_headers))
    for _, where in ipairs(report.hits) do print("HIT " .. where) end
    print(string.format("sdk-verbatim: %d hit(s)", #report.hits))
    if #report.errors > 0 then os.exit(2) end
    if #report.hits > 0 then os.exit(1) end
end
