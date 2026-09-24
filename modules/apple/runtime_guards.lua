import("compat")

-- The guards of the Swift runtime's weak imports. A weak import that no library of the runtime and no library of the C++
-- runtime it links exports is NULL on a release in the runtime's range that lacks it, and every one of them is called only
-- behind a guard in the runtime's own source; this table names that guard for each, by library file name and then symbol
-- as the symbol table spells it. Two readers: swift-runtime's on_test, which fails an install whose weak imports and this
-- table differ in either direction, and the checks after a program's link (platform.import_options), which report a weak
-- import a carried copy of the runtime makes only if it is recorded here and refuse any other as the program's own.
-- source is the line of the guard at the commit the recipe builds (swift b8189d76), or the patch of this repository
-- that adds it.
GUARDS = {
}

-- found: what dyld.unexported_weak_imports answers for the installed libraries. Returns what differs, one line each. A weak
-- import the toolchain's own code guards (apple.compat's GUARDED) is answered there, for every image, and not here.
function compare(found)
    local problems = {}
    local tested = compat.guarded()
    for _, library in ipairs(table.orderkeys(found)) do
        local recorded = GUARDS[library] or {}
        for _, symbol in ipairs(found[library]) do
            if tested[symbol:sub(2)] then
                if recorded[symbol] then
                    table.insert(problems, string.format("apple.runtime_guards records %s for %s, which apple.compat's GUARDED already answers for every image", symbol, library))
                end
            elseif not recorded[symbol] then
                table.insert(problems, string.format("%s weakly imports %s, which no library of the runtime exports, and apple.runtime_guards records no guard for it", library, symbol))
            end
        end
    end
    for _, library in ipairs(table.orderkeys(GUARDS)) do
        local imported = {}
        for _, symbol in ipairs(found[library] or {}) do
            imported[symbol] = true
        end
        for _, symbol in ipairs(table.orderkeys(GUARDS[library])) do
            if found[library] and not imported[symbol] then
                table.insert(problems, string.format("apple.runtime_guards records %s for %s, which does not weakly import it", symbol, library))
            end
        end
    end
    return problems
end
