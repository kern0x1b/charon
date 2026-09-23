"""Certify a list of symbols/selectors against BOTH the origin/main registry export and the
origin/main source tree. A row is only real work when the registry does not carry it AND no
definition exists in the tree. Written once, used for every list -- the previous handoff file was
built by an ad-hoc query that forgot the registry filter entirely.

status() key expansion is kept in sync BY HAND with crash-demand.py's status_one(): both look up
a dotted `Owner.property` api under its method-form registry keys (getter/setter/is-getter, both
+/-), because the registry writes some rows only in method form. Measured divergence, 2026-09-22:
before this file grew the same expansion, `UIActivity.activityCategory` (registry only carries
`+[UIActivity activityCategory]`) read as "нет строки" here while crash-demand.py's status_one()
found it -- this tool's in_tree() fallback happened to catch it too, so the two tools agreed on
the final verdict that day, but only by accident of a second check existing. Do not rely on the
tree fallback to keep masking a future case where crash-demand.py's registry-side match and this
tool's registry-side match disagree and the tree can't decide either way (a synthesized property,
no @dynamic, no real accessor body -- in_tree() returns False, status_one() would still find the
method-form registry row). If status_one()'s key list changes, mirror it here."""
import os, re, subprocess, sys, csv
EXP=os.environ.get("CHARON_REGISTRY_TSV", "/private/tmp/bcorpus-scratch/carried-registry-fresh.tsv")
_HERE=os.path.dirname(os.path.abspath(__file__))
_T_CANDIDATES=[p for p in [
    os.environ.get("CHARON_TREE_DIR"),                                                # explicit override survives any future worktree move
    os.path.join(os.path.dirname(_HERE), "packages", "a", "apple-backports"),          # script lives in the repo (tools/)
    os.path.join(os.path.expanduser("~"), "Git", "projects", "ios", "charon",
                  ".agent-work", "worktrees", "bcorpus", "packages", "a", "apple-backports"),  # script lives in the scratchpad
] if p]
T=next((p for p in _T_CANDIDATES if os.path.isdir(p)), None)
if T is None:
    sys.exit("verify.py: no tree directory found (looked in %s). Set CHARON_TREE_DIR to the "
              "current worktree's packages/a/apple-backports -- without it in_tree() silently "
              "scans an empty blob and every check() call reports false positives (this is exactly "
              "how the GCDevice row came back after the worktree moved earlier this session)."
              % ", ".join(_T_CANDIDATES))
reg={}
for l in open(EXP):
    p=l.rstrip("\n").split("\t")
    if len(p)>=3 and p[0]!="framework": reg[p[1]]=p[2]
BLOB=subprocess.run(["bash","-c",f"cat $(find {T} -name '*.m' -o -name '*.mm' -o -name '*.h') 2>/dev/null"],
                    capture_output=True,text=True).stdout
def status(api):
    a=re.sub(r' \(\+\d+ owners\)$','',api)
    cands=[a, a+"()", a.lstrip("_"), a.lstrip("_")+"()", a.replace("_OBJC_CLASS_$_","")]
    # A dotted property api may be carried only under its method form (crash-demand.py's
    # status_one() does this same expansion; see the module docstring for why both need it).
    if "." in a and not a.startswith(("-", "+", "_")):
        o, name = a.split(".", 1)
        up = name[0].upper() + name[1:]
        cands += ["-[%s %s]" % (o, name), "-[%s set%s:]" % (o, up), "-[%s is%s]" % (o, up),
                  "+[%s %s]" % (o, name), "+[%s set%s:]" % (o, up)]
    for k in cands:
        if k in reg: return reg[k]
    return "нет строки"
# Bodies of every @implementation in the tree, keyed by class (categories merged into the class).
# A flat blob cannot tell WHICH class defines a selector: `- (BOOL)accessibilityIgnoresInvertColors`
# exists on UIListContentProperties and made UIView.accessibilityIgnoresInvertColors look carried.
IMPLS={}
for _m in re.finditer(r'@implementation\s+(\w+)([^\n]*)\n(.*?)(?=^@end)', BLOB, re.S|re.M):
    IMPLS.setdefault(_m.group(1), []).append(_m.group(3))
def _body(cls):
    return "\n".join(IMPLS.get(cls, []))
