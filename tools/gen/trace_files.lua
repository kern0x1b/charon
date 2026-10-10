-- Where the trace layer writes its outputs: the trace directory under a framework's build directory, and the four files in it.

local layout = import("layout", {anonymous = true})

-- The name of the trace layer's directory under a framework's build directory.
local TRACE_DIR = "trace"

-- The trace directory of a framework.
function trace_dir(tree, fw)
    return path.join(layout.gen_dir(tree, fw), TRACE_DIR)
end

-- The stubs of a framework: the generated defaults, built only with CHARON_TRACE_DEFAULTS.
function defaults_file(tree, fw)
    return path.join(trace_dir(tree, fw), fw .. "Defaults.m")
end

-- The members the trace layer left out, with the reason each one is left out.
function skipped_file(tree, fw)
    return path.join(trace_dir(tree, fw), "skipped.tsv")
end

-- One row per stub: the surface row it answers and the kind of member.
function stubs_file(tree, fw)
    return path.join(trace_dir(tree, fw), "stubs.tsv")
end

-- The class-object decision of every candidate class, with its reason.
function classes_file(tree, fw)
    return path.join(trace_dir(tree, fw), "classes.tsv")
end
