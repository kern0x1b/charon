import os

from conan.api.model import Remote, LOCAL_RECIPES_INDEX
from conan.api.output import ConanOutput
from conan.cli.command import conan_command
from conan.errors import ConanException


@conan_command(group="ios6")
def ios6_remote(conan_api, parser, *args):
    """
    Serve a checkout's recipes and keep it ahead of the general remotes.
    """
    parser.add_argument("name", help="name to serve the checkout under")
    parser.add_argument("path", help="checkout holding a recipes folder")
    parsed = parser.parse_args(*args)

    path = os.path.abspath(parsed.path)
    if not os.path.isdir(os.path.join(path, "recipes")):
        raise ConanException(f"{path} holds no recipes to serve")

    known = [remote.name for remote in conan_api.remotes.list(only_enabled=False)]
    if parsed.name in known:
        conan_api.remotes.update(parsed.name, url=path)
    else:
        conan_api.remotes.add(Remote(parsed.name, path, remote_type=LOCAL_RECIPES_INDEX))

    served = [remote.name for remote in conan_api.remotes.list(only_enabled=False)
              if remote.remote_type == LOCAL_RECIPES_INDEX]
    for index, name in enumerate(served):
        conan_api.remotes.update(name, index=index)

    ConanOutput().success(f"{parsed.name} serves {path}; "
                          f"{', '.join(served)} come before the general remotes")
