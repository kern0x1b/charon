# renames.sh — sourced, not run: renames() prints the -D flags that give every class and exported symbol the
# object files define, and every selector but the kept ones, a CharonHost prefix, so the backport and the system
# implementation can live side by side in one process. uikit2/run.sh and dynamics/run.sh build with it.
renames() {
    # $1: newline separated object files, $2: selectors that must keep their name
    keep=$2
    defined=$(nm -m $1 | grep -v '(undefined)')
    printf '%s\n' "$defined" | sed -n 's/.* external _OBJC_CLASS_\$_\(.*\)/-D\1=CharonHost\1/p' | sort -u
    printf '%s\n' "$defined" | sed -n 's/.* external _\([A-Za-z_][A-Za-z0-9_]*\)$/\1/p' | grep -v '^OBJC_' | sort -u |
        awk '{ print "-D" $0 "=CharonHost" $0 }'
    [ "$keep" = "*" ] && return 0
    keep="$keep init initWithCoder copyWithZone mutableCopyWithZone encodeWithCoder description isEqual hash supportsSecureCoding dealloc load initialize"
    nm $1 | sed -n 's/.*[-+]\[[A-Za-z_]*(*[A-Za-z]*)* \([A-Za-z_][A-Za-z0-9_]*\).*\]$/\1/p' | grep -v '^charon_' | sort -u |
        awk -v keep="$keep" '
            BEGIN { split(keep, kept, " "); for (index_ in kept) skip[kept[index_]] = 1 }
            { if ($0 in skip) next
              name = $0
              if (name ~ /^set[A-Z]/) { rest = substr(name, 4); print "-D" name "=setCharonHost" rest; print "-D" tolower(substr(rest, 1, 1)) substr(rest, 2) "=charonHost" rest }
              else if (name ~ /^is[A-Z]/) { rest = substr(name, 3); print "-D" name "=isCharonHost" rest; print "-D" tolower(substr(rest, 1, 1)) substr(rest, 2) "=charonHost" rest }
              else print "-D" name "=charonHost" toupper(substr(name, 1, 1)) substr(name, 2) }' | sort -u
}
