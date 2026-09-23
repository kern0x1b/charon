-- xmake l tools/cache-sweep.lua [--dry-run] [CHECKOUT...]
--
-- Removes from $CHARON_HOME/cache the kept measurements of dyld.sdk_owners and dyld.first_releases
-- that no live checkout reads any more. The worktree sweep runs it; the measurements themselves never
-- remove a file, since two checkouts of different code share the cache and each would remove the
-- other's.
--
-- A checkout is live when it is a worktree of this repository (git worktree list) or is named on the
-- command line. Each one's own modules/apple/dyld.lua names the files it reads (dyld.kept_files), for
-- every iPhoneOS SDK in the shared xmake store and the ladder of every architecture it builds, over
-- the rungs held now under dyld.root(); a file of any other name is removed. A file whose name holds no
-- code key was written by code older than that naming, which cannot name its files: those stay while
-- such a checkout lives. A checkout this misses only costs its next run a measurement, never a wrong
-- answer, since the name of a file is the key of everything its content depends on.

local FAMILIES = {"sdk-owners", "first-release"}

local function live_checkouts(given)
    local root = path.absolute(path.join(os.scriptdir(), ".."))
    local found = {}
    local listed = os.iorunv("git", {"-C", root, "worktree", "list", "--porcelain"})
    for line in listed:gmatch("[^\n]+") do
        local checkout = line:match("^worktree (.+)$")
        if checkout then
            table.insert(found, checkout)
        end
    end
    for _, checkout in ipairs(given) do
        table.insert(found, path.absolute(checkout))
    end
    local kept = {}
    for _, checkout in ipairs(table.unique(found)) do
        if os.isfile(path.join(checkout, "modules", "apple", "dyld.lua")) then
            table.insert(kept, checkout)
        end
    end
    return kept
end

local function sdkdirs()
    local found = os.dirs(path.join(os.getenv("HOME"), ".xmake", "packages", "i", "iphoneos-sdk", "*", "*", "Developer.app",
                                    "Contents", "Developer", "Platforms", "iPhoneOS.platform", "Developer", "SDKs", "iPhoneOS*.sdk"))
    table.sort(found)
    return found
end

function main(...)
    local dry, given = false, {}
    for _, argument in ipairs({...}) do
        if argument == "--dry-run" then
            dry = true
        else
            table.insert(given, argument)
        end
    end
    local sdks = sdkdirs()
    local read, older = {}, {}
    local folder = path.join(path.directory(import("apple.dyld", {rootdir = path.join(os.scriptdir(), "..", "modules"), anonymous = true}).root()), "cache")
    for _, checkout in ipairs(live_checkouts(given)) do
        local modules = path.join(checkout, "modules")
        local dyld = import("apple.dyld", {rootdir = modules, anonymous = true})
        if dyld.kept_files then
            local backports = import("apple.backports", {rootdir = modules, anonymous = true})
            local architectures = import("apple.architectures", {rootdir = modules, anonymous = true})
            local ladders = {}
            for _, architecture in ipairs(architectures.names()) do
                table.insert(ladders, dyld.held_ladder(backports.compatible(architecture)))
            end
            for _, file in ipairs(dyld.kept_files(sdks, ladders)) do
                read[path.filename(file)] = true
            end
        else
            table.insert(older, checkout)
        end
    end
    local removed, kept, failed = 0, 0, {}
    for _, family in ipairs(FAMILIES) do
        for _, file in ipairs(os.files(path.join(folder, family .. "-*.tsv"))) do
            local name = path.filename(file)
            local rest = name:sub(#family + 2, -5)
            local unkeyed = not rest:find("-", 1, true)
            if read[name] or (unkeyed and #older > 0) then
                kept = kept + 1
            elseif dry then
                print("would remove %s", name)
                removed = removed + 1
            else
                local reason
                try {
                    function ()
                        os.rm(file)
                    end,
                    catch {
                        function (errors)
                            reason = tostring(errors)
                        end
                    }
                }
                reason = reason or (os.isfile(file) and "still there after removal" or nil)
                if reason then
                    table.insert(failed, name .. ": " .. reason)
                else
                    removed = removed + 1
                end
            end
        end
    end
    print("cache-sweep: %s: kept %d, %s %d", folder, kept, dry and "would remove" or "removed", removed)
    if #older > 0 then
        print("cache-sweep: files named without a code key stay, read by code older than that naming in: %s", table.concat(older, " "))
    end
    if #failed > 0 then
        raise("cache-sweep: could not remove %d file(s):\n%s", #failed, table.concat(failed, "\n"))
    end
end
