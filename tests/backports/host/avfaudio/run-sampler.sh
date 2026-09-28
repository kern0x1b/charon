#!/bin/sh
# What the host's own AVAudioUnitSampler holds for the parameters the port has to reach. The release
# names kAUSamplerParam_Gain 900, _CoarseTuning 901, _FineTuning 902 and _Pan 903 in
# AudioUnitParameters.h and gives no range for any of them, so the range and the mapping are asked of
# the host: a real AVAudioUnitSampler, the v2 property kAudioUnitProperty_ParameterInfo for each id, and
# then the AVFAudio property set and the parameter read, which is the mapping the port must reproduce.
# There is no AudioUnitGetParameterInfo on the SDK - the range is that property, with the parameter id
# as the element, which is the same path the port's own parameter tree walks.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
build=${AVFAUDIO_SAMPLER_BUILD:-${TMPDIR:-/tmp}/charon-avfaudio-sampler}
mkdir -p "$build"
xcrun clang -fobjc-arc -Wall -Wno-deprecated-declarations "$here/sampler.m" \
    -framework Foundation -framework AVFAudio -framework AudioToolbox -o "$build/sampler" 2> "$build/build.err" || {
        echo "FAIL building"; head -8 "$build/build.err"; exit 1; }
"$build/sampler"
