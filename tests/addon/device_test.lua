import("fixtures")

function failures(opt)
    local device = import("charon.device", {rootdir = opt.modules, anonymous = true})
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
    os.tryrm(folder)
    return found
end
