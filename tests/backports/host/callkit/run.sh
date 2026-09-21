#!/bin/sh
# run.sh — records what the host's CallKit answers for every case of device/callkit-cases.m in a Mac Catalyst binary, holds the port's
# CallKit classes, compiled under names of their own (Charon<name>), to the same records, writes the answers where the device test reads
# them, and tells apart mutants of the port.
#
# The cases keep to what an application reads off the objects themselves. A tool has no VoIP entitlement, so anything that reaches
# callservicesd comes back CXErrorCodeRequestTransactionErrorUnentitled and no delegate method is ever called; the transactions the port
# really performs are held on the device instead.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
device=${DEVICE:-$here/../../device}
callkit=${CALLKIT:-$here/../../../../packages/a/apple-backports/CallKit}
registry=${REGISTRY:-$here/../../../../packages/a/apple-backports/registry/CallKit/ios10.json}
build=${BUILD:-$(mktemp -d)}
mkdir -p "$build"
sdk=$(xcrun --show-sdk-path)
frameworks="-iframework $sdk/System/iOSSupport/System/Library/Frameworks"
common="-target arm64-apple-ios15.0-macabi -isysroot $sdk $frameworks -fobjc-arc -w"
libs="-framework Foundation -framework CoreTelephony -framework AVFoundation"

# Two records the host cannot be an oracle for: its CallKit is that of iOS 14 and later, which dropped the localized name of a
# configuration from its copy and keeps a ringtone as a resolved URL rather than the name it was given. The port implements the iOS 10
# header, where both are plain properties, so these two have to differ - and the test fails if they ever stop, since that would mean the
# host has changed under it.
divergent="configuration.deprecatedName configuration.ringtone"

xcrun clang $common -I"$device" "$here/record.m" "$device/callkit-cases.m" $libs -framework CallKit -o "$build/system"
CALLKIT_RECORDS="$build/system.json" "$build/system"
echo "records: $(python3 -c "import json; print(len(json.load(open('$build/system.json'))))")"

python3 "$here/rename.py" "$registry" "$build/rename.h"

