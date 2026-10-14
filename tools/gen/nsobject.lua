-- The NSObject selectors the generator's commands read, in one place. The scope's list is the oracle's (tools/gen.py:1929);
-- the trace lists are this port's, not the oracle's: the trace layer leaves out an init, new, copy or mutableCopy the surface does not list
-- or the headers declare unavailable (its inherited behaviour is what a call reaches). The scope takes an implicit NSObject selector or one a
-- macro hides, which adds dealloc and description. cmd_trace and cmd_scope read their lists here.

-- The selectors the trace layer leaves out when the surface does not list them: this port's rule. The oracle's member_skip
-- (tools/gen.py:991) has no name rule for them.
local TRACE_INHERITED = {init = true, new = true, copy = true, mutableCopy = true}

-- The selectors whose bare form the header parse does not spell (the oracle's SCOPE_IMPLICIT, tools/gen.py:1929).
local SCOPE_IMPLICIT = {init = true, new = true, copy = true, mutableCopy = true, dealloc = true, description = true}

-- The reason the trace layer leaves out an init or new the headers declare unavailable: no override, the inherited NSObject behaviour
-- is what a call reaches (the flag is the shard's, see declared_unavailable). This port's rule: the oracle's member_skip
-- (tools/gen.py:991) has no unavailable rule.
local UNAVAILABLE_REASON = "init/new the 26.2 headers declare unavailable: no override, NSObject's behaviour is what a call reaches"

-- The state the scope gives a row the trace layer leaves out for UNAVAILABLE_REASON: the oracle's gap text (tools/gen.py:2068),
-- which its QUEUE_NEXT (tools/gen.py:1949) queues.
local UNAVAILABLE_STATE = "init/new: not spelled by the 26.2 headers (implicit, or unavailable by a macro)"

-- The reason the trace layer leaves out an init or new the headers declare unavailable (see UNAVAILABLE_REASON).
function unavailable_reason()
    return UNAVAILABLE_REASON
end

-- The scope's state of a row the trace layer leaves out for unavailable_reason().
function unavailable_state()
    return UNAVAILABLE_STATE
end

-- True when the trace layer leaves a selector out, when the surface does not list it.
function trace_inherited(selector)
    return TRACE_INHERITED[selector] == true
end

-- True when a shard's availability column flags the declaration unavailable on every platform (the "*unavailable" flag, tools/found/avail.lua):
-- an NS_UNAVAILABLE or a macro such as AV_INIT_UNAVAILABLE in the class body.
function declared_unavailable(availability)
    for flag in string.gmatch(availability or "", "%S+") do
        if flag == "*unavailable" then
            return true
        end
    end
    return false
end

-- True when the scope reads a selector as implicit from NSObject.
function scope_implicit(selector)
    return SCOPE_IMPLICIT[selector] == true
end
