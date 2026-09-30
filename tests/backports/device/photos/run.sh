#!/bin/sh
# tests/backports/device/photos/run.sh -- the three Photos device programs, built from THIS tree's own
# Photos sources, run on a device, with their figures printed.
#
#     sh tests/backports/device/photos/run.sh [options] [PROGRAM...]
#
# Why this file exists: facts/Photos/Changes.md names photoschanges8.m, photosdata9.m and
# photosalbums8.m and quotes their check counts, and nothing in the tree ran them. The numbers were
# real when they were taken (an iPad 2 running 6.1.3, 2026-09-23 and 2026-09-24) and there was no path
# left to take them again, which is how a facts page ends up quoting a run nobody can repeat. This is
# that path: it builds each program from the sources beside it, so a run measures the tree it is run
# from and not a package that was installed weeks ago, and it prints what each program reported.
#
#   photosalbums8   a process of its own, denied the photo library by the release; it reads and writes
#                   nothing. Safe on any device, so it is the one this runs without being asked.
#   photoschanges8  an application (photoschanges8-Info.plist): it registers change observers and adds
#                   three 8-by-8 blue fixtures to the saved photos on every run.
#   photosdata9     an application (photosdata9-Info.plist): the iOS 9 creation request, the asset
#                   resources and the resource manager, over the same fixtures.
#   control         this directory's own negative control; it must FAIL, and the run says so.
#
# The two applications WRITE to the photo library of the device they run on, and the photo library of
# a device that is not the iPad 2 is the owner's. So a program that writes is refused unless the
# device is the iPad 2 (the one that holds the fleet's own fixtures, albums named CharonPhotosProbe)
# or PHOTOS_ALLOW_WRITE=1 says the device's library is a test library. Nothing is read to decide this:
# the device's name decides, so the check cannot itself touch the owner's data.
#
# Options:
#   --release R     the release to build and run for (default 6.1.3, the release the facts quote)
#   --device NAME   -d for `xmake device`: NAME picks device.NAME.env (default: device.env, the 4S)
#   --build-only    build and link everything, run nothing
#   --control       also run the negative control, and require it to fail
#   --allow-write   as PHOTOS_ALLOW_WRITE=1
#
# Environment (all optional; the defaults are what the shared xmake store holds):
#   PHOTOS_CC, PHOTOS_LD, PHOTOS_SDK    the toolchain; default the store's llvm, ld64 and iphoneos-sdk
#   PHOTOS_BUILD                       where the builds and the reports go
#                                      (default <worktree>/.agent-work/runs/photos-device)
#
# The claim is the operator's, not this script's: export CHARON_DEVICE_HOLDER and claim first
# (`xmake device -d NAME --minutes=30 claim`); this script refuses a device held by someone else and
# says so. Nothing here installs a package: the port's sources are compiled into each program, so the
# canon on the device (org.charon.apple-backports), which belongs to everybody, is left alone.
#
# Exits 0 only when every program that ran reported a figure with no failed check, and, with
# --control, when the control reported at least one.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../../../.." && pwd)
release=6.1.3
device_name=""
build_only=0
want_control=0
allow_write=${PHOTOS_ALLOW_WRITE:-0}
programs=""

while [ $# -gt 0 ]; do
    case $1 in
        --release) release=$2; shift 2 ;;
        --device) device_name=$2; shift 2 ;;
        --build-only) build_only=1; shift ;;
        --control) want_control=1; shift ;;
        --allow-write) allow_write=1; shift ;;
        --) shift; programs="$*"; break ;;
        -*) echo "run.sh: unknown option $1" >&2; exit 2 ;;
        *) programs="$programs $1"; shift ;;
    esac
done
[ -n "$programs" ] || programs="photosalbums8 photoschanges8 photosdata9"
# No device is named here on purpose: an empty -d is the transport's own default (device.env, the
# device that is attached), and a run must not silently pick a different one. The write guard below
# refuses a program that writes unless the device IS the iPad 2 or the operator says otherwise.

