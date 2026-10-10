-- The stubs of the trace layer for one framework: which declared members get one, the members left out with their reasons, and
-- the text of each stub. A stub logs its selector once to stderr, returns the zero of its return type, and sets an NSError **
-- parameter it names to an error in the framework's own domain. Its block parameters are not invoked.

local decl = import("decl", {anonymous = true})
local strings = import("strings", {anonymous = true})
local surface = import("surface", {anonymous = true})

-- The names the iOS build spells as its own types: a declaration may use them without the framework declaring them.
local BUILTIN_TYPES = strings.set({"BOOL", "NSInteger", "NSUInteger", "CGFloat", "NSTimeInterval", "NSError", "NSString", "NSNumber",
    "NSArray", "NSDictionary", "NSSet", "NSData", "NSURL", "NSDate", "NSUUID", "NSLocale", "NSMapTable", "NSPointerArray",
    "NSMeasurement", "NSIndexPath", "NSProgress", "NSOperationQueue", "NSNotificationName", "NSNotificationCenter",
    "NSOrderedSet", "NSCountedSet", "NSFileHandle", "NSBundle", "NSLayoutConstraint", "NSRange", "UInt32", "SInt32",
    "OSStatus", "Float32", "Float64", "Boolean", "AudioObjectID", "AudioStreamBasicDescription", "AudioBufferList",
    "AudioChannelLayout", "AudioComponentDescription", "AudioUnit", "AudioBuffer", "AudioUnitParameterID",
    "AudioUnitParameterValue", "AudioTimeStamp", "CFStringRef", "CFTypeRef", "CFURLRef", "CMTime", "CGPoint", "CGSize",
    "CGRect", "CFTimeInterval", "MIDIEndpointRef", "MIDIClientRef"})

-- Name prefixes of the macros and constants a declaration can spell: a capitalised word with one of them is not a type it needs.
local MACRO_PREFIXES = {"NS_", "API_", "CF_"}

-- Adds a member to a class, the class taking its place in the order the spec first names it.
local function add_member(found, cls, member)
    if found.members[cls] == nil then
        found.members[cls] = {}
        table.insert(found.order, cls)
    end
    table.insert(found.members[cls], member)
end

local function leave_out(skipped, api, reason)
    table.insert(skipped, {api = api, reason = reason})
end

local function has_hand(hand, cls, selector)
    return hand[cls] ~= nil and hand[cls][selector] ~= nil
end

-- The capitalised words a declaration spells that the framework does not declare, sorted (UNDECLARED_CHECK of tools/gen.py).
local function undeclared_types(text, declared)
    local seen, out = {}, {}
    for word in string.gmatch(text, "[%w_]+") do
        local macro = false
        for _, prefix in ipairs(MACRO_PREFIXES) do
            macro = macro or string.sub(word, 1, #prefix) == prefix
        end
        if string.match(word, "^%u") and not declared[word] and not BUILTIN_TYPES[word] and not macro and not seen[word] then
            seen[word] = true
            table.insert(out, word)
        end
    end
    table.sort(out)
    return out
end

-- The name of the NSError ** parameter a declaration names, or nil: NSError\s*\*\s*\*\s*\)?\s*(\w+), the first that matches.
local function error_argument(decl_text)
    local init = 1
    while true do
        local start, stop = string.find(decl_text, "NSError", init, true)
        if start == nil then
            return nil
        end
        local name = string.match(decl_text, "^%s*%*%s*%*%s*%)?%s*([%w_]+)", stop + 1)
        if name then
            return name
        end
        init = start + 1
    end
end

local function consider_property(r, text, env, found, skipped, seen)
    local cls = r.cls
    local name = decl.member_name(r.api)
    local selector = decl.getter_of(text, name)
    if env.overridden[r.api] or has_hand(env.hand, cls, name) or has_hand(env.hand, cls, selector) then
        return leave_out(skipped, r.api, "override or hand implementation")
    end
    local stripped = decl.strip_nullability(text)
    local type_text = decl.property_type_text(stripped, name)
    local zero = decl.resolve_kind(type_text, env.index)
    local readwrite = not string.find(stripped, "readonly", 1, true)
    local key = cls .. "\t" .. selector
    if seen[key] then
        return leave_out(skipped, r.api, "same selector declared twice in the class")
    end
    seen[key] = true
    add_member(found, cls, {api = "-[" .. cls .. " " .. selector .. "]", kind = "property-get", selector = selector,
                            type_text = type_text, zero = zero, decl = stripped})
    local setter = "set" .. string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2) .. ":"
    if readwrite and not has_hand(env.hand, cls, setter) and not env.overridden["-[" .. cls .. " " .. setter .. "]"] then
        add_member(found, cls, {api = "-[" .. cls .. " " .. setter .. "]", kind = "property-set", selector = setter,
                                type_text = type_text, zero = "void", decl = stripped})
    end
