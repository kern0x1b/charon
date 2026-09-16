import os
import plistlib
import re
import shutil
import sys
from io import StringIO

from conan import ConanFile
from conan.errors import ConanException, ConanInvalidConfiguration
from conan.tools.apple import XCRun
from conan.tools.build import can_run
from conan.tools.cmake import CMake, CMakeDeps, CMakeToolchain, cmake_layout
from conan.tools.env import Environment
from conan.tools.files import copy, mkdir, rmdir
from conan.tools.scm import Version

PLACEHOLDER = re.compile(r"\{([a-z][a-z0-9_.-]*(?::[^{}]*)?)\}")


class Ios6BaseConan(ConanFile):
    name = "ios6-base"
    user = "ios6"
    channel = "stable"
    version = "1.0"
    package_type = "python-require"
    description = "Conventions every armv7 / iOS 6 port shares"
    license = "MIT"


class DependencyEnv:

    filename = "ios6-deps.env"

    def __init__(self, conanfile):
        self._conanfile = conanfile

    def generate(self):
        dependencies = self._conanfile.dependencies
        lines = []
        for context, graph in (("HOST", dependencies.host), ("BUILD", dependencies.build)):
            for dependency in graph.values():
                folder = dependency.package_folder
                if folder is None:
                    continue
                if re.search(r"[\s'\"$\\#]", folder):
                    raise ConanException(
                        f"{dependency.ref}: {folder} cannot be written as a shell and make assignment")
                name = re.sub(r"[^A-Z0-9]", "_", dependency.ref.name.upper())
                lines.append(f"IOS6_{context}_{name}={folder}")
        path = os.path.join(self._conanfile.generators_folder, self.filename)
        with open(path, "w") as out:
            out.write("\n".join(sorted(lines)) + "\n")


