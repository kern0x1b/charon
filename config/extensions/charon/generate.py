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
from pathlib import Path

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


def _is_pattern(text):
    return any(character in text for character in "*?[")


def _matches(root, pattern, name):
    if root is None:
        raise GenerationError("{} names {} as a pattern, which needs the port folder to expand".format(name, pattern))
    return sorted(path.relative_to(root).as_posix() for path in Path(root).glob(pattern) if path.is_file())


def _sources(target, root=None):
    name = target["name"]
    sources = target.get("sources")
    if not sources:
        raise GenerationError("{} declares no sources and no cmake= to use instead".format(name))
    excluded = set()
    for pattern in target.get("exclude", []):
        excluded.update(_matches(root, pattern, name))
    expanded = []
    for entry in sources:
        if _is_pattern(entry):
            found = _matches(root, entry, name)
            if not found:
                raise GenerationError("{}: {} matches no file under {}".format(name, entry, root))
        else:
            found = [entry]
        expanded += [path for path in found if path not in excluded and path not in expanded]
    if not expanded:
        raise GenerationError("{} declares sources and exclude takes every one of them".format(name))
    return expanded


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


def _library_block(target, kind, root=None):
    name = target["name"]
    sources = [_path(source) for source in _sources(target, root)]
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
        return (["install(TARGETS {} RUNTIME DESTINATION .)".format(name)] +
                _resource_lines(target, "."))
    install = target["install"].lstrip("/")
    return (["install(TARGETS {} LIBRARY DESTINATION {})".format(name, install)] +
            _resource_lines(target, install))


def _resource_lines(target, destination):
    lines = []
    files = [resource for resource in target.get("resources", []) if isinstance(resource, str)]
    if files:
        lines.append("install(FILES {} DESTINATION {})".format(" ".join(_path(file) for file in files), destination))
    for resource in target.get("resources", []):
        if isinstance(resource, str):
            continue
        if not isinstance(resource, dict) or not resource.get("from") or not resource.get("as"):
            raise GenerationError("{} declares the resource {!r}. A resource is a path, or a table with from and "
                                  "as; anything else would be left out of the build without a word".format(
                                      target["name"], resource))
        source, renamed = _path(resource["from"]), resource["as"]
        if resource["from"].endswith("/"):
            lines.append("install(DIRECTORY {} DESTINATION {})".format(
                source, destination if renamed == "." else renamed.lstrip("/")))
        elif renamed.startswith("/"):
            folder, _, file = renamed.rpartition("/")
            lines.append("install(FILES {} DESTINATION {} RENAME {})".format(
                source, folder.lstrip("/") or ".", file))
        else:
            lines.append("install(FILES {} DESTINATION {} RENAME {})".format(source, destination, renamed))
    return lines


def cmake_project(declared, kind, project):
    targets = [target for target in declared.targets(kind) if declared.generates(target)]
    if not targets:
        return None
    languages = []
    for target in targets:
        for language in _languages(_sources(target, declared.root)):
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
        lines += _library_block(target, kind, declared.root) + [""]
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


PROJECT_INCLUDE = "project-include.cmake"
CROSS_TOOLCHAIN = "cross-toolchain.cmake"

