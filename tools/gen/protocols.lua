-- The protocol objects the generator emits for a framework, from the snapshot's protocol records (protocols.tsv and the header the
-- transcriber wrote). The objects are emitted only for the protocols the generation set names.

local layout = import("layout", {anonymous = true})
local tsv = import("tsv", {anonymous = true})
local files = import("files", {anonymous = true})
local releases = import("releases", {anonymous = true})

local GENERATED_STATUS = {["sdk16 body"] = true, transcribed = true}
local EM_DASH = "\226\128\148"

-- The objc protocols whose objects are generated. The decision is the protocols command's, which is not ported yet; until it
-- is, no protocol is named, and that is what the oracle does for all 281 frameworks (the set is empty everywhere, measured).
function generation_set(tree, fw)
    return {}
end

-- name -> the protocol's record in the snapshot (its release, status, reasons, bases, and members), or none when the framework
-- has no protocol snapshot.
function records(tree, fw)
    local out = {}
    local text = files.read_text(path.join(layout.snap_dir(tree, fw), "protocols.tsv"))
    if not text then
        return out
    end
    for _, row in ipairs(tsv.records(text)) do
        local record = out[row.protocol]
        if record == nil then
            record = {introduced = row.introduced, status = row.status, reasons = row.reasons, bases = row.bases, members = {}}
            out[row.protocol] = record
        end
        if row.section ~= "-" then
            table.insert(record.members, {section = row.section, kind = row.kind, instance = row.instance == "yes",
                                          selector = row.selector, decl = row.decl, in16 = row.in16})
        end
    end
    return out
end

-- The transcriber's header in the snapshot, by its file name, or nil.
local function header_name(tree, fw)
    local found = files.glob(path.join(layout.snap_dir(tree, fw), "Charon*Protocols.h"))
    return found[1] and path.filename(found[1]) or nil
end

-- The generated protocol files of a framework: name -> text. One source per release a protocol arrived in: each source names
-- every protocol of its release, so clang emits its protocol object there.
function protocol_files(tree, fw)
    local protocols = records(tree, fw)
    local wanted = generation_set(tree, fw)
    local generated, by_release, release_list = {}, {}, {}
    local any = false
    for name, record in pairs(protocols) do
        if GENERATED_STATUS[record.status] and wanted[name] then
            any = true
            generated[name] = record
            local release = record.introduced
            if by_release[release] == nil then
                by_release[release] = {}
                table.insert(release_list, release)
            end
            table.insert(by_release[release], name)
        end
    end
    local out = {}
    local header = nil
    if any then
        header = header_name(tree, fw)
    end
    if header then
        local text = assert(files.read_text(path.join(layout.snap_dir(tree, fw), header)), "no header " .. header)
        text = string.gsub(text, EM_DASH, "-")
        assert(not string.find(text, "[\128-\255]"), "not ASCII: " .. header)
        out[header] = text
    end
    for _, release in ipairs(releases.sorted(release_list)) do
        local names = table.move(by_release[release], 1, #by_release[release], 1, {})
        table.sort(names)
        local tag = string.gsub(release, "%.", "")
        local body = {layout.constants().MARK}
        local sdk16 = false
        for _, name in ipairs(names) do
            if generated[name].status == "sdk16 body" then
                sdk16 = true
            end
        end
        if sdk16 then
            table.insert(body, "#import <" .. fw .. "/" .. fw .. ".h>")
        end
        if header then
            table.insert(body, '#import "' .. header .. '"')
        end
        table.insert(body, "")
        table.insert(body, "__attribute__((used)) Protocol *const charon_" .. fw .. "_protocols" .. tag .. "[] = {")
        for _, name in ipairs(names) do
            table.insert(body, "    @protocol(" .. name .. "),")
        end
        table.insert(body, "};")
        out[fw .. "Protocols" .. tag .. ".m"] = table.concat(body, "\n") .. "\n"
    end
    return out
end
