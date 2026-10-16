-- check.lua - the -init and +new rows of HomeKit and HealthKit that the release's own class does not define.
--
-- Measured with tools/objc-init-members.lua over the arm64e cache of iOS 16.0: none of these classes carries
-- -init or +new in its own list, so a caller reaches NSObject's pair. (The HealthKit classes that DO carry
-- -init on 16.0 are not here: their rows stay absent until their -init is measured at runtime.) The port must therefore define neither, and every row must say
-- implemented, with the facts file the row names.
--
-- Two things are asked, and each one has a control:
--   * the REGISTRY: every row named here is implemented. A row that went back to absent would say that
--     respondsToSelector: answers NO, which the NSObject pair contradicts.
--   * the SOURCE: no @implementation block of a class named here defines -init or +new. The control is
--     HMAction, which defines an -init of its own, so a scanner that reads nothing would report 0 for it and
--     the check says so.
--
-- What this does NOT check is the object: the built library's own class list. The gate's objects carry it,
-- and it is read with objc.binary_inventory when a gate run is kept; the source check is the one that runs on
-- every light guard.

local json = import("core.base.json")

local failures, checks = 0, 0

local function expect(name, condition)
    checks = checks + 1
    if not condition then
        failures = failures + 1
        print("FAIL " .. name)
    end
end

-- The rows this group closes: the 24 HomeKit rows, HKDeletedObject's -init and HKClinicalRecord's +new.
local rows = {
    "-[HMAccessoryProfile init]", "+[HMAccessorySetupPayload new]", "-[HMAccessorySetupPayload init]",
    "+[HMAccessorySetupResult new]", "-[HMAccessorySetupResult init]", "-[HMCalendarEvent init]",
    "-[HMCameraProfile init]", "-[HMCharacteristicThresholdRangeEvent init]", "+[HMCharacteristicWriteAction new]",
    "-[HMDurationEvent init]", "+[HMEvent new]", "-[HMEventTrigger init]", "-[HMHomeAccessControl init]",
    "-[HMMutableCalendarEvent init]", "-[HMMutableCharacteristicEvent init]",
    "-[HMMutableCharacteristicThresholdRangeEvent init]", "-[HMMutableDurationEvent init]",
    "-[HMMutablePresenceEvent init]", "-[HMNumberRange init]", "-[HMPresenceEvent init]",
    "-[HMSignificantTimeEvent init]", "-[HMTrigger init]", "-[HMCharacteristicWriteAction init]", "-[HMEvent init]",
    "-[HKDeletedObject init]", "+[HKClinicalRecord new]",
}

-- The classes whose own lists carry neither selector: no @implementation block of theirs may define one.
local neither = {
    "HMAccessoryProfile", "HMAccessorySetupPayload", "HMAccessorySetupResult", "HMCalendarEvent", "HMCameraProfile",
    "HMCharacteristicThresholdRangeEvent", "HMCharacteristicWriteAction", "HMDurationEvent", "HMEvent", "HMEventTrigger",
    "HMHomeAccessControl", "HMMutableCalendarEvent", "HMMutableCharacteristicEvent",
    "HMMutableCharacteristicThresholdRangeEvent", "HMMutableDurationEvent", "HMMutablePresenceEvent", "HMNumberRange",
    "HMPresenceEvent", "HMSignificantTimeEvent", "HMTrigger",
    "HKDeletedObject",
}

-- Every @implementation block of a class in `wanted`, read line by line, with each -init and +new it defines.
local function definitions(files, wanted)
    local found = {}
    for name in pairs(wanted) do
        found[name] = {}
    end
    for _, file in ipairs(files) do
        local current = nil
        for line in io.lines(file) do
            local cls = line:match("^@implementation%s+([%w_]+)")
            if cls then
                current = wanted[cls] and cls or nil
            elseif line:match("^@end") then
                current = nil
            end
            if current then
                local sign, sel = line:match("^([-+])%s*%([^)]*%)%s*([%w_]+)")
                if not sign then
                    sign, sel = line:match("^([-+])%s*([%w_]+)")
                end
                if (sign == "-" and sel == "init") or (sign == "+" and sel == "new") then
                    table.insert(found[current], path.filename(file) .. ": " .. line)
                end
            end
        end
    end
    return found
end

function main(charon)
    local apple = path.join(charon, "packages", "a", "apple-backports")
    local files = table.join(os.files(path.join(apple, "HomeKit", "*.m")), os.files(path.join(apple, "HealthKit", "*.m")))

    -- REGISTRY: each row named above is implemented
    local status = {}
    for _, file in ipairs(table.join(os.files(path.join(apple, "registry", "HomeKit", "*.json")),
                                     os.files(path.join(apple, "registry", "HealthKit", "*.json")))) do
        local data = json.decode(io.readfile(file))
        local entries = data.entries or data
        for _, entry in ipairs(entries) do
            if entry.api then
                status[entry.api] = entry.status
            end
        end
    end
    for _, api in ipairs(rows) do
        expect(api .. " is implemented in the registry", status[api] == "implemented")
    end

    -- SOURCE: neither selector is defined by any block of the classes named as carrying neither
    local wanted = {}
    for _, name in ipairs(neither) do
        wanted[name] = true
    end
    wanted["HMAction"] = true -- the control: this class defines an -init of its own
    local defined = definitions(files, wanted)
    expect("the control HMAction shows its own -init, so the scanner reads blocks", #defined["HMAction"] == 1)
    for _, name in ipairs(neither) do
        expect(name .. " defines neither -init nor +new in the port", #defined[name] == 0)
    end

    print(string.format("checks=%d failures=%d", checks, failures))
    if failures > 0 then
        raise("init-inherited: %d of %d checks failed", failures, checks)
    end
end