CROSS_TEMPLATE = '''{generated}
set(CMAKE_SYSTEM_NAME {system})
set(CMAKE_SYSTEM_PROCESSOR {processor})

if (NOT IOS6_SDK OR NOT IOS6_DEPLOYMENT_TARGET)
    message(FATAL_ERROR
        "IOS6_SDK and IOS6_DEPLOYMENT_TARGET come from the profile Charon wrote. Reading them from the "
        "environment instead would leave them empty when ninja re-runs cmake by itself, and cmake would "
        "quietly fall back to the newest installed SDK")
endif ()
set(IOS6_SDK "${{IOS6_SDK}}" CACHE PATH "SDK this port is compiled against" FORCE)
set(IOS6_DEPLOYMENT_TARGET "${{IOS6_DEPLOYMENT_TARGET}}" CACHE STRING "Oldest release this runs on" FORCE)
set(CMAKE_OSX_SYSROOT ${{IOS6_SDK}} CACHE PATH "SDK the compiler is pointed at" FORCE)
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES IOS6_SDK IOS6_DEPLOYMENT_TARGET)
set(CMAKE_OSX_ARCHITECTURES {arch})
set(CMAKE_OSX_DEPLOYMENT_TARGET ${{IOS6_DEPLOYMENT_TARGET}})

if (DEFINED ENV{{DEVELOPER_DIR}})
    set(DEVELOPER_ROOT $ENV{{DEVELOPER_DIR}})
else ()
    execute_process(COMMAND xcode-select -p
        OUTPUT_VARIABLE DEVELOPER_ROOT OUTPUT_STRIP_TRAILING_WHITESPACE)
endif ()
if (EXISTS ${{DEVELOPER_ROOT}}/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang)
    set(TOOLCHAIN_BIN ${{DEVELOPER_ROOT}}/Toolchains/XcodeDefault.xctoolchain/usr/bin)
else ()
    set(TOOLCHAIN_BIN ${{DEVELOPER_ROOT}}/usr/bin)
endif ()
set(CMAKE_C_COMPILER ${{TOOLCHAIN_BIN}}/clang)
set(CMAKE_CXX_COMPILER ${{TOOLCHAIN_BIN}}/clang++)

set(SDK6 ${{IOS6_SDK}})
set(COMMON "-target {arch}-apple-{system_lower}${{IOS6_DEPLOYMENT_TARGET}} -isysroot ${{SDK6}}")
set(CMAKE_C_FLAGS_INIT "${{COMMON}}{defines}")
set(CMAKE_OBJC_FLAGS_INIT "${{COMMON}}{defines}")
set(CMAKE_CXX_FLAGS_INIT "${{COMMON}}{defines}")
set(CMAKE_OBJCXX_FLAGS_INIT "${{COMMON}}{defines}")
set(CMAKE_EXE_LINKER_FLAGS_INIT "${{COMMON}}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${{COMMON}}")

set(CMAKE_FIND_ROOT_PATH ${{SDK6}})
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)

if (EXISTS ${{DEVELOPER_ROOT}}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk)
    set(MIG_SYSROOT ${{DEVELOPER_ROOT}}/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk)
else ()
    set(MIG_SYSROOT ${{DEVELOPER_ROOT}}/SDKs/MacOSX.sdk)
endif ()
'''


def cross_toolchain(declared):
    target = declared.section("target")
    for required in ("arch", "os"):
        if required not in target:
            raise GenerationError(
                "[target] declares no {}, and the cross toolchain cannot be written without it".format(required))
    defines = target.get("defines", [])
    return CROSS_TEMPLATE.format(
        generated=GENERATED,
        system=target.get("system-name", "Darwin"),
        processor=target.get("system-processor", "arm"),
        arch=target["arch"],
        system_lower=str(target["os"]).lower(),
        defines="".join(" {}".format(define) for define in defines),
    )


def project_include(declared):
    packages = declared.get("engine", "config-packages", [])
    if not packages:
        return None
    lines = [GENERATED]
    lines += ["find_package({} REQUIRED CONFIG)".format(name) for name in packages]
    return "\n".join(lines) + "\n"


TIER_RECIPE = '''{generated}
from conan import ConanFile


class TierPackages(ConanFile):
    name = {name}
    version = "1.0"
    settings = "os", "arch", "compiler", "build_type"
    python_requires = {base}

    def requirements(self):
        for reference in {requires}:
            self.requires(reference)

    def generate(self):
        self.python_requires["ios6-base"].module.DependencyEnv(self).generate()
'''


def tier_recipe(declared, tier, packages):
    described = declared.section("port")
    if "name" not in described:
        raise GenerationError("[port] declares no name, and a tier's packages cannot be named without it")
    return TIER_RECIPE.format(
        generated=GENERATED,
        name=repr("{}-{}-packages".format(described["name"], tier)),
        base=repr(str(declared.get("use", "base", BASE))),
        requires=repr(_references(packages)),
    )


def written(declared, required=True):
    produced = {}
    applied = project_include(declared)
    if applied is not None:
        produced[PROJECT_INCLUDE] = applied
    if declared.using("toolchain") is None and declared.get("engine", "user-toolchain", None) is None:
        produced[CROSS_TOOLCHAIN] = cross_toolchain(declared)
    for tier, described in declared.tiers().items():
        packages = described.get("packages")
        if packages:
            produced["tests/{}/conanfile.py".format(tier)] = tier_recipe(declared, tier, packages)
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
