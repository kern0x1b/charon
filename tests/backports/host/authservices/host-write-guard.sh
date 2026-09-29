#!/bin/sh
# host-write-guard.sh -- refuses to start a host differential that would WRITE to this Mac's AutoFill.
#
# On a Mac, ASCredentialIdentityStore's four writing methods change the user's AutoFill state:
#
#   -saveCredentialIdentities:completion:
#   -removeCredentialIdentities:completion:
#   -removeAllCredentialIdentitiesWithCompletion:
#   -replaceCredentialIdentitiesWithIdentities:completion:
#
# A differential that called them to see what they return would be writing to the reviewer's passwords.
# The host side of this family is therefore read-only: -getCredentialIdentityStoreStateWithCompletion:,
# and only because it asks the system what it already holds. The writing half's behaviour is documented
# from the header, not measured on this machine, and the port's own save-then-query runs against the
# port's own store under .agent-work/runs/.
#
# This greps the host probe for the four names and refuses to continue if any of them appears. It is run
# by values.sh before it builds anything, so the refusal happens before a run rather than after one.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
probes="${*:-$(ls "$here"/values.m "$here"/hostshape.c 2>/dev/null)}"
forbidden="saveCredentialIdentities removeCredentialIdentities replaceCredentialIdentitiesWithIdentities removeAllCredentialIdentities"

status=0
for probe in $probes; do
    for name in $forbidden; do
        # A mention in a comment is not a call, and the port's own names carry it in prose; what matters
        # is a selector sent to a host object, which is the name followed by a colon and a send.
        if grep -qE "sel_registerName\(\"$name" "$probe" || grep -qE "performSelector.*$name" "$probe"; then
            echo "FAIL $probe would call -$name on the host, which writes this Mac's AutoFill state"
            status=1
        elif grep -q "$name" "$probe"; then
            echo "note  $probe mentions $name; it must be prose and not a call -- the check above found no send"
        else
            echo "ok    $probe does not name $name"
        fi
    done
done
if [ "$status" -ne 0 ]; then
    echo "FAIL: the host half of this family must not write to the machine's AutoFill state"
    exit 1
fi
echo "ok: the host half names none of the four writing methods"