PROTOCOLS=set(); ADOPTERS={}
try:
    import json as _j
    _k=_j.load(open("/private/tmp/bcorpus-scratch/reg-kinds.json"))
    PROTOCOLS={a for a,kk in _k.items() if kk=="protocol"}
    _store=_j.load(open("/private/tmp/bcorpus-scratch/tools/store.json"))
    _imported=set()
    for _a,_d in _store["apps"].items():
        _imported |= {r["name"] for r in _d["demand"] if r.get("kind")=="class"}
    # No guessing which classes adopt a protocol: use the direct evidence we already have --
    # the concrete classes the corpus apps import. A protocol member is carried when one of
    # THOSE classes defines it in the tree.
    ADOPTERS={_p:_imported for _p in PROTOCOLS}
except Exception as _e:
    pass

def in_tree(api, kind=None, owner=None):
    a=re.sub(r' \(\+\d+ owners\)$','',api)
    if a.startswith("_OBJC_CLASS_$_") or kind=="class":
        c=a.replace("_OBJC_CLASS_$_","")
        return c in IMPLS or f"@interface {c}" in BLOB
    m=re.match(r'[+-]\[(\w+) ([\w:]+)\]$',a)
    if m: own,sel=m.group(1),m.group(2)
    elif "." in a and not a.startswith("_"): own,sel=a.split(".",1)
    else: own,sel=None,a.lstrip("_")
    own=owner or own
    if own is not None:
        # A PROTOCOL owner has no @implementation of its own: the member is provided by the concrete
        # classes that adopt it. Widen the search to every class the CALLING apps actually import.
        # (GCDevice is a protocol; GCController implements vendorName and every caller imports it.)
        if own not in IMPLS and own in PROTOCOLS:
            cands=[c for c in IMPLS if c in ADOPTERS.get(own,set())]
            B2="\n".join(_body(c) for c in cands) if cands else ""
        elif own not in IMPLS:
            return False
        else:
            B2=_body(own)
    else:
        B2=BLOB                       # a bare C symbol has no owning class
    if ":" in sel:
        parts=[p for p in sel.split(":") if p]
        pat=r'[-+]\s*\([^)]*\)\s*'+re.escape(parts[0])+r'\s*:'
        for q in parts[1:]: pat+=r'[^;{]{0,300}?\b'+re.escape(q)+r'\s*:'
        return bool(re.search(pat,B2))
    up=sel[0].upper()+sel[1:]
    if re.search(r'[-+]\s*\([^)]*\)\s*'+re.escape(sel)+r'\s*(?:\{|;|$)',B2,re.M): return True
    if re.search(r'[-+]\s*\([^)]*\)\s*set'+re.escape(up)+r'\s*:',B2): return True
    # `@dynamic name` is an explicit statement that there is NO implementation here -- it is negative
    # evidence, not positive. A bare `@property` is not proof either: the compiler synthesises an
    # accessor that holds a value nobody honours, which is exactly how the project's own facts file
    # (facts/UIKit/UIGraphicsRendererFormatPreferred.md) records preferredRange "answering YES".
    # Only a real body or an explicit @synthesize counts.
    if re.search(r'@dynamic\b[^;\n]*\b'+re.escape(sel)+r'\b',B2): return False
    if re.search(r'@synthesize\b[^;\n]*\b'+re.escape(sel)+r'\b',B2): return True
    if own is None and re.search(r'^[A-Za-z_][\w \t\*]*\b'+re.escape(sel)+r'\s*(=|\()',BLOB,re.M): return True
    return False

def check(name, rows):
    real=[]; carried=[]; intree=[]
    for api,kind,extra in rows:
        st=status(api)
        if st in ("implemented","inert"): carried.append((api,st,extra)); continue
        # An explicit `absent`/`ignored` row is a DECISION by the owner of the class, with a reason and a
        # facts file. A sighting in the tree does not overturn it -- what is in the tree may be a
        # declaration the decision itself describes. Only a row the registry never ruled on is settled
        # by the tree.
        if st in ("absent","ignored"): real.append((api,st,extra)); continue
        if in_tree(api,kind): intree.append((api,st,extra)); continue
        real.append((api,st,extra))
    print(f"\n### {name}: заявлено {len(rows)} -> НАСТОЯЩИХ {len(real)}")
    if carried: print(f"   ЛОЖНЫЕ, несёт реестр ({len(carried)}):");  [print(f"      {s:12} {a}") for a,s,_ in carried]
    if intree:  print(f"   ЛОЖНЫЕ, есть в дереве ({len(intree)}):");  [print(f"      {s:12} {a}") for a,s,_ in intree]
    return real
