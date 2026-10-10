-- The byte order of the generator's sorts (less, strings, keys). The one definition is modules/apple/order.lua: the package's own code
-- (modules/apple/backports.lua, read by lift's key and by the registry's fixtures) sorts with it too, and a copy of the modules alone
-- carries it. This file re-exports it for tools/gen, so every sort of a name in the generator still reads order.less.
local byte = import("apple.order", {rootdir = path.join(os.scriptdir(), "..", "..", "modules"), anonymous = true})

less = byte.less
strings = byte.strings
keys = byte.keys