class Ios6Port:
    """Base class for a port's own conanfile.

    Inherited with python_requires_extend, the way a service inherits a
    convention plugin: the target, the generators and the checks live here, and
    the port's file is left saying only what that port needs.
    """

    settings = "os", "arch", "compiler", "build_type"
    generators = "CMakeDeps", "CMakeToolchain", "VirtualBuildEnv"

    def validate(self):
        arch = str(self.settings.arch)
        if str(self.settings.os) != "iOS" or arch not in ("armv7", "armv8"):
            raise ConanInvalidConfiguration(
                f"{self.name} targets iOS on armv7 or arm64; got {self.settings.os}/{arch}. "
                "Build it with -pr:h ios6-armv7 or -pr:h ios-arm64.")
        if arch == "armv8" and Version(str(self.settings.os.version)) < "7.0":
            raise ConanInvalidConfiguration(
                f"{self.name}: arm64 starts at iOS 7.0; the profile says {self.settings.os.version}.")

    def layout(self):
        self.folders.generators = os.path.join("build", "conan", str(self.settings.arch))

    def generate(self):
        DependencyEnv(self).generate()

    def _components(self, name):
        try:
            return self.dependencies[name].cpp_info.aggregated_components()
        except KeyError:
            available = ", ".join(sorted(dependency.ref.name for dependency in self.dependencies.host.values()))
            raise ConanException(f"{name} is not a dependency of {self.name}; it requires {available}")

    def _static_library(self, name, library):
        info = self._components(name)
        if library not in info.libs:
            raise ConanException(f"{name} does not provide {library}; it provides {', '.join(info.libs)}")
        for folder in info.libdirs:
            path = os.path.join(folder, f"lib{library}.a")
            if os.path.isfile(path):
                return path
        raise ConanException(f"{name} declares {library} but no lib{library}.a is in {', '.join(info.libdirs)}")

    def _build_tool(self, name):
        try:
            return os.path.join(self.dependencies.build[name].package_folder, "bin")
        except KeyError:
            available = ", ".join(sorted(dependency.ref.name for dependency in self.dependencies.build.values()))
            raise ConanException(f"{name} is not a build tool of {self.name}; it has {available}")

    def _resolve(self, name):
        kind, _, rest = name.partition(":")
        parts = [part for part in rest.split(":") if part] if rest else []
        if kind == "pkg" and len(parts) == 1:
            return self.dependencies[parts[0]].package_folder
        if kind == "include" and len(parts) == 1:
            return self._components(parts[0]).includedirs[0]
        if kind == "lib" and len(parts) == 2:
            return self._static_library(parts[0], parts[1])
        if kind == "libdirs" and len(parts) == 1:
            return " ".join(f"-L{folder}" for package in parts[0].split(",")
                            for folder in self._components(package).libdirs)
        if kind == "bin" and len(parts) == 1:
            return self._build_tool(parts[0])
        raise ConanException(f"{{{name}}} is not something this toolchain can resolve; it answers pkg:NAME, "
                             "include:NAME, lib:NAME:LIBRARY, libdirs:NAME[,NAME] and bin:TOOL")

    def resolved(self, text):
        return PLACEHOLDER.sub(lambda match: str(self._resolve(match.group(1))), str(text))

    def resolved_values(self, mapping):
        return {name: self.resolved(value) for name, value in mapping.items()}

    @property
    def declared(self):
        declaration = getattr(type(self), "declaration", None)
        if not declaration:
            raise ConanException(f"{self.name} carries no declaration; a generated recipe bakes one in")
        return declaration

    @property
    def port_root(self):
        root = getattr(type(self), "port", None)
        if not root:
            raise ConanException(f"{self.name} does not say which folder it was generated for")
        return root

    def declared_variant(self):
        chosen, matched = None, -1
        for name, declared in self.declared.get("variants", {}).items():
            wanted = [entry.split("=", 1) for entry in declared.get("options", [])]
            if all(str(self.options.get_safe(option)) == value for option, value in wanted) and len(wanted) > matched:
                chosen, matched = name, len(wanted)
        if chosen is None:
            raise ConanException(f"{self.name}: no declared variant matches the options this build was given")
        return chosen

    def declared_setting(self, section, key, default=None):
        variant = self.declared.get("variants", {}).get(self.declared_variant(), {})
        if key in variant:
            return variant[key]
        return self.declared.get(section, {}).get(key, default)

    def declared_target(self, kind, name):
        for target in self.declared.get(kind, []):
            if target.get("name") == name:
                return target
        raise ConanException(f"{self.name} declares no {kind} called {name}")

    def declared_targets(self):
        found = []
        for kind in ("static-library", "device-library"):
            found += self.declared.get(kind, [])
        application = self.declared.get("application")
        if application:
            found.append(application)
        return found

    def _target_product(self, name):
        kind, target = self._declared_kind(name)
        produced = target.get("produces")
        if not produced:
            raise ConanException(f"{name} does not say what it produces, so nothing can point at it")
        project = target.get("cmake")
        return os.path.join(self.build_folder, os.path.basename(project) if project else kind, produced)

    @property
    def sdk_path(self):
        sdk = self.conf.get("tools.apple:sdk_path", check_type=str)
        if not sdk:
            raise ConanException("tools.apple:sdk_path is not set; build with the port's profile")
        return sdk

    @property
    def stage_folder(self):
        return os.path.join(self.build_folder, "stage")

    def _declared_context(self):
        engine = self.declared.get("engine", {})
        tuning = " ".join(self.conf.get("tools.build:cxxflags", default=[], check_type=list))
        context = {
            "sdk": self.sdk_path,
            "triple": f"{self.settings.arch}-apple-ios{self.settings.os.version}",
            "tuning": tuning,
            "version": str(self.version),
            "source": self.source_folder,
            "build": self.build_folder,
            "stage": self.stage_folder,
            "stubs": os.path.join(self.port_root, engine.get("stubs", "")),
            "prefix-header": self.declared_setting("engine", "prefix-header", ""),
        }
        flags = self.declared.get("flags", {})
        for name in ("common", "defines", "c", "cxx", "objc", "objcxx"):
            if name in flags:
                context[name] = flags[name]
        return context

    def _resolve_declared(self, name, context, seen):
        if name in seen:
            raise ConanException(f"{{{name}}} refers to itself")
        if name in context:
            return self._expand(context[name], context, seen | {name})
        if name == "engine-exports":
            return self._expand(self.declared.get("engine", {}).get("exports", ""), context, seen)
        if name == "exports":
            return self._expand(self.declared_setting("engine", "exports", ""), context, seen)
        kind, _, rest = name.partition(":")
        if kind == "target" and rest:
            return self._target_product(rest)
        return None

    def _expand(self, text, context, seen=frozenset()):
        def replace(match):
            name = match.group(1)
            answered = self._resolve_declared(name, context, seen)
            return str(answered) if answered is not None else str(self._resolve(name))
        return PLACEHOLDER.sub(replace, str(text))

    def declared_flags(self, name):
        flags = self.declared.get("flags", {})
        if name not in flags:
            raise ConanException(f"{self.name} declares no {name} flags")
        return self._expand(flags[name], self._declared_context())

    def declared_options(self):
        context = self._declared_context()
        options = dict(self.declared.get("engine", {}).get("options", {}))
        variant = self.declared.get("variants", {}).get(self.declared_variant(), {})
        options.update(variant.get("engine-options", {}) or {})
        return {name: self._expand(value, context) for name, value in options.items()}

    def declared_layout(self):
        self.folders.root = os.path.relpath(self.port_root, self.recipe_folder)
        engine = self.declared.get("engine", {})
        if engine.get("cmake"):
            self.folders.source = engine["cmake"]
        self.folders.build = os.path.join("build", self.declared_variant())
        self.folders.generators = os.path.join(self.folders.build, "conan")

    def declared_toolchain(self):
        engine = self.declared.get("engine", {})
        user_toolchain = engine.get("user-toolchain")
        if user_toolchain:
            self.conf.define("tools.cmake.cmaketoolchain:user_toolchain",
                             [os.path.join(self.port_root, user_toolchain)])
        toolchain = CMakeToolchain(self)
        toolchain.blocks.remove("apple_system")
        variables = toolchain.cache_variables
        variables.update(self.declared_options())
        variables.update({
            "IOS6_SDK": self.sdk_path,
            "IOS6_DEPLOYMENT_TARGET": str(self.settings.os.version),
            "CMAKE_OSX_SYSROOT": self.sdk_path,
            "CMAKE_OSX_DEPLOYMENT_TARGET": str(self.settings.os.version),
            "CMAKE_BUILD_TYPE": "Release",
            "PYTHON_EXECUTABLE": sys.executable,
            "CMAKE_C_FLAGS": self.declared_flags("c"),
            "CMAKE_CXX_FLAGS": self.declared_flags("cxx"),
            "CMAKE_OBJC_FLAGS": self.declared_flags("objc"),
            "CMAKE_OBJCXX_FLAGS": self.declared_flags("objcxx"),
            "CMAKE_SHARED_LINKER_FLAGS": self.declared_flags("shared-link"),
            "CMAKE_EXE_LINKER_FLAGS": self.declared_flags("exe-link"),
            "CMAKE_MODULE_LINKER_FLAGS": self.declared_flags("module-link"),
        })
        include = engine.get("project-include")
        if include:
            name = engine.get("project-name")
            if not name:
                raise ConanException(
                    f"{self.name} declares project-include but no project-name. CMake applies the file as "
                    "CMAKE_PROJECT_<the name the engine gives project()>_INCLUDE, and the folder the sources "
                    "sit in is not that name; guessing it means the file is silently never included")
            variables[f"CMAKE_PROJECT_{name}_INCLUDE"] = os.path.join(self.port_root, include)
        toolchain.generate()

        deps = CMakeDeps(self)
        wanted = engine.get("find-packages", [])
        for dependency in self.dependencies.host.values():
            if dependency.ref.name not in wanted:
                deps.set_property(dependency.ref.name, "cmake_find_mode", "none")
        deps.generate()

        environment = Environment()
        environment.define("CCACHE_BASEDIR", self.port_root)
        environment.vars(self, scope="build").save_script("ccache_basedir")

    def declared_build(self):
        for step in self.declared_pipeline():
            action, _, argument = step.partition(":")
            self.output.title(step)
            self._run_step(action, argument)

    def declared_pipeline(self):
        variant = self.declared_variant()
        steps = self.declared.get("pipeline", {}).get(variant)
        if not steps:
            raise ConanException(f"{self.name} declares no pipeline for the {variant} variant, so building it "
                                 "would do nothing and report success")
        return steps

    def _run_step(self, action, argument):
        steps = {
            "task": self._run_task,
            "build": self._build_target,
            "check": self._run_check,
            "stage": self._run_stage,
        }
        if action not in steps:
            raise ConanException(f"{action} is not a step this toolchain knows; it runs "
                                 f"{', '.join(sorted(steps))}")
        steps[action](argument)

    def _run_task(self, name):
        declared = self.declared.get("tasks", {})
        if name not in declared:
            known = ", ".join(sorted(declared)) or "none declared"
            raise ConanException(f"{self.name} declares no task {name} ({known})")
        words = self._expand(declared[name], self._declared_context()).split()
        script = os.path.join(self.port_root, words[0])
        if not os.path.isfile(script):
            raise ConanException(f"{script} does not exist, and the task {name} names it")
        arguments = " ".join(f'"{word}"' for word in words[1:])
        self.run(f'"{sys.executable}" "{script}" {arguments}')

    def _declared_kind(self, name):
        for kind in ("static-library", "device-library"):
            for target in self.declared.get(kind, []):
                if target.get("name") == name:
                    return kind, target
        application = self.declared.get("application") or {}
        if application.get("name") == name:
            return "application", application
        raise ConanException(f"{self.name} declares no target called {name}")

    def _project_source(self, kind, target):
        project = target.get("cmake")
        if project:
            return os.path.join(self.port_root, project)
        written = os.path.join(self.recipe_folder, kind, "CMakeLists.txt")
        if not os.path.isfile(written):
            raise ConanException(
                f"{target.get('name')} names no cmake project of its own and none was written to {written}; "
                "the declaration is what generates it, so generating has to happen before building")
        return os.path.dirname(written)

    def _cmake_project(self, source, folder, definitions):
        toolchain = os.path.join(self.generators_folder, "conan_toolchain.cmake")
        values = " ".join(f'-D{name}="{value}"' for name, value in definitions.items())
        self.run(f'cmake -S "{source}" -B "{folder}" -G Ninja -DCMAKE_BUILD_TYPE=Release '
                 f'-DCMAKE_TOOLCHAIN_FILE="{toolchain}" -DIOS6_SDK="{self.sdk_path}" '
                 f'-DIOS6_DEPLOYMENT_TARGET="{self.settings.os.version}" '
                 f'-DCHARON_PORT="{self.port_root}" {values}')
        self.run(f'cmake --build "{folder}"')

    def _build_target(self, name):
        if name == "engine":
            cmake = CMake(self)
            cmake.configure()
            cmake.build()
            return
        if name == "application":
            self._build_application()
            return
        if name in ("static-library", "device-library"):
            self._build_kind(name)
            return
        kind, target = self._declared_kind(name)
        folder = os.path.join(self.build_folder, os.path.basename(target.get("cmake") or name))
        self._cmake_project(self._project_source(kind, target), folder, self._declared_cache(target))
        if target.get("installs-into") == "stage":
            self.run(f'cmake --install "{folder}" --prefix "{self.stage_folder}"')
            self._sign_installed(folder)

    def _declared_cache(self, *targets):
        context = self._declared_context()
        values = {}
        for target in targets:
            values.update({key: self._expand(value, context)
                           for key, value in (target.get("cache") or {}).items()})
        return values

    def _build_kind(self, kind):
        targets = [target for target in self.declared.get(kind, []) if not target.get("cmake")]
        if not targets:
            raise ConanException(f"{self.name} declares no {kind} for Charon to generate; a target that names a "
                                 "cmake project of its own is built by its own name")
        folder = os.path.join(self.build_folder, kind)
        self._cmake_project(self._project_source(kind, targets[0]), folder, self._declared_cache(*targets))
        if any(target.get("installs-into") == "stage" for target in targets):
            self.run(f'cmake --install "{folder}" --prefix "{self.stage_folder}"')
            self._sign_installed(folder)

    def _sign_installed(self, folder):
        macho = MachO(self)
        manifest = os.path.join(folder, "install_manifest.txt")
        with open(manifest) as installed:
            paths = [line.strip() for line in installed if line.strip()]
        for path in paths:
            if macho.is_macho(path):
                macho.strip(path)
                macho.sign(path)

    def _run_check(self, name):
        checks = {
            "exports": self._check_exports,
            "no-encryption-info": lambda: MachO(self).refuse_encryption_info(self.stage_folder),
            "imports": self._check_imports,
        }
        if name not in checks:
            raise ConanException(f"{name} is not a check this toolchain knows; it runs {', '.join(sorted(checks))}")
        checks[name]()

    def _check_exports(self):
        macho = MachO(self)
        listed_at = self._expand(self.declared_setting("engine", "exports", ""), self._declared_context())
        binary = os.path.join(self.build_folder, "WebKitLegacy.framework", "WebKitLegacy")
        with open(listed_at) as listing:
            listed = {line.strip() for line in listing if line.strip() and not line.lstrip().startswith("#")}
        exported = set(macho.output(f'"{macho.tool("nm")}" -gUj "{binary}"').split())
        missing, unlisted = sorted(listed - exported), sorted(exported - listed)
        if missing or unlisted:
            raise ConanException(f"{binary} was not linked with {listed_at}: {len(missing)} listed symbols not "
                                 f"exported (first: {missing[:3]}), {len(unlisted)} exported symbols not listed "
                                 f"(first: {unlisted[:3]})")

    def _check_imports(self):
        cache = self.conf.get("user.ios6:dyld_shared_cache", check_type=str)
        if not cache:
            raise ConanException(
                "user.ios6:dyld_shared_cache is not set, and check:imports is a step this pipeline declares. "
                "A step that reports success having looked at nothing is worse than no step at all, so either "
                "name the cache this port is checked against or take check:imports out of the pipeline")
        self.run(f'ios6-imports-check --cache "{cache}" --dist "{self.stage_folder}"')

    def _clear_stage(self):
        rmdir(self, self.stage_folder)
        mkdir(self, self.stage_folder)

    def _run_stage(self, name):
        stages = {"clear": self._clear_stage,
                  "frameworks": self._stage_frameworks,
                  "plists-to-binary": self._stage_binary_plists}
        if name not in stages:
            raise ConanException(f"{name} is not a staging step this toolchain knows; it runs "
                                 f"{', '.join(sorted(stages))}")
        stages[name]()

    def _stage_binary_plists(self):
        for folder, _, names in os.walk(self.stage_folder):
            for name in names:
                if not name.endswith(".plist"):
                    continue
                path = os.path.join(folder, name)
                with open(path, "rb") as source:
                    content = plistlib.load(source)
                with open(path, "wb") as target:
                    plistlib.dump(content, target, fmt=plistlib.FMT_BINARY)

    def _stage_frameworks(self):
        stage = self.declared.get("stage", {})
        engine = os.path.join(self.stage_folder, stage.get("engine-location", ""))
        macho, installed = MachO(self), {}
        for built, described in stage.get("frameworks", {}).items():
            name = described["as"]
            destination = os.path.join(engine, f"{name}.framework", name)
            mkdir(self, os.path.dirname(destination))
            shutil.copy2(os.path.join(self.build_folder, f"{built}.framework", built), destination)
            installed[destination] = described["replaces"]

        for built, described in stage.get("frameworks", {}).items():
            if not described.get("resources"):
                continue
            source = os.path.join(self.build_folder, f"{built}.framework")
            if not os.path.isdir(source):
                raise ConanException(f"{source} does not exist, and it is where {built} resources come from")
            target = os.path.join(engine, f"{described['as']}.framework")
            omit = set(described.get("omit", []))
            for entry in sorted(os.listdir(source)):
                if entry == built or entry in omit:
                    continue
                path = os.path.join(source, entry)
                if entry.endswith(".lproj"):
                    copy(self, "*.js", path, os.path.join(target, entry))
                elif os.path.isdir(path):
                    shutil.copytree(path, os.path.join(target, entry), symlinks=True, dirs_exist_ok=True)
                else:
                    shutil.copy2(path, target)
            for flatten in described.get("flatten", []):
                origin = os.path.join(target, flatten["from"])
                if not os.path.isdir(origin):
                    continue
                for pattern in flatten.get("patterns", []):
                    copy(self, pattern, origin, os.path.join(target, flatten["into"]))

        runtime = self._components("libcxx").libdirs[0]
        for built, renamed in stage.get("runtime", {}).items():
            destination = os.path.join(self.stage_folder, "usr", "lib", renamed)
            mkdir(self, os.path.dirname(destination))
            shutil.copy2(os.path.join(runtime, built), destination)
            installed[destination] = f"/usr/lib/{renamed}"

        macho.retarget(installed)
        for binary in installed:
            if not binary.endswith(".dylib"):
                macho.require_compatibility_version(binary, "1.0.0")
                macho.strip(binary, "-S -x")
            macho.sign(binary)

    def _build_application(self):
        declared = self.declared.get("application", {})
        name = declared.get("name")
        if not name:
            raise ConanException(f"{self.name} declares no application to build")
        bundle = os.path.join(self.build_folder, f"{name}.app")
        frameworks = os.path.join(bundle, "Frameworks")
        rmdir(self, bundle)
        mkdir(self, frameworks)

        folder = os.path.join(self.build_folder, os.path.basename(declared.get("cmake") or "application"))
        self._cmake_project(self._project_source("application", declared), folder, self._declared_cache(declared))
        self.run(f'cmake --install "{folder}" --prefix "{bundle}"')

        macho, bundled = MachO(self), {}
        stage = self.declared.get("stage", {})
        for built in stage.get("frameworks", {}):
            destination = os.path.join(frameworks, f"{built}.framework", built)
            shutil.copytree(os.path.join(self.build_folder, f"{built}.framework"),
                            os.path.dirname(destination), symlinks=True, dirs_exist_ok=True)
            bundled[destination] = f"@executable_path/Frameworks/{built}.framework/{built}"
        runtime = self._components("libcxx").libdirs[0]
        for built in stage.get("runtime", {}):
            library = built.replace(".1.0.", ".1.")
            destination = os.path.join(frameworks, library)
            shutil.copy2(os.path.join(runtime, built), destination)
            bundled[destination] = f"@executable_path/Frameworks/{library}"

        macho.retarget(bundled)
        for binary in bundled:
            if not binary.endswith(".dylib"):
                macho.require_compatibility_version(binary, "1.0.0")
            macho.sign(binary)

        self._write_application_plist(bundle, name, declared)
        entitlements = declared.get("entitlements")
        executable = os.path.join(bundle, name)
        macho.repoint(executable, bundled)
        carried = {os.path.basename(identity) for identity in bundled.values()}
        elsewhere = [reference for reference in macho.references(executable)
                     if os.path.basename(reference) in carried
                     and not reference.startswith("@executable_path/")]
        if elsewhere:
            raise ConanException(
                f"{executable} loads {', '.join(elsewhere)} from outside its own bundle while shipping a copy "
                "of each; the application would run against whatever the system has there instead of what it "
                "was built with")
        macho.sign(executable, os.path.join(self.port_root, entitlements) if entitlements else None)

    def _write_application_plist(self, bundle, name, declared):
        described = dict(declared.get("plist", {}))
        scheme = described.pop("url-scheme", None)
        identifier = described.get("CFBundleIdentifier", name)
        info = {
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleExecutable": name,
            "CFBundleVersion": str(self.version),
            "CFBundleShortVersionString": str(self.version),
            "MinimumOSVersion": str(self.settings.os.version),
        }
        info.update(described)
        if scheme:
            info["CFBundleURLTypes"] = [{"CFBundleURLName": identifier, "CFBundleURLSchemes": [scheme]}]
        with open(os.path.join(bundle, "Info.plist"), "wb") as handle:
            plistlib.dump(info, handle)

    def declared_package(self):
        for name in self.declared.get("port", {}).get("licenses", []):
            copy(self, name, self.port_root, os.path.join(self.package_folder, "licenses"))
        application = self.declared.get("application", {})
        if application and self.declared_variant() == application.get("variant"):
            bundle = f"{application['name']}.app"
            shutil.copytree(os.path.join(self.build_folder, bundle),
                            os.path.join(self.package_folder, bundle), symlinks=True, dirs_exist_ok=True)
            return
        shutil.copytree(self.stage_folder, os.path.join(self.package_folder, "root"),
                        symlinks=True, dirs_exist_ok=True)
        described = self.declared.get("package", {})
        control = described.get("control")
        if not control:
            raise ConanException(f"{self.name} declares no package control file, so no .deb can be written")
        scripts = described.get("maintainer-scripts")
        DebianPackage(self, os.path.join(self.port_root, control), self.stage_folder,
                      os.path.join(self.port_root, scripts) if scripts else None
                      ).write(os.path.join(self.package_folder, "deb"))


