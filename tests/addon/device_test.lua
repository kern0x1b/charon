import("fixtures")

function claim_failures(device, folder)
    local found = {}
    local home, holder = os.getenv("CHARON_HOME"), os.getenv("CHARON_DEVICE_HOLDER")
    os.setenv("CHARON_HOME", path.join(folder, "home"))
    local phone = {host = "10.0.0.7", port = "22", password = "", udid = "abc123"}
    device.claim(phone, "first", 30)
    local errors = fixtures.refusal(function () device.claim(phone, "second", 30) end)
    if not errors or not errors:find("held by first", 1, true) then
        table.insert(found, "a claimed device must refuse a second holder, naming the first: " .. tostring(errors))
    end
    if not fixtures.refusal(function () device.release(phone, "second") end) then
        table.insert(found, "only the holder releases a claim")
    end
    os.setenv("CHARON_DEVICE_HOLDER", "second")
    errors = fixtures.refusal(function () device.tunnel(phone) end)
    if not errors or not errors:find("held by first", 1, true) then
        table.insert(found, "reaching a device another holder claimed must be refused: " .. tostring(errors))
    end
    os.setenv("CHARON_DEVICE_HOLDER", "first")
    if fixtures.refusal(function () device.tunnel(phone) end) then
        table.insert(found, "the holder reaches the device it claimed")
    end
    device.release(phone, "first")
    if device.lease("abc123") then
        table.insert(found, "a released device has no claim")
    end
    device.claim(phone, "second", 30)
    io.writefile(path.join(folder, "home", "devices", "abc123.lease", "holder"), "second\n" .. (os.time() - 1) .. "\n")
    if device.lease("abc123") or fixtures.refusal(function () device.claim(phone, "third", 5) end) then
        table.insert(found, "an expired claim frees the device")
    end
    if not fixtures.refusal(function () device.claim({host = "10.0.0.7", port = "22", password = "", udid = ""}, "first", 5) end) then
        table.insert(found, "a device without a UDID cannot be claimed")
    end
    for name, value in pairs({CHARON_HOME = home or false, CHARON_DEVICE_HOLDER = holder or false}) do
        if value then
            os.setenv(name, value)
        else
            os.setenv(name, nil)
        end
    end
    return found
end

function failures(opt)
    local device = import("device", {rootdir = opt.modules, anonymous = true})
    local found = {}
    local folder = fixtures.scratch()
    io.writefile(path.join(folder, "device.env"), table.concat({
        "# the phone on the desk",
        "export DEVICE_HOST=10.0.0.7",
        "DEVICE_PORT='22' # quoted",
        "DEVICE_PASSWORD=\"secret value\"",
        "DEVICE_UDID=abc123 # trailing",
        "not a line"
    }, "\n"))
    io.writefile(path.join(folder, "device.spare.env"), "DEVICE_HOST=10.0.0.8\n")
    local settings = device.bind(folder)
    local wanted = {host = "10.0.0.7", port = "22", password = "secret value", udid = "abc123"}
    for key, value in pairs(wanted) do
        if settings[key] ~= value then
            table.insert(found, string.format("device.env gives %s=%s, read %s", key, value, tostring(settings[key])))
        end
    end
    if device.bind(folder, "spare").host ~= "10.0.0.8" then
        table.insert(found, "a named device reads device.NAME.env")
    end
    local errors = fixtures.refusal(function () device.bind(folder, "absent") end)
    if not errors or not errors:find("this port has device.env, device.spare.env", 1, true) then
        table.insert(found, "a phone nothing names must be refused, listing the env files there are: " .. tostring(errors))
    end
    table.join2(found, claim_failures(device, folder))
    os.tryrm(folder)
    return found
end
