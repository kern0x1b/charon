from io import StringIO

from conan import ConanFile
from conan.errors import ConanException
from conan.tools.layout import basic_layout


class TestPackage(ConanFile):
    settings = "os", "arch", "compiler", "build_type"
    generators = "VirtualBuildEnv"
    test_type = "explicit"

    def build_requirements(self):
        self.tool_requires(self.tested_reference_str)

    def layout(self):
        basic_layout(self)

    def test(self):
        output = StringIO()
        self.run("arm-apple-darwin11-ld -v", stdout=output, stderr=output, env="conanbuild")
        expected = f"ld64-{self.dependencies.build['ld64'].ref.version}"
        if expected not in output.getvalue():
            raise ConanException(f"arm-apple-darwin11-ld is not {expected}: {output.getvalue()}")
