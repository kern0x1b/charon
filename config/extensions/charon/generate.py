"""Write what a port declared as the files the tools underneath expect.

Every function here returns text and touches no disk, so what it produces can be
read and compared in a test rather than inspected after a build. What it writes
goes into the build tree, never into the port: a file that can be generated is
not kept, and the one place to look for what built something is the tree it was
built in.
"""
import spec

LANGUAGES = {".c": "C", ".m": "OBJC", ".mm": "OBJCXX", ".cpp": "CXX", ".cc": "CXX", ".swift": "Swift"}
CMAKE_MINIMUM = "3.24"
GENERATED = "# Written by Charon from charon.toml. Edits here are lost on the next build."


class GenerationError(Exception):
    pass


def _quoted(value):
    return '"{}"'.format(value)


def profile(declared, includes=None):
    target = declared.section("target")
    for required in ("arch", "os", "os-version"):
        if required not in target:
            raise GenerationError("[target] declares no {}, and it is what says what this port builds for".format(
                required))
    lines = []
    if includes:
        lines += ["include({})".format(name) for name in includes] + [""]
    lines.append("[settings]")
    lines.append("os={}".format(target["os"]))
    lines.append("os.version={}".format(target["os-version"]))
    if "sdk" in target:
        lines.append("os.sdk={}".format(target["sdk"]))
    lines.append("arch={}".format(target["arch"]))
    lines.append("build_type={}".format(target.get("build-type", "Release")))
    if "cppstd" in target:
        lines.append("compiler.cppstd={}".format(target["cppstd"]))

    tuning = []
    if "cpu" in target:
        tuning += ["-mcpu={}".format(target["cpu"]), "-mtune={}".format(target["cpu"])]
    if "fpu" in target:
        tuning.append("-mfpu={}".format(target["fpu"]))
    if tuning:
        rendered = ", ".join(_quoted(flag) for flag in tuning)
        lines += ["", "[conf]",
                  "tools.build:cflags=[{}]".format(rendered),
                  "tools.build:cxxflags=[{}]".format(rendered)]
    return "\n".join(lines) + "\n"


def _languages(sources):
    found = []
    for pattern in sources:
        suffix = pattern[pattern.rfind("."):] if "." in pattern else ""
        language = LANGUAGES.get(suffix)
        if language is None:
            raise GenerationError("{} is a source Charon cannot name a language for".format(pattern))
        if language not in found:
            found.append(language)
    return found


def _sources(target):
    sources = target.get("sources")
    if not sources:
        raise GenerationError("{} declares no sources and no cmake= to use instead".format(target["name"]))
    return sources


def _options(target, key, prefix=""):
    values = target.get(key, [])
    return ["{}{}".format(prefix, value) for value in values]


def _library_block(target, kind):
    name = target["name"]
    sources = _sources(target)
    if kind == "application":
        lines = ["add_executable({}".format(name), "    {})".format("\n    ".join(sources))]
    else:
        lines = ["add_library({} {}".format(name, "STATIC" if kind == "static-library" else "SHARED"),
                 "    {})".format("\n    ".join(sources))]

    properties = ["PREFIX \"\""] if kind == "device-library" else []
    if kind == "device-library":
        install = target.get("install")
        if not install:
            raise GenerationError("{} declares no install path, and a device library has to say where it "
                                  "belongs on the phone".format(name))
        properties += ["INSTALL_NAME_DIR {}".format(install), "BUILD_WITH_INSTALL_NAME_DIR ON"]
    if "suffix" in target:
        properties.append("SUFFIX {}".format(_quoted(target["suffix"])))
    if "standard" in target:
        properties += ["CXX_STANDARD {}".format(target["standard"]), "CXX_STANDARD_REQUIRED ON", "CXX_EXTENSIONS OFF"]
    if properties:
        lines.append("set_target_properties({} PROPERTIES {})".format(name, " ".join(properties)))

    for key, command in (("include", "target_include_directories({} PRIVATE"),
                         ("include-system", "target_include_directories({} SYSTEM PRIVATE")):
        folders = target.get(key)
        if folders:
            lines.append(command.format(name) + "\n    {})".format("\n    ".join(folders)))

    options = _options(target, "options")
    if options:
        lines.append("target_compile_options({} PRIVATE\n    {})".format(name, "\n    ".join(options)))
    link_options = _options(target, "link-options")
    if link_options:
        lines.append("target_link_options({} PRIVATE\n    {})".format(name, "\n    ".join(link_options)))

    linked = [_quoted("-framework {}".format(framework)) for framework in target.get("frameworks", [])]
    linked += list(target.get("libraries", []))
    if linked:
        lines.append("target_link_libraries({} PRIVATE\n    {})".format(name, "\n    ".join(linked)))
    return lines


def _install_block(target, kind):
    name = target["name"]
    if kind == "static-library":
        return []
    if kind == "application":
        lines = ["install(TARGETS {} RUNTIME DESTINATION .)".format(name)]
        files = [resource for resource in target.get("resources", []) if isinstance(resource, str)]
        if files:
            lines.append("install(FILES {} DESTINATION .)".format(" ".join(files)))
        return lines
    lines = []
    install = target["install"].lstrip("/")
    lines.append("install(TARGETS {} LIBRARY DESTINATION {})".format(name, install))
    for resource in target.get("resources", []):
        if isinstance(resource, str):
            lines.append("install(FILES {} DESTINATION {})".format(resource, install))
            continue
        source, destination = resource["from"], resource["as"]
        if source.endswith("/"):
            lines.append("install(DIRECTORY {} DESTINATION {})".format(
                source, install if destination == "." else destination.lstrip("/")))
        elif destination.startswith("/"):
            folder, _, renamed = destination.rpartition("/")
            lines.append("install(FILES {} DESTINATION {} RENAME {})".format(source, folder.lstrip("/"), renamed))
        else:
            lines.append("install(FILES {} DESTINATION {} RENAME {})".format(source, install, destination))
    return lines


def cmake_project(declared, kind, project):
    targets = [target for target in declared.targets(kind) if declared.generates(target)]
    if not targets:
        return None
    languages = []
    for target in targets:
        for language in _languages(_sources(target)):
            if language not in languages:
                languages.append(language)

    lines = [GENERATED,
             "cmake_minimum_required(VERSION {})".format(CMAKE_MINIMUM),
             "project({} {})".format(project, " ".join(languages)),
             ""]
    packages = []
    for target in targets:
        for package in target.get("packages", []):
            if package not in packages:
                packages.append(package)
    for package in packages:
        lines.append("find_package({} REQUIRED CONFIG)".format(package))
    if lines[-1] != "":
        lines.append("")
    for target in targets:
        lines += _library_block(target, kind) + [""]
    for target in targets:
        lines += _install_block(target, kind)
    return "\n".join(lines).rstrip("\n") + "\n"


def written(declared):
    produced = {}
    profiles = declared.using("profile")
    if profiles is None:
        produced["profile"] = profile(declared, includes=declared.get("target", "include-profiles", []))
    for kind, project in (("static-library", "port-static"), ("device-library", "port-device"),
                          ("application", "port-application")):
        text = cmake_project(declared, kind, project)
        if text is not None:
            produced["{}/CMakeLists.txt".format(kind)] = text
    if not produced:
        raise GenerationError("{} declares nothing Charon can generate".format(declared.root / spec.MANIFEST))
    return produced
