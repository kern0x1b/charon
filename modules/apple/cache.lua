-- The compiler cache every build in this tree runs its compilers through, and the two things that
-- differ between the callers: whether a run writes an object file, and whether its output is
-- wanted on stdout.
--
-- Why it is a module and not a function in one of its callers: the backports build and the lift
-- are the two things on this machine that run a compiler thousands of times, and they are the two
-- that were measured paying for the same work twice - the lift re-reading the SDK's headers for
-- every API name of the whole registry, and a gate recompiling units another band had already
-- compiled. A second copy of "find ccache on the path" is a second thing to keep right, and the
-- rule against that is not worth bending for the convenience of one caller.
--
-- What ccache changes is the cost of a compile, not its result: it runs the same compiler with the
-- same arguments, and on a hit it writes back the object the compiler wrote (measured: 21 of the
-- gate's own units across seven frameworks, every mode, shasum against a CCACHE_DISABLE=1 run of
-- the same sources, identical every time). For a run that writes no object - a lift's
-- -fsyntax-only -ast-dump, or a header probe - it replays the compiler's own output instead, and
-- that was measured too: with clang's per-process AST node ids normalised (they differ between
-- any two runs, cached or not) the dump is byte-identical, 5,370,418 bytes and 782 availability
-- attributes both ways.
--
-- Where the key comes from is the machine's business: hash_dir = false in the cache's own
-- ccache.conf is what lets two worktrees share one cache, and coordination/heavy.sh writes it.

local cached_program

-- The cache program to run a compiler through, or nil where there is none to run it through.
-- CCACHE_DISABLE takes it out for a build that has to show its own work, and ccache reads that
-- variable as set-at-all, empty value included - measured: with CCACHE_DISABLE= set ccache records
-- no call, and with it unset the second identical compile is a direct hit. CCACHE names the
-- program where it is not on the path, and is checked as hard as one found on the path, so a
-- stale value left by a brew upgrade that moved ccache costs the cache and not the build. xmake
-- 3.1.1 has no os.which, so the path is walked here; the answer is kept, because a build runs a
-- compiler thousands of times and neither the path nor the environment changes under it.
function program()
    if os.getenv("CCACHE_DISABLE") then
        return nil
    end
    if cached_program then
        return cached_program
    end
    local given = os.getenv("CCACHE")
    if given and given ~= "" then
        cached_program = os.isexec(given) and given or nil
    else
        for _, folder in ipairs((os.getenv("PATH") or ""):split(path.envsep())) do
            local found = path.join(folder, "ccache")
            if os.isexec(found) then
                cached_program = found
                break
            end
        end
    end
    return cached_program
end

-- The program and the arguments a compiler run goes through, the shape os.execv takes: the
-- wrapper is the program and the compiler its first argument, because os.execv runs a name it
-- cannot execute itself by splitting that name on spaces, and a checkout under a path with a
-- space in it has to survive that. Returns nil arguments when there is no cache, so a caller can
-- pass the result straight through.
function wrapped(compiler, arguments)
    local wrapper = program()
    if not wrapper or not compiler then
        return compiler, arguments
    end
    return wrapper, table.join({compiler}, arguments)
end

-- os.iorunv(compiler, arguments, opt) with the cache in front of the compiler, for a run whose
-- output the caller wants to read.
function iorunv(compiler, arguments, opt)
    local program, argv = wrapped(compiler, arguments)
    return os.iorunv(program, argv, opt)
end

-- os.execv(compiler, arguments, opt) with the cache in front of the compiler, for a run whose
-- status the caller wants. The status is the compiler's own: the cache returns it unchanged.
function execv(compiler, arguments, opt)
    local program, argv = wrapped(compiler, arguments)
    return os.execv(program, argv, opt)
end