class MachO:
    """Reading and correcting the Mach-O files a port produces.

    Every method takes a path and answers about that file, so a port says what
    it wants done and never assembles an otool or install_name_tool command of
    its own. A reference that cannot be resolved is refused rather than left for
    dyld to fail on at load, where iOS 6 gives up with no crash log.
    """

    ENCRYPTED = "LC_ENCRYPTION_INFO"
    MAGIC = (b"\xce\xfa\xed\xfe", b"\xca\xfe\xba\xbe")

    def __init__(self, conanfile):
        self._conanfile = conanfile

    def tool(self, name):
        return XCRun(self._conanfile).find(name)

    def output(self, command):
        captured = StringIO()
        self._conanfile.run(command, stdout=captured)
        return captured.getvalue()

    @classmethod
    def is_macho(cls, path):
        if os.path.islink(path) or not os.path.isfile(path):
            return False
        with open(path, "rb") as candidate:
            return candidate.read(4) in cls.MAGIC

    def binaries_under(self, root):
        found = []
        for folder, _, names in os.walk(root):
            for name in names:
                path = os.path.join(folder, name)
                if self.is_macho(path):
                    found.append(path)
        return sorted(found)

    def install_name(self, binary):
        listing = self.output(f'"{self.tool("otool")}" -D "{binary}"').splitlines()
        return listing[1].strip() if len(listing) > 1 else None

    def references(self, binary):
        listing = self.output(f'"{self.tool("otool")}" -L "{binary}"')
        found = [match.group(1) for match in re.finditer(r"^\t(\S+) \(compatibility version", listing, re.M)]
        identity = self.install_name(binary)
        return [reference for reference in found if reference != identity]

    def compatibility_version(self, binary):
        commands = self.output(f'"{self.tool("otool")}" -l "{binary}"').split("Load command")
        identity = next((block for block in commands if "cmd LC_ID_DYLIB" in block), "")
        match = re.search(r"compatibility version (\S+)", identity)
        return match.group(1) if match else None

    def refuse_encryption_info(self, root):
        otool = self.tool("otool")
        stamped = [os.path.relpath(path, root) for path in self.binaries_under(root)
                   if self.ENCRYPTED in self.output(f'"{otool}" -l "{path}"')]
        if stamped:
            raise ConanException(f"linked by a linker that stamps {self.ENCRYPTED}, which iOS 6 refuses in a "
                                 f"library it loads: {', '.join(stamped)}")

    def repoint(self, binary, identities):
        rename = os.path.basename
        by_name = {rename(identity).replace("librev-", "lib"): identity for identity in identities.values()}
        install_name_tool = self.tool("install_name_tool")
        for reference in self.references(binary):
            target = by_name.get(rename(reference))
            if target and target != reference:
                self._conanfile.run(f'"{install_name_tool}" -change "{reference}" "{target}" "{binary}"')

    def retarget(self, identities):
        install_name_tool = self.tool("install_name_tool")
        for binary, identity in identities.items():
            self._conanfile.run(f'"{install_name_tool}" -id "{identity}" "{binary}"')
            self.repoint(binary, identities)
            unresolved = [reference for reference in self.references(binary) if reference.startswith("@rpath/")]
            if unresolved:
                raise ConanException(f"{binary} still depends on {', '.join(unresolved)}")

    def require_compatibility_version(self, binary, expected):
        found = self.compatibility_version(binary)
        if found != expected:
            raise ConanException(f"{binary} declares compatibility version {found} and the system's clients of "
                                 f"this framework recorded {expected}")

    def strip(self, binary, arguments="-x"):
        self._conanfile.run(f'"{self.tool("strip")}" {arguments} "{binary}"')

    def sign(self, binary, entitlements=None):
        flags = f'-S"{entitlements}"' if entitlements else "-S"
        self._conanfile.run(f'ldid {flags} "{binary}"')


