import("core.base.option")
import("@self.emulator")

function main()
    local command = option.get("command")
    if not command or #command == 0 then
        raise("xmake queue runs a command in a build slot: xmake queue -- xmake build")
    end
    local program, arguments = command[1], table.slice(command, 2)
    -- A build that the queue already started passes its slot down, so a nested
    -- build runs inside it instead of waiting for one its parent holds.
    if emulator.holds_build_slot() then
        os.execv(program, arguments)
        return
    end
    local count = tonumber(option.get("count")) or emulator.build_capacity()
    local slot = emulator.acquire({folder = path.join(emulator.root(), "build-slots"), count = count, patience = 0})
    local ok, errors = pcall(function ()
        os.execv(program, arguments, {envs = {[emulator.build_slot_name()] = tostring(slot.index)}})
    end)
    emulator.release(slot)
    if not ok then
        raise(errors)
    end
end
