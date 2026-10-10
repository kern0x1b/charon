-- The NSObject selectors the generator's commands read, in one place. The lists are the oracle's (tools/gen.py): the trace layer leaves
-- out an init, new, copy or mutableCopy the surface does not list (its inherited behaviour is what a call reaches); the scope takes an
-- implicit NSObject selector or one a macro hides, which adds dealloc and description. cmd_scope keeps its own copy of the scope's list
-- until it imports this module (the owner of cmd_scope to change).

-- The selectors the trace layer leaves out when the surface does not list them (tools/gen.py stub_members).
local TRACE_INHERITED = {init = true, new = true, copy = true, mutableCopy = true}

-- The selectors whose bare form the header parse does not spell (tools/gen.py scope).
local SCOPE_IMPLICIT = {init = true, new = true, copy = true, mutableCopy = true, dealloc = true, description = true}

-- True when the trace layer leaves a selector out, when the surface does not list it.
function trace_inherited(selector)
    return TRACE_INHERITED[selector] == true
end

-- True when the scope reads a selector as implicit from NSObject.
function scope_implicit(selector)
    return SCOPE_IMPLICIT[selector] == true
end
