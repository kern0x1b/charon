"""The mutant: the module with the one call removed, asked of the case's own fixture."""
import os
import shutil

here = os.path.abspath(".")
modules = os.path.join(here, "modules")
mutant = os.path.join(here, ".agent-work", "runs", "mutant-modules")
shutil.rmtree(mutant, ignore_errors=True)
shutil.copytree(modules, mutant)
backports = os.path.join(mutant, "apple", "backports.lua")
s = open(backports).read()
old = """            local declared = entry.kind == "protocol" or
                (owner and listed[owner] and listed[owner].kind == "protocol" and
                 protocol_declared(root, owner, inventory, sdkdir))"""
new = """            local declared = entry.kind == "protocol" or
                (owner and listed[owner] and listed[owner].kind == "protocol")"""
assert old in s, "the call is not where the case measured it"
open(backports, "w").write(s.replace(old, new, 1))
print("mutant written without the call")
