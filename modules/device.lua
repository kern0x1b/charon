import("core.base.option")
import("lib.detect.find_tool")

CHOSEN = "CHARON_DEVICE"

local defaults = {host = "127.0.0.1", port = "2222", password = "", udid = ""}

local ssh_options = {
    "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
    "-o", "LogLevel=ERROR", "-o", "ConnectTimeout=8",
    "-o", "HostKeyAlgorithms=+ssh-rsa", "-o", "PubkeyAcceptedKeyTypes=+ssh-rsa",
    "-o", "KexAlgorithms=+diffie-hellman-group1-sha1,diffie-hellman-group14-sha1",
    "-o", "Ciphers=+aes128-cbc,3des-cbc",
    "-o", "ControlMaster=auto", "-o", "ControlPersist=60",
    "-o", "ControlPath=/tmp/charon-ssh-%h-%p"
}

function read_env_file(file)
    local values = {}
    if not os.isfile(file) then
        return values
    end
    for raw in io.readfile(file):gmatch("[^\n]+") do
        local line = raw:trim()
        if line ~= "" and not line:startswith("#") then
            if line:startswith("export ") then
                line = line:sub(8):ltrim()
            end
            local key, value = line:match("^([%a_][%w_]*)=(.*)$")
            if key then
                value = value:trim()
                local quote = value:sub(1, 1)
                if quote == "'" or quote == '"' then
                    local finish = value:find(quote, 2, true)
                    value = finish and value:sub(2, finish - 1) or value:sub(2)
                else
                    value = value:gsub("%s+#.*$", ""):trim()
                end
                values[key] = value
            end
        end
    end
    return values
end

function env_file(root, name)
    local chosen = name or os.getenv(CHOSEN)
    return path.join(root, chosen and ("device." .. chosen .. ".env") or "device.env")
end

function bind(root, name)
    local file = env_file(root, name)
    if not os.isfile(file) and not os.getenv("DEVICE_HOST") then
        local known = {}
        for _, found in ipairs(os.files(path.join(root, "device*.env"))) do
            table.insert(known, path.filename(found))
        end
        table.sort(known)
        raise("nothing names a phone: %s does not exist and DEVICE_HOST is unset%s. %s:%s is not a safe guess - on a machine with a USB tunnel it reaches whichever phone that tunnel serves.",
              file, #known > 0 and (" (this port has " .. table.concat(known, ", ") .. ")") or "", defaults.host, defaults.port)
    end
    local values = read_env_file(file)
    local function value(...)
        for _, key in ipairs({...}) do
            local found = values[key] or os.getenv(key)
            if found and found ~= "" then
                return found
            end
        end
    end
    return {
        host = value("DEVICE_HOST") or defaults.host,
        port = value("DEVICE_PORT") or defaults.port,
        password = value("DEVICE_PASSWORD", "DEVICE_PASS") or defaults.password,
        udid = value("DEVICE_UDID") or defaults.udid
    }
end

function where(settings)
    return settings.host .. ":" .. settings.port
end

local function port_open(host, port)
    return try { function ()
        os.runv("nc", {"-z", "-G", "2", host, port})
        return true
    end }
end

function tunnel(settings)
    if settings.host ~= "127.0.0.1" or port_open(settings.host, settings.port) then
        return
    end
    local iproxy = find_tool("iproxy")
    if not iproxy then
        return
    end
    local udid = settings.udid
    if udid == "" then
        local attached = (try { function () return os.iorunv("idevice_id", {"-l"}) end } or ""):split("%s+")
        if #attached == 1 then
            udid = attached[1]
        end
    end
    if udid == "" then
        wprint("tunnel on %s is down and DEVICE_UDID is not set", settings.port)
        return
    end
    try { function () os.runv("pkill", {"-f", "iproxy " .. settings.port .. " "}) end }
    os.execv("sh", {"-c", string.format("nohup %s %s 22 -u %s > /tmp/iproxy-%s.log 2>&1 &", iproxy.program, settings.port, udid, settings.port)})
    os.sleep(3000)
end

local function authenticated(settings, program, argv)
    if settings.password == "" then
        return program, argv, nil
    end
    return "sshpass", table.join({"-e", program}, argv), {SSHPASS = settings.password}
end

function run(settings, command, opt)
    opt = opt or {}
    if command:find("killall", 1, true) then
        wprint("killing a VoIP application makes iOS 6 relaunch it and kill it again for holding a file lock (0xdead10cc); quit it from the switcher instead")
    end
    tunnel(settings)
    local program, argv, envs = authenticated(settings, "ssh", table.join(ssh_options, {"-p", settings.port, "root@" .. settings.host, command}))
    if opt.capture then
        return os.iorunv(program, argv, {envs = envs})
    end
    os.execv(program, argv, {envs = envs, try = opt.try})
end

function copy(settings, localfile, remote)
    tunnel(settings)
    local program, argv, envs = authenticated(settings, "scp", table.join(ssh_options, {"-P", settings.port, localfile, "root@" .. settings.host .. ":" .. remote}))
    os.execv(program, argv, {envs = envs})
end

function fetch(settings, remote, localfile)
    tunnel(settings)
    local program, argv, envs = authenticated(settings, "scp", table.join(ssh_options, {"-P", settings.port, "root@" .. settings.host .. ":" .. remote, localfile}))
    return try { function ()
        os.runv(program, argv, {envs = envs})
        return true
    end }
end

function identity_conflicts(settings, stage)
    import("apple.bundle")
    local conflicts = {}
    for _, plist in ipairs(os.files(path.join(stage, "Applications", "*.app", "Info.plist"))) do
        local packaged = bundle.read_plist(plist).CFBundleIdentifier
        local relative = path.relative(plist, stage)
        local fetched = os.tmpfile() .. ".plist"
        if fetch(settings, "/" .. relative, fetched) and os.isfile(fetched) then
            local installed = bundle.read_plist(fetched).CFBundleIdentifier
            os.rm(fetched)
            if installed ~= packaged then
                table.insert(conflicts, string.format("/%s on the phone is %s, and this package installs %s over it; SpringBoard would lose the app until a reboot, so remove the installed one first", path.directory(relative), tostring(installed), tostring(packaged)))
            end
        end
    end
    return conflicts
end

function log(settings, seconds, text)
    local syslog = find_tool("idevicesyslog")
    if not syslog then
        raise("idevicesyslog is not installed; brew install libimobiledevice reads the phone's log over USB without Xcode")
    end
    local argv = {}
    if settings.udid ~= "" then
        table.join2(argv, {"-u", settings.udid})
    end
    if text and text ~= "" then
        table.join2(argv, {"-m", text})
    end
    os.execv("sh", {"-c", string.format("%s %s & reader=$!; sleep %d; kill $reader 2>/dev/null; wait $reader 2>/dev/null; true",
                                       syslog.program, os.args(argv), seconds)})
end
