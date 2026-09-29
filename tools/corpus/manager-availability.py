# own ios AvailabilityAttr -> enclosing category/interface -> none; never a neighbour's
import re, sys
nodes = []  # dicts: depth, kind, name, ios, macos_unavail, parent
stack = []
for l in open(sys.argv[1]).read().splitlines():
    m = re.match(r'^([| `]*)[|`]-(\w+)', l)
    if not m:
        continue
    depth = len(m.group(1)) // 2
    while stack and stack[-1]['depth'] >= depth:
        stack.pop()
    kind = m.group(2)
    parent = stack[-1] if stack else None
    if kind == 'AvailabilityAttr' and parent is not None:
        a = re.search(r' ios (\d+(?:\.\d+)*)', l)
        if a and parent['ios'] is None:
            parent['ios'] = a.group(1)
        if re.search(r' macos .*Unavailable', l):
            parent['macos_unavail'] = True
        continue
    name = None
    if kind == 'ObjCMethodDecl':
        n = re.search(r' ([-+]) ([\w:]+)', l); name = n.group(1) + n.group(2) if n else None
    elif kind in ('ObjCPropertyDecl', 'ObjCInterfaceDecl', 'ObjCCategoryDecl'):
        n = re.search(r"(?:col|line):\d+(?::\d+)?> (?:[\w ]*? )?(\w+)(?: '|$)", l); name = n.group(1) if n else None
    node = dict(depth=depth, kind=kind, name=name, ios=None, macos_unavail=False, parent=parent)
    nodes.append(node); stack.append(node)
for n in nodes:
    if n['kind'] not in ('ObjCMethodDecl', 'ObjCPropertyDecl'):
        continue
    ios, src, p = n['ios'], 'member', n['parent']
    while ios is None and p is not None:
        if p['kind'] in ('ObjCCategoryDecl', 'ObjCInterfaceDecl') and p['ios']:
            ios, src = p['ios'], 'category' if p['kind'] == 'ObjCCategoryDecl' else 'class'
        p = p['parent']
    print('\t'.join([n['name'] or '?', ios or 'none', src if ios else '-', 'macos-unavailable' if n['macos_unavail'] else '']))
