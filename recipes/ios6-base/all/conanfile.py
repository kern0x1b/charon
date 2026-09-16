import os
import plistlib
import re
import shutil
import struct
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
        chosen = self.conf.get("user.charon:port", check_type=str)
        if chosen:
            return chosen
        root = getattr(type(self), "port", None)
        if root:
            return root
        folder = getattr(self, "recipe_folder", None)
        if folder and os.path.basename(os.path.normpath(folder)) == "charon":
            candidate = os.path.normpath(os.path.join(folder, os.pardir, os.pardir, os.pardir))
            if os.path.isfile(os.path.join(candidate, "charon.toml")):
                return candidate
        raise ConanException(f"{self.name} cannot tell which port it was written for: it is not in a port's "
                             "build/<variant>/charon folder, and user.charon:port is not set")

    def declared_variant(self):
        building = self.declared.get("for-variant")
        if building:
            return building
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
            "port": self.port_root,
            "stubs": os.path.join(self.port_root, engine.get("stubs", "")),
            "prefix-header": self.declared_setting("engine", "prefix-header", ""),
        }
        application = self.declared.get("application") or {}
        if application.get("name"):
            bundle = os.path.join(self.build_folder, f"{application['name']}.app")
            context["application"] = bundle
            context["executable"] = os.path.join(bundle, application["name"])
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

    FLAG_VARIABLES = (("CMAKE_C_FLAGS", "c"), ("CMAKE_CXX_FLAGS", "cxx"), ("CMAKE_OBJC_FLAGS", "objc"),
                      ("CMAKE_OBJCXX_FLAGS", "objcxx"), ("CMAKE_SHARED_LINKER_FLAGS", "shared-link"),
                      ("CMAKE_EXE_LINKER_FLAGS", "exe-link"), ("CMAKE_MODULE_LINKER_FLAGS", "module-link"))

    def declared_flag_variables(self):
        declared = self.declared.get("flags", {})
        return {variable: self.declared_flags(name) for variable, name in self.FLAG_VARIABLES if name in declared}

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
            cross = os.path.join(self.port_root, user_toolchain)
        else:
            cross = os.path.join(self.recipe_folder, "cross-toolchain.cmake")
            if not os.path.isfile(cross):
                raise ConanException(
                    f"{self.name} names no user-toolchain of its own and nothing was written to {cross}. "
                    "It is what points the compiler at the SDK this port targets; without it cmake falls "
                    "back to the newest installed one and compiles against a system years newer")
        self.conf.define("tools.cmake.cmaketoolchain:user_toolchain", [cross])
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
        })
        variables.update(self.declared_flag_variables())
        include = engine.get("project-include")
        if include:
            applied = os.path.join(self.port_root, include)
        elif engine.get("config-packages"):
            applied = os.path.join(self.recipe_folder, "project-include.cmake")
            if not os.path.isfile(applied):
                raise ConanException(
                    f"{self.name} declares config-packages and nothing was written to {applied}; the "
                    "declaration is what generates it, so generating has to happen before building")
        else:
            applied = None
        if applied:
            name = engine.get("project-name")
            if not name:
                raise ConanException(
                    f"{self.name} says which packages the engine must find by config, or names a "
                    "project-include of its own, but no project-name. CMake applies the file as "
                    "CMAKE_PROJECT_<the name the engine gives project()>_INCLUDE, and the folder the sources "
                    "sit in is not that name; guessing it means the file is silently never included")
            variables[f"CMAKE_PROJECT_{name}_INCLUDE"] = applied
        toolchain.generate()

        deps = CMakeDeps(self)
        wanted = self.declared_find_packages()
        for dependency in self.dependencies.host.values():
            if dependency.ref.name not in wanted:
                deps.set_property(dependency.ref.name, "cmake_find_mode", "none")
        deps.generate()

        environment = Environment()
        environment.define("CCACHE_BASEDIR", self.port_root)
        environment.vars(self, scope="build").save_script("ccache_basedir")

    def declared_steps(self):
        chosen = self.conf.get("user.charon:steps", default=None, check_type=list)
        return list(chosen) if chosen else self.declared_pipeline()

    def declared_build(self):
        for step in self.declared_steps():
            action, _, argument = step.partition(":")
            self.output.title(step)
            self._run_step(action, argument)

    def declared_pipeline(self):
        variant = self.declared_variant()
        steps = self.declared.get("pipeline", {}).get(variant)
        if not steps:
            raise ConanException(f"{self.name} declares no pipeline for the {variant} variant, so building it "
                                 "would do nothing and report success")
        merged = {name for declared in self.declared.get("variants", {}).values()
                  for name in (declared.get("merge") or [])}
        if variant in merged and "sign:application" in steps:
            raise ConanException(
                f"the {variant} pipeline signs an application that another variant merges; the merged "
                "executable is signed after the merge, and a signature on one slice is lost in it")
        if "sign:application" in steps:
            signed = steps.index("sign:application")
            after = [step for step in steps[signed + 1:] if step in ("build:application", "merge:application")]
            if after:
                raise ConanException(
                    f"the {variant} pipeline runs {', '.join(after)} after sign:application; anything that "
                    "changes the bundle has to come before it is signed")
        if "build:application" in steps and variant not in merged:
            built = steps.index("build:application")
            if "sign:application" not in steps[built + 1:]:
                raise ConanException(
                    f"the {variant} pipeline builds the application and never signs it, and an unsigned "
                    "application does not start on the device; add sign:application after build:application "
                    "and after any task that changes the executable, or name {variant} in the merge of the "
                    "variant that signs it")
        return steps

    def _run_step(self, action, argument):
        steps = {
            "task": self._run_task,
            "build": self._build_target,
            "check": self._run_check,
            "stage": self._run_stage,
            "sign": self._sign_target,
            "merge": self._merge_target,
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
        body = declared[name]
        if not isinstance(body, dict):
            raise ConanException(
                f"task {name} is declared as {body!r}. A task is a table - [tasks.{name}] with script, shell or "
                "python - so that every task in a declaration reads the same way")
        kinds = [kind for kind in ("script", "shell", "python") if kind in body]
        if len(kinds) != 1:
            raise ConanException(f"task {name} declares {', '.join(kinds) or 'none'} of script, shell and python, "
                                 "and a task has to say exactly one thing to run")
        context = self._declared_context()
        arguments = self._expand(body.get("args", ""), context)
        if kinds[0] == "script":
            return self._run_script(name, "{} {}".format(self._expand(body["script"], context), arguments))
        if kinds[0] == "shell":
            return self.run(" ".join(part for part in (self._expand(body["shell"], context), arguments) if part),
                            cwd=self.port_root)
        return self._run_written(name, body["python"], arguments)

    def _run_script(self, name, commandline):
        words = commandline.split()
        script = os.path.join(self.port_root, words[0])
        if not os.path.isfile(script):
            raise ConanException(f"{script} does not exist, and the task {name} names it")
        arguments = " ".join(f'"{word}"' for word in words[1:])
        self.run(f'"{sys.executable}" "{script}" {arguments}', cwd=self.port_root)

    def _run_written(self, name, body, arguments):
        folder = os.path.join(self.build_folder, "charon-tasks")
        mkdir(self, folder)
        written = os.path.join(folder, f"{name}.py")
        with open(written, "w") as handle:
            handle.write(body)
        self.run(f'"{sys.executable}" "{written}" {arguments}', cwd=self.port_root)

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
        self._verify_inputs(folder)

    def _build_target(self, name):
        if name == "engine":
            cmake = CMake(self)
            cmake.configure()
            cmake.build()
            self._verify_inputs(self.build_folder)
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

    def declared_find_packages(self):
        wanted = list((self.declared.get("engine") or {}).get("find-packages", []))
        for kind in ("static-library", "device-library", "executable", "application"):
            declared = self.declared.get(kind) or []
            for target in [declared] if isinstance(declared, dict) else declared:
                wanted += [package for package in target.get("packages", []) if package not in wanted]
        return wanted

    def declared_waivers(self):
        waived = self.declared.get("waive") or {}
        for name, why in waived.items():
            if name not in MachO.WAIVABLE:
                raise ConanException(f"[waive] names {name}, which is not something this toolchain verifies; it "
                                     f"verifies {', '.join(MachO.WAIVABLE)}")
            reasons = why.values() if name == "input-minimum" and isinstance(why, dict) else [why]
            if not reasons or any(not isinstance(reason, str) or not reason.strip() for reason in reasons):
                raise ConanException(f"[waive] {name} gives no reason, and a check is only left out for one")
        return waived

    def _verify_inputs(self, folder):
        waived = self.declared_waivers().get("input-minimum")
        if isinstance(waived, str):
            self.output.warning(f"input-minimum not checked: {waived}")
            return
        waived = waived or {}
        arch, target = str(self.settings.arch), str(self.settings.os.version)
        cputype = MachO.CPU_TYPES.get(arch)
        if cputype is None:
            raise ConanException(f"{arch} is not an architecture this toolchain reads link inputs for")
        problems, objects, members = [], 0, 0
        for place, _, names in os.walk(folder):
            for name in sorted(names):
                if name.endswith(".o"):
                    path = os.path.join(place, name)
                    objects += 1
                    problems += MachO.minimum_problems(path, cputype, target, os.path.relpath(path, folder))
        checked = getattr(self, "_inputs_checked", set())
        for reference, dependency in self.dependencies.host.items():
            package = reference.ref.name
            if package in checked:
                continue
            checked.add(package)
            if package in waived:
                self.output.warning(f"input-minimum not checked for {package}: {waived[package]}")
                continue
            for libdir in dependency.cpp_info.aggregated_components().libdirs:
                if not os.path.isdir(libdir):
                    continue
                for name in sorted(os.listdir(libdir)):
                    path = os.path.join(libdir, name)
                    if name.endswith(".a") and not os.path.islink(path):
                        members += len(MachO.recorded_minimums(path, cputype))
                        problems += MachO.minimum_problems(path, cputype, target, f"{package}/{name}")
        self._inputs_checked = checked
        unknown = sorted(set(waived) - {dependency.ref.name for dependency in self.dependencies.host.values()})
        if unknown:
            raise ConanException(f"[waive] input-minimum names {', '.join(unknown)}, which this build does not "
                                 "depend on")
        if problems:
            shown = "; ".join(problems[:5]) + (f"; and {len(problems) - 5} more" if len(problems) > 5 else "")
            raise ConanException(f"a link input was not built for this target: {shown}")
        self.output.info(f"{objects} objects in {os.path.basename(folder)} and {members} archive members of its "
                         f"dependencies record iOS {target}")

    def _verify(self, binary):
        MachO(self).verify(binary, self.declared_waivers())

    def _sign_installed(self, folder):
        macho = MachO(self)
        manifest = os.path.join(folder, "install_manifest.txt")
        with open(manifest) as installed:
            paths = [line.strip() for line in installed if line.strip()]
        for path in paths:
            if macho.is_macho(path):
                self._verify(path)
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

        runtime, runtime_files = self.declared_runtime()
        for built, renamed in runtime_files.items():
            destination = os.path.join(self.stage_folder, "usr", "lib", renamed)
            mkdir(self, os.path.dirname(destination))
            shutil.copy2(os.path.join(runtime, built), destination)
            installed[destination] = f"/usr/lib/{renamed}"

        macho.retarget(installed)
        for binary in installed:
            self._verify(binary)
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
        runtime, runtime_files = self.declared_runtime()
        for built in runtime_files:
            library = built.replace(".1.0.", ".1.")
            destination = os.path.join(frameworks, library)
            shutil.copy2(os.path.join(runtime, built), destination)
            bundled[destination] = f"@executable_path/Frameworks/{library}"
        bundled.update(self._declared_bundle(bundle, declared))

        macho.retarget(bundled)
        for binary in bundled:
            self._verify(binary)
            if not binary.endswith(".dylib"):
                macho.require_compatibility_version(binary, "1.0.0")
            macho.sign(binary)

        self._write_application_plist(bundle, name, declared)
        executable = os.path.join(bundle, name)
        macho.repoint(executable, bundled)
        carried = {MachO.library_stem(identity) for identity in bundled.values()}
        for binary in [executable] + list(bundled):
            elsewhere = [reference for reference in macho.references(binary)
                         if MachO.library_stem(reference) in carried
                         and not reference.startswith("@executable_path/")]
            if elsewhere:
                raise ConanException(
                    f"{binary} loads {', '.join(elsewhere)} from outside its own bundle while the bundle carries "
                    "that library; it would run against whatever the system has there instead of what it was "
                    "built with, and two copies of one runtime in a process do not agree")
        self._verify(executable)
        if declared.get("strip"):
            macho.strip(executable, declared["strip"])

    def _merge_target(self, name):
        if name != "application":
            raise ConanException(f"merge:{name} is not something this toolchain merges; it merges application")
        application = (self.declared.get("application") or {}).get("name")
        if not application:
            raise ConanException(f"{self.name} declares no application to merge")
        variant = self.declared_variant()
        slices = (self.declared.get("variants", {}).get(variant) or {}).get("merge") or []
        if len(slices) < 2:
            raise ConanException(f"the {variant} variant runs merge:application and names fewer than two slices "
                                 "under merge")
        bundles = [os.path.join(self.port_root, "build", slice_name, f"{application}.app") for slice_name in slices]
        missing = [slice_name for slice_name, bundle in zip(slices, bundles) if not os.path.isdir(bundle)]
        if missing:
            raise ConanException(f"there is no {application}.app for {', '.join(missing)}; build each slice "
                                 "before merging, which charon build does when it builds the merging variant")
        binaries, problems = MachO.merge_plan(bundles)
        if problems:
            raise ConanException(f"the slices of {application}.app cannot be merged: " + "; ".join(problems))
        destination = os.path.join(self.build_folder, f"{application}.app")
        rmdir(self, destination)
        shutil.copytree(bundles[0], destination, symlinks=True)
        macho = MachO(self)
        lipo = macho.tool("lipo")
        for relative in binaries:
            merged = os.path.join(destination, relative)
            inputs = " ".join(f'"{os.path.join(bundle, relative)}"' for bundle in bundles)
            self.run(f'"{lipo}" -create {inputs} -output "{merged}"')
            architectures = macho.output(f'"{lipo}" -archs "{merged}"').split()
            if len(architectures) != len(bundles):
                raise ConanException(f"{merged} came out with {', '.join(architectures) or 'no architecture'} "
                                     f"from {len(bundles)} slices; two slices built for the same architecture "
                                     "cannot be told apart")
            self._verify(merged)

    def _sign_target(self, name):
        if name != "application":
            raise ConanException(f"sign:{name} is not something this toolchain signs; it signs application")
        declared = self.declared.get("application", {})
        executable = self._declared_context().get("executable")
        if not executable or not os.path.isfile(executable):
            raise ConanException(f"sign:application found no executable at {executable}; build:application has "
                                 "to run before it")
        entitlements = declared.get("entitlements")
        macho = MachO(self)
        if not entitlements:
            macho.sign(executable)
            return
        listed = os.path.join(self.port_root, entitlements)
        macho.sign(executable, listed)
        waived = self.declared_waivers()
        if "entitlements" in waived:
            self.output.warning(f"{executable}: entitlements not read back: {waived['entitlements']}")
            return
        with open(listed, "rb") as handle:
            wanted = plistlib.load(handle)
        problems = macho.entitlement_problems(wanted, macho.entitlements(executable))
        if problems:
            raise ConanException(f"{executable} was signed without what {entitlements} declares: "
                                 + "; ".join(problems))

    def declared_runtime(self):
        stage = self.declared.get("stage", {})
        files = stage.get("runtime") or {}
        if not files:
            return None, {}
        package = stage.get("runtime-from")
        if not package:
            raise ConanException(
                f"{self.name} declares [stage.runtime] and no runtime-from under [stage]; nothing says which "
                "package the runtime libraries it names are copied from")
        return self._components(package).libdirs[0], files

    def _application_plist(self, name, declared):
        described = dict(declared.get("plist", {}))
        scheme = described.pop("url-scheme", None)
        info = {}
        written = declared.get("plist-file")
        if written:
            path = os.path.join(self.port_root, written)
            if not os.path.isfile(path):
                raise ConanException(f"{name} names plist-file {written}, and there is no such file")
            with open(path, "rb") as handle:
                info = plistlib.load(handle)
        info.update(described)
        executable = info.get("CFBundleExecutable")
        if executable is not None and executable != name:
            raise ConanException(
                f"{written or 'the declared plist'} gives CFBundleExecutable {executable}, and the application "
                f"built is {name}; the bundle would not start")
        derived = {
            "CFBundleName": name,
            "CFBundleDisplayName": name,
            "CFBundleExecutable": name,
            "CFBundleVersion": str(self.version),
            "CFBundleShortVersionString": str(self.version),
            "MinimumOSVersion": str(self.settings.os.version),
        }
        for key, value in derived.items():
            info.setdefault(key, value)
        identifier = info.get("CFBundleIdentifier", name)
        if scheme:
            info["CFBundleURLTypes"] = [{"CFBundleURLName": identifier, "CFBundleURLSchemes": [scheme]}]
        return info

    def _declared_bundle(self, bundle, declared):
        name = declared.get("name")
        context = self._declared_context()
        carried = {}
        for entry in declared.get("bundle", []):
            if not isinstance(entry, dict) or not entry.get("from"):
                raise ConanException(f"{name} bundles {entry!r}; an entry is a table with from and, optionally, "
                                     "into")
            source = self._expand(entry["from"], context)
            if not os.path.isfile(source):
                raise ConanException(f"{name} bundles {source}, and there is no such file")
            into = str(entry.get("into", "Frameworks")).strip("/")
            destination = os.path.join(bundle, into, os.path.basename(source))
            os.makedirs(os.path.dirname(destination), exist_ok=True)
            shutil.copy2(source, destination)
            if MachO.is_macho(destination):
                carried[destination] = f"@executable_path/{into}/{os.path.basename(source)}"
        return carried

    def _write_application_plist(self, bundle, name, declared):
        info = self._application_plist(name, declared)
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
    MAGIC = (b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe")

    def __init__(self, conanfile):
        self._conanfile = conanfile

    def tool(self, name):
        return XCRun(self._conanfile).find(name)

    def output(self, command):
        captured = StringIO()
        self._conanfile.run(command, stdout=captured)
        return captured.getvalue()

    @classmethod
    def merge_plan(cls, bundles):
        listings = []
        for bundle in bundles:
            files = {}
            for folder, _, names in os.walk(bundle):
                for name in names:
                    path = os.path.join(folder, name)
                    if not os.path.islink(path):
                        files[os.path.relpath(path, bundle)] = path
            listings.append(files)
        problems = []
        every = set().union(*listings)
        partial = sorted(relative for relative in every if any(relative not in listing for listing in listings))
        if partial:
            problems.append("present in only some slices: " + ", ".join(partial))
        binaries = []
        for relative in sorted(every - set(partial)):
            paths = [listing[relative] for listing in listings]
            kinds = [cls.is_macho(path) for path in paths]
            if all(kinds):
                binaries.append(relative)
            elif any(kinds):
                problems.append(f"{relative} is a Mach-O in some slices and not in others")
            else:
                contents = set()
                for path in paths:
                    with open(path, "rb") as handle:
                        contents.add(handle.read())
                if len(contents) > 1:
                    problems.append(cls._difference(relative, bundles, paths))
        return binaries, problems

    @staticmethod
    def _difference(relative, bundles, paths):
        slices = [os.path.basename(os.path.dirname(bundle)) for bundle in bundles]
        if not relative.endswith(".plist"):
            return f"{relative} differs between slices"
        try:
            loaded = []
            for path in paths:
                with open(path, "rb") as handle:
                    loaded.append(plistlib.load(handle))
        except Exception:
            return f"{relative} differs between slices"
        keys = sorted({key for plist in loaded for key in plist
                       if len({repr(other.get(key)) for other in loaded}) > 1})
        described = "; ".join("{} ({})".format(key, ", ".join(f"{slice_name}: {plist.get(key)!r}"
                                                               for slice_name, plist in zip(slices, loaded)))
                              for key in keys)
        advice = ""
        if "MinimumOSVersion" in keys:
            advice = ". Each slice derives MinimumOSVersion from its own target; pin it in plist-file"
        return f"{relative} differs between slices in {described}{advice}"

    @classmethod
    def is_macho(cls, path):
        if os.path.islink(path) or not os.path.isfile(path):
            return False
        with open(path, "rb") as candidate:
            return candidate.read(4) in cls.MAGIC

    ARM, ARM64 = 12, 0x0100000C
    EXECUTABLE = 2
    CODE = 0x80000000 | 0x400
    THUMB_DEFINITION = 0x0008
    SMALLEST_ARM64_PAGEZERO = 1 << 32
    WAIVABLE = ("thumb-interworking", "pagezero", "entitlements", "input-minimum")
    CPU_TYPES = {"armv7": 12, "armv7s": 12, "armv8": 0x0100000C, "arm64": 0x0100000C}

    @classmethod
    def recorded_minimums(cls, path, cputype):
        with open(path, "rb") as handle:
            if handle.read(8) != b"!<arch>\n":
                return [(None, minimum) for minimum in cls._minimums_at(handle, 0, cputype)]
            found = []
            at = 8
            while True:
                handle.seek(at)
                header = handle.read(60)
                if len(header) < 60:
                    return found
                name, size = header[:16].decode().strip(), int(header[48:58].decode().strip())
                body = at + 60
                if name.startswith("#1/"):
                    length = int(name[3:])
                    handle.seek(body)
                    name = handle.read(length).rstrip(b"\0").decode(errors="replace")
                    start = body + length
                else:
                    start = body
                if not name.startswith("__.SYMDEF"):
                    found += [(name, minimum) for minimum in cls._minimums_at(handle, start, cputype)]
                at = body + size + (size & 1)

    @classmethod
    def _minimums_at(cls, handle, base, cputype):
        handle.seek(base)
        magic = handle.read(4)
        if magic == b"\xca\xfe\xba\xbe":
            count = struct.unpack(">I", handle.read(4))[0]
            slices = [struct.unpack(">iiIII", handle.read(20)) for _ in range(count)]
            return [minimum for kind, _, offset, _, _ in slices if kind == cputype
                    for minimum in cls._minimums_at(handle, base + offset, cputype)]
        if magic not in (b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe"):
            return []
        kind, _, _, ncmds, sizeofcmds = struct.unpack("<iiIII", handle.read(20))
        if kind != cputype:
            return []
        handle.seek(base + (32 if magic == b"\xcf\xfa\xed\xfe" else 28))
        commands = handle.read(sizeofcmds)
        at = 0
        for _ in range(ncmds):
            command, size = struct.unpack_from("<II", commands, at)
            if command == 0x25:
                return [struct.unpack_from("<I", commands, at + 8)[0]]
            if command == 0x32:
                return [struct.unpack_from("<I", commands, at + 12)[0]]
            at += size
        return [None]

    @staticmethod
    def version_text(encoded):
        return "none" if encoded is None else f"{encoded >> 16}.{(encoded >> 8) & 0xFF}" + (
            f".{encoded & 0xFF}" if encoded & 0xFF else "")

    @staticmethod
    def encoded_version(text):
        parts = [int(part) for part in str(text).split(".")] + [0, 0]
        return (parts[0] << 16) | (parts[1] << 8) | parts[2]

    @classmethod
    def minimum_problems(cls, path, cputype, target, label):
        wanted = cls.encoded_version(target)
        problems = []
        for member, minimum in cls.recorded_minimums(path, cputype):
            if minimum == wanted:
                continue
            named = f"{label}({member})" if member else label
            if minimum is None:
                problems.append(f"{named} records no minimum OS version, so nothing says it was built for {target}")
            elif minimum > wanted:
                problems.append(f"{named} was built for iOS {cls.version_text(minimum)}, newer than the {target} "
                                "this links for")
            else:
                problems.append(f"{named} was built for iOS {cls.version_text(minimum)} instead of {target}, which "
                                "means it was compiled without the target's flags")
        return problems

    @classmethod
    def images(cls, data):
        magic = data[:4]
        if magic in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
            wide = magic == b"\xca\xfe\xba\xbf"
            count = struct.unpack_from(">I", data, 4)[0]
            entry, layout = (32, ">iiQQI") if wide else (20, ">iiIII")
            return [cls._image(data, struct.unpack_from(layout, data, 8 + index * entry)[2])
                    for index in range(count)]
        return [cls._image(data, 0)]

    @classmethod
    def _image(cls, data, base):
        magic = data[base:base + 4]
        if magic not in (b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe"):
            raise ConanException(f"there is no Mach-O image at offset {base}")
        wide = magic == b"\xcf\xfa\xed\xfe"
        cputype, _, filetype, ncmds, _, _ = struct.unpack_from("<iiIIII", data, base + 4)
        image = {"base": base, "cputype": cputype, "filetype": filetype, "wide": wide,
                 "segments": [], "sections": [], "symtab": None, "rebase": None, "local": None}
        at = base + (32 if wide else 28)
        for _ in range(ncmds):
            command, size = struct.unpack_from("<II", data, at)
            if command in (0x1, 0x19):
                if command == 0x19:
                    name, vmaddr, vmsize, fileoff, _, _, _, nsects, _ = struct.unpack_from("<16sQQQQiiII", data, at + 8)
                    first, entry, layout = at + 72, 80, "<16s16sQQIIIIIIII"
                else:
                    name, vmaddr, vmsize, fileoff, _, _, _, nsects, _ = struct.unpack_from("<16sIIIIiiII", data, at + 8)
                    first, entry, layout = at + 56, 68, "<16s16sIIIIIIIIII"
                image["segments"].append({"name": name.rstrip(b"\0").decode(), "vmaddr": vmaddr,
                                          "vmsize": vmsize, "fileoff": fileoff})
                for index in range(nsects):
                    fields = struct.unpack_from(layout, data, first + index * entry)
                    image["sections"].append({"name": fields[0].rstrip(b"\0").decode(), "addr": fields[2],
                                              "size": fields[3], "flags": fields[8]})
            elif command == 0x2:
                image["symtab"] = struct.unpack_from("<IIII", data, at + 8)
            elif command in (0x22, 0x80000022):
                image["rebase"] = struct.unpack_from("<II", data, at + 8)
            elif command == 0xB:
                image["local"] = struct.unpack_from("<II", data, at + 72)
            at += size
        return image

    @staticmethod
    def _uleb(data, at):
        value, shift = 0, 0
        while True:
            byte = data[at]
            at += 1
            value |= (byte & 0x7F) << shift
            shift += 7
            if byte < 0x80:
                return value, at

    @classmethod
    def rebased_slots(cls, data, image):
        segments = image["segments"]
        slots = []
        if image["rebase"] and image["rebase"][1]:
            offset, size = image["rebase"]
            at, end = image["base"] + offset, image["base"] + offset + size
            kind, segment, address, width = 1, 0, 0, 8 if image["wide"] else 4
            while at < end:
                byte = data[at]
                at += 1
                opcode, immediate = byte & 0xF0, byte & 0x0F
                if opcode == 0x00:
                    break
                if opcode == 0x10:
                    kind = immediate
                elif opcode == 0x20:
                    segment = immediate
                    address, at = cls._uleb(data, at)
                elif opcode == 0x30:
                    step, at = cls._uleb(data, at)
                    address += step
                elif opcode == 0x40:
                    address += immediate * width
                elif opcode in (0x50, 0x60, 0x70, 0x80):
                    if opcode == 0x50:
                        times, skip = immediate, 0
                    elif opcode == 0x60:
                        times, at = cls._uleb(data, at)
                        skip = 0
                    elif opcode == 0x70:
                        times = 1
                        skip, at = cls._uleb(data, at)
                    else:
                        times, at = cls._uleb(data, at)
                        skip, at = cls._uleb(data, at)
                    for _ in range(times):
                        if kind in (1, 2):
                            slots.append((segments[segment]["vmaddr"] + address,
                                          image["base"] + segments[segment]["fileoff"] + address))
                        address += width + skip
                else:
                    raise ConanException(f"rebase opcode {byte:#x} is not one this toolchain reads")
        elif image["local"] and image["local"][1] and not image["wide"]:
            offset, count = image["local"]
            relocated = segments[0]["vmaddr"]
            for index in range(count):
                address, info = struct.unpack_from("<II", data, image["base"] + offset + index * 8)
                if address & 0x80000000:
                    kind, length, address = (address >> 24) & 0xF, (address >> 28) & 0x3, address & 0xFFFFFF
                else:
                    kind, length = (info >> 28) & 0xF, (info >> 25) & 0x3
                if kind != 0 or length != 2:
                    continue
                vmaddr = relocated + address
                for described in segments:
                    if described["vmaddr"] <= vmaddr < described["vmaddr"] + described["vmsize"]:
                        slots.append((vmaddr, image["base"] + described["fileoff"] + vmaddr - described["vmaddr"]))
        return slots

    @classmethod
    def code_symbols(cls, data, image):
        if not image["symtab"]:
            return {}
        symoff, nsyms, stroff, _ = image["symtab"]
        code = {index + 1 for index, section in enumerate(image["sections"]) if section["flags"] & cls.CODE}
        found = {}
        for index in range(nsyms):
            strx, kind, section, desc, value = struct.unpack_from("<IBBHI", data, image["base"] + symoff + index * 12)
            if kind & 0xE0 or (kind & 0x0E) != 0x0E or section not in code:
                continue
            end = data.index(b"\0", image["base"] + stroff + strx)
            name = data[image["base"] + stroff + strx:end].decode(errors="replace")
            found.setdefault(value & ~1, set()).add((bool(desc & cls.THUMB_DEFINITION), name))
        return found

    @classmethod
    def interworking_problems(cls, path):
        with open(path, "rb") as handle:
            data = handle.read()
        problems, checked = [], 0
        for image in cls.images(data):
            if image["cputype"] != cls.ARM:
                continue
            symbols = cls.code_symbols(data, image)
            for slot, position in cls.rebased_slots(data, image):
                pointer = struct.unpack_from("<I", data, position)[0]
                described = symbols.get(pointer & ~1)
                if not described or len({thumb for thumb, _ in described}) != 1:
                    continue
                checked += 1
                thumb = next(iter(described))[0]
                name = sorted(name for _, name in described)[0]
                if thumb and not pointer & 1:
                    problems.append(f"the pointer at {slot:#x} to Thumb function {name} lacks bit 0, so a call "
                                    "through it enters Thumb code in ARM state; the linker dropped it")
                elif not thumb and pointer & 1:
                    problems.append(f"the pointer at {slot:#x} to ARM function {name} has bit 0 set, so a call "
                                    "through it enters ARM code in Thumb state; something rewrote it after the link")
        return problems, checked

    @classmethod
    def pagezero_problems(cls, path):
        with open(path, "rb") as handle:
            data = handle.read()
        problems = []
        for image in cls.images(data):
            if image["filetype"] != cls.EXECUTABLE or image["cputype"] not in (cls.ARM, cls.ARM64):
                continue
            named = {segment["name"]: segment for segment in image["segments"]}
            zero, text = named.get("__PAGEZERO"), named.get("__TEXT")
            if zero is None or text is None:
                problems.append("an executable without __PAGEZERO and __TEXT does not map the way iOS expects")
            elif image["cputype"] == cls.ARM64 and zero["vmsize"] < cls.SMALLEST_ARM64_PAGEZERO:
                problems.append(f"the arm64 __PAGEZERO is {zero['vmsize']:#x}, and a 64-bit iOS executable needs "
                                f"at least {cls.SMALLEST_ARM64_PAGEZERO:#x}; nothing should pass -pagezero_size")
            elif image["cputype"] == cls.ARM and text["vmaddr"] != zero["vmaddr"] + zero["vmsize"]:
                problems.append(f"__PAGEZERO ends at {zero['vmaddr'] + zero['vmsize']:#x} and __TEXT starts at "
                                f"{text['vmaddr']:#x}; the gap is what a post-link edit of the segment leaves")
        return problems

    @staticmethod
    def entitlement_problems(declared, signed):
        return [f"{key} is declared as {value!r} and the signature carries "
                f"{signed[key]!r}" if key in signed else f"{key} is declared and the signature does not carry it"
                for key, value in declared.items() if signed.get(key, object()) != value]

    def entitlements(self, binary):
        captured = StringIO()
        if self._conanfile.run(f'ldid -e "{binary}"', stdout=captured, ignore_errors=True):
            return {}
        text = captured.getvalue().strip()
        return plistlib.loads(text.encode()) if text else {}

    def verify(self, binary, waived):
        problems = []
        if "thumb-interworking" in waived:
            self._conanfile.output.warning(f"{binary}: thumb-interworking not checked: {waived['thumb-interworking']}")
        else:
            found, checked = self.interworking_problems(binary)
            problems += found
            self._conanfile.output.info(f"{os.path.basename(binary)}: {checked} rebased code pointers match the "
                                        "mode of the function they name")
        if "pagezero" in waived:
            self._conanfile.output.warning(f"{binary}: pagezero not checked: {waived['pagezero']}")
        else:
            problems += self.pagezero_problems(binary)
        if problems:
            shown = "; ".join(problems[:5]) + (f"; and {len(problems) - 5} more" if len(problems) > 5 else "")
            raise ConanException(f"{binary} is not what the platform runs: {shown}")

    def binaries_under(self, root):
        found = []
        for folder, _, names in os.walk(root):
            for name in names:
                path = os.path.join(folder, name)
                if self.is_macho(path):
                    found.append(path)
        return sorted(found)

    @staticmethod
    def library_stem(reference):
        name = os.path.basename(reference)
        return name.split(".", 1)[0].replace("librev-", "lib")

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