class DebianPackage:
    """A .deb for the device's dpkg, written from a staged filesystem tree.

    The same archive dpkg-deb and theos's dm.pl write: an ar file holding
    debian-binary, control.tar.gz and data.tar.lzma. The version comes from the
    recipe, so the control file a port keeps says everything but that.
    """

    def __init__(self, conanfile, control, root, scripts=None):
        self._conanfile = conanfile
        self._control = control
        self._root = root
        self._scripts = scripts

    def _fields(self):
        with open(self._control) as template:
            text = template.read().rstrip("\n")
        if re.search(r"^(Version|Installed-Size):", text, re.M):
            raise ConanException(f"{self._control} must not carry Version or Installed-Size; the recipe writes them")
        fields = dict(re.findall(r"^([A-Za-z-]+):\s*(.*)$", text, re.M))
        for required in ("Package", "Architecture"):
            if required not in fields:
                raise ConanException(f"{self._control} has no {required} field")
        size = sum(os.lstat(os.path.join(folder, name)).st_size
                   for folder, _, names in os.walk(self._root) for name in names)
        text += f"\nVersion: {self._conanfile.version}\nInstalled-Size: {(size + 1023) // 1024}\n"
        return fields, text

    @staticmethod
    def _tar(members, compression):
        import io
        import tarfile

        buffer = io.BytesIO()
        mode = "w:gz" if compression == "gz" else "w"
        with tarfile.open(fileobj=buffer, mode=mode, format=tarfile.GNU_FORMAT) as archive:
            for name, path, data in members:
                info = archive.gettarinfo(path, arcname=name) if path else tarfile.TarInfo(name)
                info.uid = info.gid = 0
                info.uname = info.gname = "root"
                info.mtime = 0
                if data is not None:
                    info.size = len(data)
                    info.mode = 0o644
                    archive.addfile(info, io.BytesIO(data))
                elif info.isfile():
                    with open(path, "rb") as content:
                        archive.addfile(info, content)
                else:
                    archive.addfile(info)
        payload = buffer.getvalue()
        if compression == "lzma":
            import lzma
            payload = lzma.compress(payload, format=lzma.FORMAT_ALONE, preset=9)
        return payload

    def _data_members(self):
        members = [("./", self._root, None)]
        for folder, directories, names in os.walk(self._root):
            directories.sort()
            for name in sorted(directories) + sorted(names):
                path = os.path.join(folder, name)
                members.append(("./" + os.path.relpath(path, self._root), path, None))
        return members

    def write(self, destination):
        fields, control = self._fields()
        control_members = [("./", self._root, None), ("./control", None, control.encode())]
        if self._scripts and os.path.isdir(self._scripts):
            for name in sorted(os.listdir(self._scripts)):
                control_members.append((f"./{name}", os.path.join(self._scripts, name), None))
        parts = [
            ("debian-binary", b"2.0\n"),
            ("control.tar.gz", self._tar(control_members, "gz")),
            ("data.tar.lzma", self._tar(self._data_members(), "lzma")),
        ]
        os.makedirs(destination, exist_ok=True)
        path = os.path.join(destination,
                            f"{fields['Package']}_{self._conanfile.version}_{fields['Architecture']}.deb")
        with open(path, "wb") as deb:
            deb.write(b"!<arch>\n")
            for name, data in parts:
                deb.write(f"{name:<16}{0:<12}{0:<6}{0:<6}{0o100644:<8o}{len(data):<10}`\n".encode())
                deb.write(data)
                if len(data) % 2:
                    deb.write(b"\n")
        return path


class Ios6TestPackage:
    """Base class for a recipe's test_package.

    Builds test_package.c or test_package.cpp against the package under test and
    links it for the target, so a package that compiles but cannot be linked
    against fails at conan create rather than inside the port. The program runs
    only where the target can run.
    """

    settings = "os", "arch", "compiler", "build_type"
    generators = "CMakeDeps", "CMakeToolchain", "VirtualRunEnv"
    test_type = "explicit"

    def requirements(self):
        self.requires(self.tested_reference_str)

    def layout(self):
        cmake_layout(self)

    def build(self):
        cmake = CMake(self)
        cmake.configure()
        cmake.build()

    def test(self):
        if can_run(self):
            self.run(os.path.join(self.cpp.build.bindir, "test_package"), env="conanrun")
