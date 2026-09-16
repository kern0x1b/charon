"""Write what a port declared as the files the tools underneath expect.

Every function here returns text and touches no disk, so what it produces can be
read and compared in a test rather than inspected after a build. What it writes
goes into the build tree, never into the port: a file that can be generated is
not kept, and the one place to look for what built something is the tree it was
built in.

A generated project is configured from the build tree and not from the port, so
CMAKE_CURRENT_SOURCE_DIR is the folder Charon wrote into. Every path a
declaration names is therefore written against CHARON_PORT, which the build
passes; a value that already starts at the root, at a cmake variable or at a
flag is left exactly as declared.
"""
import spec

LANGUAGES = {".c": "C", ".m": "OBJC", ".mm": "OBJCXX", ".cpp": "CXX", ".cc": "CXX", ".swift": "Swift"}
CMAKE_MINIMUM = "3.24"
GENERATED = "# Written by Charon from charon.toml. Edits here are lost on the next build."
PORT = "${CHARON_PORT}"
REQUIRES_PORT = ('if (NOT CHARON_PORT)\n'
                 '    message(FATAL_ERROR\n'
                 '        "CHARON_PORT names the folder charon.toml lives in, and every path below is written '
                 'against it; the build passes it")\n'
                 'endif ()')


class GenerationError(Exception):
    pass


def _quoted(value):
    return '"{}"'.format(value)


def _path(value):
    text = str(value)
    if text[:1] in ("/", "$", "-"):
        return text
    return "{}/{}".format(PORT, text)


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


def _source_properties(target):
    declared = target.get("source-include") or {}
    lines = []
    for source, folders in declared.items():
        wanted = folders if isinstance(folders, list) else [folders]
        lines.append('set_source_files_properties({} PROPERTIES INCLUDE_DIRECTORIES "{}")'.format(
            _path(source), ";".join(_path(folder) for folder in wanted)))
    return lines


def _library_block(target, kind):
    name = target["name"]
    sources = [_path(source) for source in _sources(target)]
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
            lines.append(command.format(name) + "\n    {})".format(
                "\n    ".join(_path(folder) for folder in folders)))

    lines += _source_properties(target)

    options = _options(target, "options")
    if options:
        lines.append("target_compile_options({} PRIVATE\n    {})".format(name, "\n    ".join(options)))
    definitions = _options(target, "definitions")
    if definitions:
        lines.append("target_compile_definitions({} PRIVATE\n    {})".format(name, "\n    ".join(definitions)))
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
            lines.append("install(FILES {} DESTINATION .)".format(" ".join(_path(name) for name in files)))
        return lines
    lines = []
    install = target["install"].lstrip("/")
    lines.append("install(TARGETS {} LIBRARY DESTINATION {})".format(name, install))
    for resource in target.get("resources", []):
        if isinstance(resource, str):
            lines.append("install(FILES {} DESTINATION {})".format(_path(resource), install))
            continue
        source, destination = _path(resource["from"]), resource["as"]
        if resource["from"].endswith("/"):
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
             "",
             REQUIRES_PORT,
             ""]
    wanted = []
    for target in targets:
        for name in (target.get("cache") or {}):
            if name not in wanted:
                wanted.append(name)
    if wanted:
        lines += ["foreach (variable {})".format(" ".join(wanted)),
                  "    if (NOT ${variable})",
                  '        message(FATAL_ERROR "${variable} is named by the declaration and answered from the '
                  'dependency graph; configure through charon build")',
                  "    endif ()",
                  "endforeach ()",
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


BASE = "ios6-base/1.0@ios6/stable"
RECIPE_TEMPLATE = '''{generated}
from conan import ConanFile


class Port(ConanFile):
    name = {name}
    version = {version}
    description = {description}
    package_type = "application"
    generators = "VirtualBuildEnv"
    python_requires = {base}
    python_requires_extend = "ios6-base.Ios6Port"
    options = {options}
    default_options = {defaults}

    port = {port}
    declaration = {declaration}

    def requirements(self):
        for reference in {requires}:
            self.requires(reference)

    def build_requirements(self):
        for reference in {tools}:
            self.tool_requires(reference)

    def layout(self):
        self.declared_layout()

    def generate(self):
        super().generate()
        self.declared_toolchain()

    def build(self):
        self.declared_build()

    def package(self):
        self.declared_package()
'''


def _option_domains(declared):
    named = {}
    for variant in declared.section("variants").values():
        for entry in variant.get("options", []):
            option, _, value = entry.partition("=")
            named.setdefault(option, set()).add(value)
    domains, defaults = {}, {}
    for option, values in named.items():
        if not values <= {"True", "False"}:
            raise GenerationError("{} is declared with {}, and Charon only derives a domain for True and "
                                 "False; declare it in the recipe instead".format(option, ", ".join(sorted(values))))
        domains[option] = [True, False]
        defaults[option] = False
    return domains, defaults


def _references(section):
    return ["{}/{}".format(name, version) for name, version in section.items()]


def recipe(declared, port_root):
    import pprint
    described = declared.section("port")
    for required in ("name", "version"):
        if required not in described:
            raise GenerationError("[port] declares no {}, and a recipe cannot be written without it".format(required))
    domains, defaults = _option_domains(declared)
    return RECIPE_TEMPLATE.format(
        generated=GENERATED,
        name=repr(described["name"]),
        version=repr(str(described["version"])),
        description=repr(described.get("description", "")),
        base=repr(str(declared.get("use", "base", BASE))),
        options=repr(domains),
        defaults=repr(defaults),
        port=repr(str(port_root)),
        declaration=pprint.pformat(declared.content, width=110, sort_dicts=False, indent=4),
        requires=repr(_references(declared.section("requires"))),
        tools=repr(_references(declared.section("tools"))),
    )


def written(declared, required=True):
    produced = {}
    profiles = declared.using("profile")
    if profiles is None:
        produced["profile"] = profile(declared, includes=declared.get("target", "include-profiles", []))
    for kind, project in (("static-library", "port-static"), ("device-library", "port-device"),
                          ("application", "port-application")):
        text = cmake_project(declared, kind, project)
        if text is not None:
            produced["{}/CMakeLists.txt".format(kind)] = text
    if required and not produced:
        raise GenerationError("{} declares nothing Charon can generate".format(declared.root / spec.MANIFEST))
    return produced
