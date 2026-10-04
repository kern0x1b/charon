#!/usr/bin/env python3
"""
Does a member a superclass implements read missing while the built image or the release carries it?

classify_method and classify_property looked for a selector, or a property's accessors, in the OWNER
class's own selector sets. `load_built_inventories` records a `superclass` edge per class, so the
chain was there to walk and nothing walked it: a member the superclass implements read `missing` for
the subclass.

The measurement this file is built on is the six 6.1.3 built libraries' own inventory
(`xmake l tools/corpus/objc-inventory.lua <gate>/libUIKitBackports.dylib armv7`), which holds

    UIKeyCommand   super UICommand
    UICommand      super UIMenuElement
    UIMenuElement  super <none>

`UIKeyCommand` declares none of `-action`, `-title` or `+commandWithTitle:image:action:propertyList:`
and all ten UIKeyCommand rows of the surface read missing; `UICommand` declares all three. The names
below are that hierarchy with the words shortened, because a selftest that carried Apple's names
would read as a claim about Apple's classes rather than about this reader.

The rule, in one line: an ancestor answers only where it is measured -- in the built image, or in the
release's own cache -- and the reason says which of the two proved the row. Everything else in the file
is an edge of that.

    python3 selftest-api-ledger-chain.py

Exit 0 when every check holds. The inventories are written here, so nothing on this machine can
make it pass or fail.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.realpath(__file__))
LEDGER = os.path.join(HERE, "api-ledger.py")
SOURCE = open(LEDGER, encoding="utf-8").read()
spec = importlib.util.spec_from_file_location("api_ledger", LEDGER)
ledger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ledger)

CHECKS = []
failures = []


def check(what, got, want):
    CHECKS.append(what)
    if got == want:
        print("ok   %s" % what)
    else:
        print("FAIL %s\n       got  %r\n       want %r" % (what, got, want))
        failures.append(what)


def fresh_code(name):
    """The code object the file on disk compiles to for the top-level def `name`, or None."""
    code = (lambda: 0).__code__
    for const in compile(SOURCE, LEDGER, "exec").co_consts:
        if isinstance(const, type(code)) and const.co_name == name:
            return const
    return None


# The loaded module is the file on disk, and this is here because it was not once. The interpreter's
# bytecode cache is keyed by the source's mtime in whole seconds and its size, and this machine's
# python3 keeps that cache outside the tree
# (`~/Library/Caches/com.apple.python/<abs path>/api-ledger.cpython-39.pyc`), so editing the file and
# putting it back inside one second leaves the OLD bytecode in place -- measured 2026-10-04, where a
# mutation and its undo one command apart made a clean api-ledger.py fail 9 of the 34 checks below and
# look like a defect in the walk. Compiling the file here and comparing the code objects catches it,
# and it is the same question as every other check here: is the code that answered the one on disk?
for name in ("classify_method", "classify_property", "_ancestors"):
    check("the loaded %s is the file on disk, not a stale bytecode cache" % name,
          getattr(ledger, name).__code__ == fresh_code(name), True)


def entry(instance=(), klass=(), library="Backports", superclass=""):
    return {"instance": set(instance), "class": set(klass), "protocols": set(),
            "superclass": superclass, "image": "", "library": library}


# The measured hierarchy, in the inventory's own spelling: a selector carries a leading `-` for an
# instance method AND for a class method (run_objc_inventory's docstring), so the class factory
# below is `-commandWithTitle:image:action:propertyList:` and not `+...`.
BUILT = {
    "KeyCommand": entry(instance=["-input", "-setInput:", "-copyWithZone:"],
                        library="UIKitBackports", superclass="Command"),
    "Command": entry(instance=["-action", "-setAction:", "-title", "-state"],
                     klass=["-commandWithTitle:image:action:propertyList:"],
                     library="UIKitBackports", superclass="MenuElement"),
    "MenuElement": entry(instance=["-title", "-image"], library="UIKitBackports"),
}
# A port class whose declared superclass is a release class: the port's libraries are loaded beside
# the device's frameworks, so what the release declares is what the port class inherits. `NSObject` is
# in the 6.1.3 cache on every real device, and nothing in the built libraries here.
RELEASE = {
    "NSObject": entry(instance=["-description"], klass=["-new"]),
    "Responder": entry(instance=["-becomeFirstResponder"], superclass="NSObject"),
    "Table": entry(instance=["-reloadData"], superclass="Responder"),
}
PROTOCOLS_BUILT = {"Shape": entry(instance=["-area"], library="UIKitBackports")}
PROTOCOLS_RELEASE = {}


def method(api, built=None, release=None, decided=None):
    return ledger.classify_method(api, BUILT if built is None else built,
                                  RELEASE if release is None else release,
                                  PROTOCOLS_BUILT, PROTOCOLS_RELEASE, decided=decided)


def prop(api, built=None, release=None, getter=None, decided=None):
    return ledger.classify_property(api, BUILT if built is None else built,
                                    RELEASE if release is None else release,
                                    PROTOCOLS_BUILT, PROTOCOLS_RELEASE, getter=getter, decided=decided)


# The row the finding is about, one per kind: an instance property, a class method and an instance
# method, all three answered above the owner.
check("a property a superclass declares reads implemented",
      prop("KeyCommand.action")[0], "implemented")
check("and the reason names the ancestor and the library that carries it",
      prop("KeyCommand.action")[1], "built: UIKitBackports (inherited from Command)")

check("a class method a superclass declares reads implemented",
      method("+[KeyCommand commandWithTitle:image:action:propertyList:]")[0], "implemented")
check("with the same reason", method("+[KeyCommand commandWithTitle:image:action:propertyList:]")[1],
      "built: UIKitBackports (inherited from Command)")

check("an instance method a superclass declares reads implemented",
      method("-[KeyCommand state]")[0], "implemented")

# Two steps up, so the walk is a walk and not a single step: `image` is in `MenuElement` alone, one
# step past `Command`, and the reason names the ancestor that answers rather than the one above the
# owner.
check("the nearest ancestor that answers is the one named",
      prop("KeyCommand.title")[1], "built: UIKitBackports (inherited from Command)")
two_steps = {
    "KeyCommand": entry(instance=["-input"], library="UIKitBackports", superclass="Command"),
    "Command": entry(instance=["-title"], library="UIKitBackports", superclass="MenuElement"),
    "MenuElement": entry(instance=["-image"], library="UIKitBackports"),
}
check("a member two steps up the chain is found",
      prop("KeyCommand.image", built=two_steps)[1],
      "built: UIKitBackports (inherited from MenuElement)")

# The release's own chain, for a class only the release carries.
check("a release class inherits from the release above it",
      method("-[Table becomeFirstResponder]")[0], "implemented")
check("and the reason says the release proved it",
      method("-[Table becomeFirstResponder]")[1],
      "release-native: 6.1.3 dyld cache (inherited from Responder)")

# The mixed chain, which is the port's own shape: the owner is the port's, and the ancestor that
# answers is a release class.
mixed = {"Port": entry(instance=["-own"], library="UIKitBackports", superclass="Table")}
check("a port class inherits from a release class it declares as its superclass",
      method("-[Port reloadData]", built=mixed, release=RELEASE)[0], "implemented")
check("and the reason names the release, not the port",
      method("-[Port reloadData]", built=mixed, release=RELEASE)[1],
      "release-native: 6.1.3 dyld cache (inherited from Table)")

# A property read through a class selector, inherited: the class set is searched all the way up, or
# a `@property (class, readonly)` on a subclass of the class that declares it reads missing.
classprop = {"Panel": entry(instance=["-own"], library="UIKitBackports", superclass="Command"),
             "Command": entry(klass=["-shared"], library="UIKitBackports")}
check("a class property a superclass declares reads implemented",
      prop("Panel.shared", built=classprop)[0], "implemented")
check("and says it is read through the class accessor",
      prop("Panel.shared", built=classprop)[1],
      "built: UIKitBackports (inherited from Command) (a class property: read through -shared)")

# The declared getter still wins over the derived one on the way up: the accessor is what the chain
# is asked for, not the property's own name.
declared = {"Thing": entry(instance=["-own"], library="UIKitBackports", superclass="Base"),
            "Base": entry(instance=["-isEnabled"], library="UIKitBackports")}
check("an ancestor's declared getter answers the row",
      prop("Thing.enabled", built=declared, getter="isEnabled")[0], "implemented")
check("while the derived accessor the same chain does not hold still reads missing",
      prop("Thing.enabled", built=declared)[0], "missing")

# A name in both inventories. The port's libraries extend NSObject with categories, so the built entry
# holds the port's selectors and no others, and the release's NSObject holds the rest: `-description`
# here is the device's, and the reason must say so rather than name the library that happened to add a
# category to NSObject first.
both = {"KeyCommand": entry(instance=["-input"], library="UIKitBackports", superclass="NSObject"),
        "NSObject": entry(instance=["-conversationContext"], library="HomeKit")}
RELEASE_BOTH = dict(RELEASE)
RELEASE_BOTH["NSObject"] = entry(instance=["-description"], klass=["-new"])
check("a member only the release's copy of a shared name carries reads implemented",
      method("-[KeyCommand description]", built=both, release=RELEASE_BOTH)[0], "implemented")
check("and the reason names the release, not the library that extended NSObject",
      method("-[KeyCommand description]", built=both, release=RELEASE_BOTH)[1],
      "release-native: 6.1.3 dyld cache (inherited from NSObject)")
check("while a member only the port's copy carries reads implemented from the built image",
      method("-[KeyCommand conversationContext]", built=both, release=RELEASE_BOTH)[0], "implemented")
check("with the library that carries that selector",
      method("-[KeyCommand conversationContext]", built=both, release=RELEASE_BOTH)[1],
      "built: HomeKit (inherited from NSObject)")

# What the walk must NOT answer. A member no measured ancestor holds, with the chain measured all the
# way to its root: `MenuElement` is a root in these inventories, so this is an absence and not a
# refusal.
check("a member no measured ancestor declares still reads missing",
      method("-[KeyCommand makeOne]")[0], "missing")
check("with the reason it always had",
      method("-[KeyCommand makeOne]")[1], "KeyCommand is there, selector makeOne is not")

# A chain that reaches an ancestor in neither inventory stops there and says so, rather than reading
# as an absence: the walk cannot answer for a class nothing here measures.
unmeasured = {"KeyCommand": entry(instance=["-input"], library="UIKitBackports",
                                  superclass="Absent")}
check("a chain that reaches an unmeasured class reads missing",
      method("-[KeyCommand title]", built=unmeasured)[0], "missing")
check("and the reason names where the walk stopped",
      method("-[KeyCommand title]", built=unmeasured)[1],
      "KeyCommand is there, selector title is not, and the superclass Absent above it is in neither "
      "the built libraries nor the 6.1.3 cache")
check("the same for a property row",
      prop("KeyCommand.title", built=unmeasured)[1],
      "KeyCommand is there, neither -title nor -setTitle: is an instance or a class selector, and the "
      "superclass Absent above it is in neither the built libraries nor the 6.1.3 cache")

# A protocol owner is not walked: a protocol has no superclass, and this is why the walk is inside
# `if built or released` in both functions. The owner here is in neither class inventory.
check("a protocol owner is not answered by inheritance",
      method("-[Shape inherited]", built={"Other": entry(superclass="Command")})[0], "missing")
check("and keeps the reason it always had, with no stop clause for a chain it does not have",
      method("-[Shape inherited]", built={"Other": entry(superclass="Command")})[1],
      "Shape is there, selector inherited is not")
check("a property of a protocol likewise", prop("Shape.inherited", built={"Other": BUILT["Command"]})[0],
      "missing")

# A row a registry has decided keeps its decision, as `+new` already required: the chain must not
# answer around the guard the way an unguarded walk would. Measured over the whole surface, that guard
# is 13 rows -- the ten `-[VN*Request init]` whose registry row says Apple's header marks the
# initialiser unavailable, the two `UITextInputTraits` properties the port answers on NSObject under a
# row of its own, and `+[NSURLSessionStreamTask new]`.
DECIDED = {"+[KeyCommand new]"}
check("the chain does not answer a row a registry decided",
      method("+[KeyCommand new]", decided=DECIDED)[0], "missing")
check("while the same row reads implemented with no decision against it",
      method("+[KeyCommand new]")[0], "implemented")
check("and a decided property row keeps its decision too",
      prop("KeyCommand.action", decided={"KeyCommand.action"})[0], "missing")
check("while the same property reads implemented with no decision against it",
      prop("KeyCommand.action")[0], "implemented")

# The mutations. Each drops one thing the walk needs, and each is a way this reader can be wrong
# with every check above still green.

# The edge itself: no superclass recorded on the owner, which is what `load_built_inventories` leaves
# for a class two libraries both extend.
cut = {"KeyCommand": entry(instance=["-input"], library="UIKitBackports")}
check("dropping the superclass edge puts the row back to missing",
      prop("KeyCommand.action", built=cut)[0], "missing")
check("with the reason it always had",
      prop("KeyCommand.action", built=cut)[1],
      "KeyCommand is there, neither -action nor -setAction: is an instance or a class selector")
check("and the same for the class method row",
      method("+[KeyCommand commandWithTitle:image:action:propertyList:]", built=cut)[0], "missing")

# The intermediate edge: the owner still names a superclass, and the class it names is in neither
# inventory. The chain stops there, which is a refusal to answer, not a credit.
check("a chain through an unmeasured class is not answered past it",
      method("-[KeyCommand title]", built={"KeyCommand": cut["KeyCommand"]},
             release={})[0], "missing")

# The step from the built image into the release cache. Without it a port class never inherits from
# the device's frameworks, and every `:[Port ...]` row whose answer is NSObject's reads missing.
nostop = {"Port": entry(instance=["-own"], library="UIKitBackports", superclass="Table")}
check("the walk does reach a release class from the built image",
      method("-[Port becomeFirstResponder]", built=nostop, release=RELEASE)[0], "implemented")

# A chain that loops back on itself terminates instead of hanging the run.
loop = {"Ping": entry(superclass="Pong"), "Pong": entry(superclass="Ping")}
check("a chain that loops back on itself still answers",
      ledger._ancestors("Ping", loop, {})[1], "")
check("and answers nothing rather than looping", method("-[Ping go]", built=loop)[0], "missing")

# The call sites, a wiring check against main's source text rather than a run: build() needs a gate,
# a dyld cache and an SDK to reach those lines. Both functions must still be handed the built and the
# release inventories, or the walk has nothing to walk. It is a wiring check and says so.
source = SOURCE
body = source[source.index("def main("):]
for name in ("classify_method", "classify_property"):
    call = re.search(name + r"\(([^)]*)\)", body)
    check("main() hands %s both class inventories and the decided rows" % name,
          sorted(part.strip().split("=")[0] for part in call.group(1).split(",") if part.strip()),
          ["api", "built_classes", "built_protocols", "decided", "release_classes", "release_protocols"]
          if name == "classify_method" else
          ["api", "built_classes", "built_protocols", "decided", "getter", "release_classes",
           "release_protocols"])

print("\n%d checks, %d failures" % (len(CHECKS), len(failures)))
sys.exit(1 if failures else 0)