port() {
    dir=$1
    xcrun clang $common -include "$build/rename.h" -I"$device" -I"$callkit" "$here/record.m" "$device/callkit-cases.m" \
        "$dir"/*.m $libs -o "$dir/run"
}
rm -rf "$build/port"; mkdir -p "$build/port"
cp "$callkit"/*.m "$callkit/CharonCallKit.h" "$build/port/"
port "$build/port"
CALLKIT_RECORDS="$build/port.json" "$build/port/run"
python3 "$here/compare.py" "$build/system.json" "$build/port.json" "$divergent"
echo "port: agrees with the system on every record but the two it must not"

# The device reads the host's answers, with the two the host is no oracle for taken from the port itself.
python3 "$here/expectations.py" "$build/system.json" "$build/port.json" "$divergent" "$build/expectations.json"
python3 "$here/../foundation2/embed.py" "$build/expectations.json" "$device/callkit-expectations.h"
sed -i.bak 's/foundation2_expectations/callkit_expectations/' "$device/callkit-expectations.h" && rm -f "$device/callkit-expectations.h.bak"

survived=0
mutant() {
    file=$1; from=$2; to=$3
    rm -rf "$build/mutant"; mkdir -p "$build/mutant"
    cp "$callkit"/*.m "$callkit/CharonCallKit.h" "$build/mutant/"
    python3 "$here/mutate.py" "$build/mutant/$file" "$from" "$to"
    port "$build/mutant"
    rm -f "$build/mutant.json"
    CALLKIT_RECORDS="$build/mutant.json" timeout 60 "$build/mutant/run" > /dev/null 2>&1 || true
    if cmp -s "$build/port.json" "$build/mutant.json"; then echo "MUTANT SURVIVED: $file $from -> $to"; survived=$((survived + 1)); fi
}
mutant CXErrorDomains10.m 'NSErrorDomain const CXErrorDomain = @"com.apple.CallKit.error";' 'NSErrorDomain const CXErrorDomain = @"com.apple.callkit.error";'
mutant CXErrorDomains10.m 'CXErrorDomainIncomingCall = @"com.apple.CallKit.error.incomingcall";' 'CXErrorDomainIncomingCall = @"com.apple.CallKit.error.incomingCall";'
mutant CXErrorDomains10.m 'CXErrorDomainRequestTransaction = @"com.apple.CallKit.error.requesttransaction";' 'CXErrorDomainRequestTransaction = @"com.apple.CallKit.error.transaction";'
mutant CXErrorDomains10.m 'CXErrorDomainCallDirectoryManager = @"com.apple.CallKit.error.calldirectorymanager";' 'CXErrorDomainCallDirectoryManager = @"com.apple.CallKit.error.directorymanager";'
mutant CXProviderConfiguration10.m "_maximumCallGroups = 2;" "_maximumCallGroups = 1;"
mutant CXProviderConfiguration10.m "_maximumCallsPerCallGroup = 5;" "_maximumCallsPerCallGroup = 4;"
mutant CXProviderConfiguration10.m "_includesCallsInRecents = YES;" "_includesCallsInRecents = NO;"
mutant CXProviderConfiguration10.m "_supportsVideo = NO;" "_supportsVideo = YES;"
mutant CXProviderConfiguration10.m "_supportedHandleTypes = [NSSet set];" "_supportedHandleTypes = [NSSet setWithObject:@(1)];"
mutant CXProviderConfiguration10.m "copy->_maximumCallGroups = _maximumCallGroups;" "copy->_maximumCallGroups = 2;"
mutant CXProviderConfiguration10.m "copy->_supportedHandleTypes = [_supportedHandleTypes copy];" "copy->_supportedHandleTypes = [NSSet set];"
mutant CXProviderConfiguration10.m "_localizedName = [localizedName copy];" "_localizedName = nil;"
mutant CXActions10.m "    return 5.0;" "    return 6.0;"
mutant CXActions10.m "    return 600.0;" "    return 60.0;"
mutant CXActions10.m "    return 60.0;" "    return 600.0;"
mutant CXActions10.m "if (_complete || !_charon_provider)" "if (_complete)"
mutant CXActions10.m "_callUUID = [callUUID copy];" "_callUUID = [[NSUUID UUID] copy];"
mutant CXActions10.m "    CXAction *copy = [[[self class] allocWithZone:zone] charon_initWithUUID:_UUID];" "    CXAction *copy = [[[self class] allocWithZone:zone] charon_initWithUUID:[NSUUID UUID]];"
mutant CXActions10.m "copy->_video = _video;" "copy->_video = NO;"
mutant CXActions10.m "copy->_contactIdentifier = [_contactIdentifier copy];" "copy->_contactIdentifier = nil;"
mutant CXActions10.m "    _onHold = onHold;" "    _onHold = !onHold;"
mutant CXActions10.m "    _muted = muted;" "    _muted = !muted;"
mutant CXActions10.m "        _type = type;" "        _type = type + 1;"
mutant CXTransaction10.m "        if (!action.isComplete)
            return NO;
    }
    return YES;" "        (void)action;
    }
    return NO;"
mutant CXTransaction10.m "    [_actions addObject:action];" "    (void)action;"
mutant CXTransaction10.m "        [copy->_actions addObject:[action copy]];" "        [copy->_actions addObject:action];"
mutant CXHandle10.m "return handle.type == _type && (handle.value == _value || [handle.value isEqualToString:_value]);" "return handle.value == _value || [handle.value isEqualToString:_value];"
mutant CXHandle10.m "    return [[CXHandle allocWithZone:zone] initWithType:_type value:_value];" "    return self;"
mutant CXHandle10.m "return (NSUInteger)_type ^ _value.hash;" "return 0x1234;"
mutant CXHandle10.m '[coder encodeObject:_value forKey:@"value"];' '[coder encodeObject:@"other" forKey:@"value"];'
mutant CXCallUpdate10.m "    copy->_supportsHolding = _supportsHolding;" "    copy->_supportsHolding = NO;"
mutant CXCallUpdate10.m "    _localizedCallerName = [localizedCallerName copy];" "    _localizedCallerName = @\"fixed\";"
mutant CXCallController10.m "        _callObserver = [[CXCallObserver alloc] init];" "        _callObserver = nil;"
echo "mutants surviving: $survived"
[ "$survived" -eq 0 ]