end

local function consider_method(r, text, env, found, skipped, seen)
    local cls = r.cls
    local selector = string.match(string.gsub(r.api, "%]+$", ""), "^[^ ]* (.*)$")
    assert(selector, "a method api names no selector: " .. r.api)
    if env.overridden[r.api] or has_hand(env.hand, cls, selector) then
        return leave_out(skipped, r.api, "override or hand implementation")
    end
    local stripped = decl.strip_nullability(text)
    local ret = string.match(stripped, "^[%-%+]%s*%(%s*([^%)]-)%s*%)")
    if ret == nil then
        return leave_out(skipped, r.api, "no return type parsed")
    end
    local key = cls .. "\t" .. selector
    if seen[key] then
        return leave_out(skipped, r.api, "same selector declared twice in the class")
    end
    seen[key] = true
    add_member(found, cls, {api = r.api, kind = "method", selector = selector, type_text = ret,
                            zero = decl.resolve_kind(ret, env.index), decl = stripped})
end

-- One spec row: the stub it gets, or the reason it is left out.
local function consider(r, env, found, skipped, seen)
    local text = strings.strip(strings.rstrip(r.decl, ";"))
    if env.release_missing ~= nil then
        local ledger_api = r.kind == "method" and r.api or (r.cls .. "." .. decl.member_name(r.api))
        if env.release_missing[surface.key(r.kind, ledger_api)] == nil then
            return leave_out(skipped, r.api, "implemented at 6.1.3: the release answers")
        end
    end
    local undeclared = undeclared_types(decl.strip_nullability(text), env.declared)
    if #undeclared > 0 then
        return leave_out(skipped, r.api, "type not declared for iOS: " .. table.concat(undeclared, ","))
    end
    if r.kind == "property" then
        return consider_property(r, text, env, found, skipped, seen)
    end
    return consider_method(r, text, env, found, skipped, seen)
end

-- The stubs of one framework from its spec rows. env: index (typedef name -> text), declared (set of names the iOS build sees),
-- overridden (set of canonical keys a registry row covers), hand (cls -> selector -> true, from the hand sources), and
-- release_missing (key(kind, api) -> status of the 6.1.3 ledger, or nil when the ledger is not there: every member is then
-- considered). Returns found = {order = the classes in the order the spec names them, members = cls -> list of members}, and
-- skipped = the list of {api, reason} the members left out got, in the order they were decided.
-- A member is {api, kind (method, property-get, property-set), selector, type_text, zero (void, object, scalar or struct), decl}.
function members(spec, env)
    local found = {order = {}, members = {}}
    local skipped, seen = {}, {}
    for _, r in ipairs(spec) do
        if r.kind == "method" or r.kind == "property" then
            consider(r, env, found, skipped, seen)
        end
    end
    return found, skipped
end

-- The text of one stub (stub_text of tools/gen.py). zero_kind is the kind of the return type; kind is one of method, property-get,
-- property-set or function.
function stub_text(fw, api, kind, selector, type_text, zero_kind, decl_text)
    local log = 'static BOOL charon_logged = NO; if (!charon_logged) { charon_logged = YES; fprintf(stderr, "unimplemented: '
        .. fw .. ' %s\\n", "' .. api .. '"); }'
    local name = error_argument(decl_text)
    local error_code = ""
    if name then
        error_code = "if (" .. name .. ") { *" .. name .. ' = [NSError errorWithDomain:@"' .. fw
            .. '.Unimplemented" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"' .. api .. ' is not implemented by the port"}]; } '
    end
    local zero
    if zero_kind == "void" then
        zero = ""
    elseif zero_kind == "object" then
        zero = kind == "function" and "return NULL;" or "return nil;"
    elseif zero_kind == "scalar" then
        zero = "return 0;"
    else
        zero = "return (" .. type_text .. "){0};"
    end
    local head
    if kind == "property-get" then
        head = "- (" .. type_text .. ")" .. selector
    elseif kind == "property-set" then
        head = "- (void)" .. string.sub(selector, 1, #selector - 1) .. ":(" .. type_text .. ")value"
    else
        head = decl_text
    end
    local sep = error_code ~= "" and (" " .. error_code) or " "
    return head .. " { " .. log .. sep .. zero .. " }"
end
