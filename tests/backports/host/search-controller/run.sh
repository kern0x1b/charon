#!/bin/sh
# run.sh: a differential of UISearchController's iOS 16 properties (the search bar placement, the scope bar activation and the suggestions'
# flag) and the iOS 13 scope bar flag, the port against the host, in two processes. SEARCH_CONTROLLER_PORT_SOURCES replaces the port's
# files, so a planted wrong port can be run as a control: it must fail.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
. "$here/../../common/runs.sh" "$here"
uikit=$here/../../../../packages/a/apple-backports/UIKit
build=${SEARCH_CONTROLLER_BUILD:-$(runs_fresh charon-search-controller)}
. "$here/../../common/twoprocess.sh"
if [ -n "${SEARCH_CONTROLLER_PORT_SOURCES:-}" ]; then
    set -- $SEARCH_CONTROLLER_PORT_SOURCES
else
    set -- "$uikit/UISearchController.m" "$uikit/UISearchController+ScopeBar.m" "$uikit/UINavigationItem+SearchController.m"
fi
if result=$(twoprocess_run "$here/test.m" "$@"); then
    echo "ok search-controller: $result"
else
    echo "FAIL search-controller: $result"
    exit 1
fi