store=$HOME/.xmake/packages
pick() { ls -d "$store/$1/$2"/*/ 2>/dev/null | head -1; }
: "${PHOTOS_CC:=$(ls "$(pick l/llvm 23.1.1)"bin/clang 2>/dev/null | head -1)}"
: "${PHOTOS_LD:=$(ls "$(pick l/ld64 956.6)"bin/ld 2>/dev/null | head -1)}"
if [ -z "${PHOTOS_SDK:-}" ]; then
    for folder in "$store"/i/iphoneos-sdk/16.4/*/; do
        sdk="$folder"'Developer.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS16.4.sdk'
        [ -d "$sdk" ] && PHOTOS_SDK=$sdk && break
    done
    : "${PHOTOS_SDK:=$(pick i/iphoneos-sdk 16.4)}"
fi
for tool in "$PHOTOS_CC" "$PHOTOS_LD" "$PHOTOS_SDK"; do
    [ -e "$tool" ] || { echo "run.sh: $tool is not there; set PHOTOS_CC, PHOTOS_LD and PHOTOS_SDK" >&2; exit 1; }
done
command -v ldid >/dev/null 2>&1 || { echo "run.sh: ldid is not on PATH (brew install ldid)" >&2; exit 1; }

out=${PHOTOS_BUILD:-$root/.agent-work/runs/photos-device}
mkdir -p "$out"
photos=$root/packages/a/apple-backports/Photos
triple=armv7-apple-ios$release
# The flags the library is built with (modules/apple/backports.lua:1118, :473), not a private set: the
# sources below must be compiled exactly as the dylib compiles them, or a run measures another build.
cflags="-target $triple -isysroot $PHOTOS_SDK -isystem $PHOTOS_SDK/usr/include -fobjc-arc -Os -g0 -Wall
        -Wno-unguarded-availability-new -Wno-incompatible-sysroot -I$photos -I$here/.."
# The frameworks the library itself is built against, copied from the declaration in
# modules/apple/backports.lua:66 (PhotosBackports) rather than gathered from the imports, so the two
# cannot drift. Photos and PhotosUI are NOT among them: no release below 13 carries them, which is
# why the port carries these classes at all. FoundationBackports is not linked either: at 6.1.3 the
# release's own Foundation is the one, and linking the port's would put two Foundations in the process.
frameworks="-framework AssetsLibrary -framework AVFoundation -framework CoreLocation -framework CoreGraphics
            -framework ImageIO -framework MobileCoreServices -framework UIKit -framework Foundation"

# The band's own sources. Which band an object lands in is its registry minimum, not its file name
# (modules/apple/backports.lua:2014 -- minimums() reads entry.minimum and never the status, and
# :2508 band_ranges), which is why PHChangeRequest13.m is in the 6.0 band: registry/Photos/ios13.json
# gives PHChangeRequest minimum 6.0, and PHAssetCollectionChangeRequest8.m has it for a superclass.
# The 13.0 and 14.0 objects proper are left out, and a program that needs one cannot link -- which is
# the failure a program for those releases is written against.
band8="CharonPhotosStore.m CharonPhotosTransaction.m PHPhotosErrorDomain8.m PHObject8.m PHPhotoLibrary.m
       PHCollection8.m PHChange8.m PHFetchResult8.m PHFetchOptions8.m PHAsset8.m PHImageManager8.m
       PHAssetChangeRequest8.m PHAssetCollectionChangeRequest8.m PHChangeRequest13.m"
band9="PHAssetResource9.m PHAssetResourceManager9.m PHAssetCreationRequest9.m"

compile_one() { # $1 source, $2 object
    # shellcheck disable=SC2086
    $PHOTOS_CC $cflags -c "$1" -o "$2"
}

link_one() { # $1 output, rest: objects
    output=$1
    shift
    # shellcheck disable=SC2086
    $PHOTOS_CC -target "$triple" -isysroot "$PHOTOS_SDK" -fuse-ld="$PHOTOS_LD" -fobjc-arc \
        -Wl,-rename_section,__DATA,__objc_catlist,__DATA,__charon_catlist \
        -o "$output" "$@" $frameworks $extra
    ldid -S "$output" >/dev/null 2>&1 || echo "run.sh: ldid could not sign $output" >&2
}

# $1 program name, $2 the sources' band (8 or 9), $3 process|app, $4 the plist's executable name
build() {
    name=$1
    band=$2
    kind=$3
    executable=$4
    # photosdata9.m writes its own test videos with AVAssetWriter and hands AVFoundation the pixel
    # buffer pool, so it links CoreMedia and CoreVideo as well; the other two programs need nothing
    # the library does not already name.
    extra=""
    [ "$name" = photosdata9 ] && extra="-framework CoreMedia -framework CoreVideo"
    objects="$out/$name.objects"
    rm -rf "$objects"
    mkdir -p "$objects"
    index=0
    for source in $band8 $([ "$band" = 9 ] && echo "$band9"); do
        index=$((index + 1))
        compile_one "$photos/$source" "$objects/$index.o"
    done
    compile_one "$root/packages/a/apple-backports/attach.c" "$objects/attach.o"
    compile_one "$here/../check.m" "$objects/check.o"
    # A program of the device's own directory, or this directory's control, which is the only one
    # written here.
    if [ -f "$here/$name.m" ]; then main=$here/$name.m; else main=$here/../$name.m; fi
    compile_one "$main" "$objects/main.o"
    case $kind in
        process)
            link_one "$out/$name" "$objects"/*.o
            ;;
        app)
            bundle=$out/$executable.app
            rm -rf "$bundle"
            mkdir -p "$bundle"
            link_one "$bundle/$executable" "$objects"/*.o
            cp "$here/../$name-Info.plist" "$bundle/Info.plist"
            ;;
    esac
    echo "built $name for iOS $release ($(ls "$objects" | wc -l | tr -d ' ') objects)"
}

declare -A bundles 2>/dev/null || true
case_ok() { case " $programs " in *" $1 "*) return 0 ;; *) return 1 ;; esac }

built=""
for name in $programs; do
    case $name in
        photosalbums8) build "$name" 8 process photosalbums8 ;;
        photoschanges8) build "$name" 8 app photoschanges ;;
        photosdata9) build "$name" 9 app photosdata ;;
        control) build "$name" 8 process control ;;
        *) echo "run.sh: $name is not one of photosalbums8, photoschanges8, photosdata9, control" >&2; exit 2 ;;
    esac
    built="$built $name"
done
[ "$build_only" = 1 ] && { echo "build-only: nothing was run"; exit 0; }
[ "$want_control" = 1 ] && built="$built control"

# The transport. Every command below goes through the driver's own device module, which checks the
# claim, the tunnel and the UDID; a raw ssh would check none of them and "permission denied" would
# then mean the wrong device.
[ -n "${CHARON_DEVICE_HOLDER:-}" ] || { echo "run.sh: export CHARON_DEVICE_HOLDER=<band> and claim the device first (xmake device ${device_name:+-d $device_name} --minutes=30 claim)" >&2; exit 1; }
device_flag=""
[ -n "$device_name" ] && device_flag="-d $device_name"
xmake device $device_flag list 2>&1 | sed 's/^/  /'

remote_dir=/private/var/backports
run_device() { xmake device $device_flag -s 300 run "$1"; }
copy() { CHARON_ROOT=$root xmake l "$here/copy.lua" "$1" "$2" >/dev/null; }
fetch() { CHARON_ROOT=$root xmake l "$here/copy.lua" "$1" "$2" --fetch >/dev/null; }

failed=0
report() { # $1 program, $2 report path on this host
    name=$1
    report=$2
    if [ ! -s "$report" ]; then
        echo "$name: NO REPORT -- the program wrote nothing to $remote_dir, so nothing about it is known"
        failed=1
        return
    fi
    sed 's/^/  | /' "$report"
    if ! grep -Eq '^[0-9]+ checks, [0-9]+ failed' "$report"; then
        echo "$name: no figure line in the report"
        failed=1
        return
    fi
    figure=$(grep -E '^[0-9]+ checks, [0-9]+ failed' "$report" | tail -1)
    count=$(echo "$figure" | awk '{print $1}')
    bad=$(echo "$figure" | awk '{print $3}')
    grep -a '^FAIL' "$report" | sed 's/^/  FAILED /' || true
    echo "$name: $figure"
    # The control is the one program whose failure is the verdict: it is run with expect_failure set,
    # and then only a report that says 0 failed is a failure of the run.
    if [ "$name" = control ]; then
        [ "$bad" -ne 0 ] || failed=1
        return
    fi
    [ "$bad" -eq 0 ] || failed=1
    [ "$count" -gt 0 ] || failed=1
}

for name in $built; do
    case $name in
        photosalbums8|control)
            copy "$out/$name" "$remote_dir/$name"
            run_device "chmod +x $remote_dir/$name; $remote_dir/$name $remote_dir/$name.log; echo \"exit=\$?\""
            fetch "$remote_dir/$name.log" "$out/$name-$device_name.report"
            report "$name" "$out/$name-$device_name.report"
            ;;
        photoschanges8|photosdata9)
            if [ "$allow_write" != 1 ] && [ "$device_name" != ipad2 ]; then
                which=${device_name:-the default device}
                echo "$name: REFUSED -- it writes to the photo library, and $which's library is the owner's."
                echo "  Run it on the iPad 2 (the one holding the fleet's CharonPhotosProbe fixtures), or set PHOTOS_ALLOW_WRITE=1"
                echo "  if that device's library is a test library. Nothing was pushed and nothing ran."
                failed=1
                continue
            fi
            executable=$(echo "$name" | sed 's/photoschanges8/photoschanges/; s/photosdata9/photosdata/')
            copy "$out/$executable.app" "/Applications/$executable.app"
            run_device "uicache -p /Applications/$executable.app; sblaunch local.charon.backports.${executable}"
            echo "$name: launched; the report is $remote_dir/$name.log when it writes $remote_dir/$name.done"
            # The applications write their report to a file, not to the launch's stdout, because a
            # process SpringBoard started has no terminal to print to. Wait for the .done marker the
            # program writes itself, bounded, and fetch the log it left.
            waited=0
            while [ "$waited" -lt 60 ]; do
                if run_device "[ -f $remote_dir/$name.done ] && echo done" 2>/dev/null | grep -q done; then
                    break
                fi
                waited=$((waited + 1))
                sleep 2
            done
            if [ "$waited" -ge 60 ]; then
                echo "$name: the program did not write $remote_dir/$name.done within 120s; the log it did write follows"
            fi
            fetch "$remote_dir/$name.log" "$out/$name-$device_name.report"
            report "$name" "$out/$name-$device_name.report"
            ;;
    esac
done

# The control is the last thing said, because it is what makes the figures above mean anything.
for name in $built; do
    [ "$name" = control ] || continue
    if grep -Eq '^[0-9]+ checks, [1-9][0-9]* failed' "$out/$name-$device_name.report" 2>/dev/null; then
        echo "control: it failed, so a failing check in a program above would have been seen"
    else
        echo "control: IT DID NOT FAIL. Either this device does not deny the process the release denies, which"
        echo "  makes photosalbums8's own check vacuous, or the report is not the control's. The figures"
        echo "  above are not evidence until this is."
        failed=1
    fi
done

echo "reports and builds: $out"
[ "$failed" -eq 0 ] && echo "photos device: every program that ran passed" || echo "photos device: FAILED"
exit $failed
