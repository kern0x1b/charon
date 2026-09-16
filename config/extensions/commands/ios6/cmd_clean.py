import json
import os
import shutil
import subprocess

from conan.api.model import ListPattern
from conan.api.output import ConanOutput
from conan.cli.command import conan_command
from conan.errors import ConanException


def _tree_size(path):
    total = 0
    for folder, directories, names in os.walk(path):
        directories[:] = [name for name in directories if name != ".git"]
        for name in names:
            candidate = os.path.join(folder, name)
            if not os.path.islink(candidate):
                total += os.lstat(candidate).st_size
    return total


def _megabytes(size):
    return f"{size / (1024 * 1024):.0f} MB"


def _users_of(folder):
    listing = subprocess.run(["ps", "-Ao", "pid=,pgid=,args="], capture_output=True, text=True,
                             errors="replace").stdout
    mine = (os.getpid(), os.getpgrp())
    found = []
    for line in listing.splitlines():
        fields = line.split(None, 2)
        if len(fields) < 3 or folder not in fields[2]:
            continue
        if int(fields[0]) in mine or int(fields[1]) in mine:
            continue
        found.append(fields[2].strip())
    return found


def _locked_references(path):
    with open(path) as lock:
        content = json.load(lock)
    references = set()
    for section in ("requires", "build_requires", "python_requires"):
        for entry in content.get(section) or []:
            references.add(entry.split("#")[0])
    return references


@conan_command(group="ios6")
def clean(conan_api, parser, *args):
    """
    Report what builds leave behind - the port's build trees and the cache's source, build and
    download folders - and remove it when asked.
    """
    parser.add_argument("path", nargs="?", default=".",
                        help="the port's checkout; default: the current folder")
    parser.add_argument("--build-root", default="build",
                        help="where this port's layout puts its build trees, relative to the "
                             "checkout or absolute; default: build")
    parser.add_argument("--force", action="store_true",
                        help="delete; without it nothing is removed and the sizes are only reported")
    parser.add_argument("--cache", action="store_true",
                        help="also the source, build and download folders inside the Conan cache")
    parser.add_argument("--unused", metavar="TIME",
                        help="also cached packages nobody has used for this long, e.g. 30d; only the "
                             "references this port's conan.lock names, because the cache is shared")
    args = parser.parse_args(*args)

    out = ConanOutput()
    checkout = os.path.abspath(args.path)
    if not os.path.isfile(os.path.join(checkout, "conanfile.py")):
        raise ConanException(f"{checkout} holds no conanfile.py; point the command at a port's checkout")
    build_root = args.build_root if os.path.isabs(args.build_root) else os.path.join(checkout, args.build_root)
    build_root = os.path.normpath(build_root)
    if os.path.commonpath([checkout, build_root]) != checkout:
        raise ConanException(f"{build_root} is outside {checkout}; this command removes a port's own builds")

    removed = 0
    if os.path.isdir(build_root):
        busy = _users_of(build_root)
        if busy:
            raise ConanException(f"{build_root} is in use by:\n  " + "\n  ".join(busy) +
                                 "\nWait for that build: removing its tree leaves a corrupt one behind.")
        for name in sorted(os.listdir(build_root)):
            tree = os.path.join(build_root, name)
            if not os.path.isdir(tree):
                continue
            size = _tree_size(tree)
            removed += size
            out.info(f"build tree {tree}: {_megabytes(size)}")
            if args.force:
                shutil.rmtree(tree)
    else:
        out.info(f"no build trees under {build_root}")

    if args.cache:
        package_list = conan_api.list.select(ListPattern("*", rrev="*", prev="*"))
        out.info("cache: the source, build and download folders of every package in this home")
        if args.force:
            conan_api.cache.clean(package_list)

    if args.unused:
        lockfile = os.path.join(checkout, "conan.lock")
        if not os.path.isfile(lockfile):
            raise ConanException(f"{lockfile} is missing, and it is what says which references belong to "
                                 "this port; without it an unused-package sweep would reach into every "
                                 "other port sharing this cache")
        references, recipes, packages = _locked_references(lockfile), [], []
        for reference in sorted(references):
            selected = conan_api.list.select(ListPattern(reference, rrev="*", prev="*"), lru=args.unused)
            for ref, contents in selected.items():
                if contents:
                    packages.extend(contents)
                else:
                    recipes.append(ref)
        out.info(f"cache: {len(recipes)} recipe revisions and {len(packages)} binaries "
                 f"of this port's own references unused for {args.unused}")
        if args.force:
            if packages:
                conan_api.remove.packages(packages)
            if recipes:
                conan_api.remove.recipes(recipes)

    out.info(f"build trees: {_megabytes(removed)} {'removed' if args.force else 'would be removed'}")
    if not args.force:
        out.info("nothing was deleted; add --force")
