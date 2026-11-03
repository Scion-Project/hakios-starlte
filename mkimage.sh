#!/bin/bash
# The Galaxy S9's boot image for one run: the boot shim, HakiOS's UEFI for starlte (prebuilt/ or a Mu-Silicium/ built
# here) and a payload with everything in it -- the loader, the kernel, the small root image, the command line. Samsung's
# boot loader has no fastboot and Silicium's UEFI no USB gadget, so there is no resident loader to send runs to as on the
# POCO: every run is an image flashed to BOOT, TWRP kept in RECOVERY (README.md, "On the phone"). The run ends by itself after SECS seconds
# (loader_return_after=): the loader keeps the log in Samsung's pstore RAM and restarts the phone.
#
#   devices/starlte/mkimage.sh [-o xnu-starlte.img] [-k kernel] [-r root.apfs] [-l loader.efi] [-s SECS] [-q] [-n] [boot-args...]
#
# The kernel is the S9's own configuration (make starlte_defconfig && make kernel: hakios-kernel). The boot-arguments are
# that configuration's -- the S9's defaults, what has been seen working on the phone (configs/starlte.config, README.md
# "Defaults") -- with the ones given here over them: name=value replaces a default, a new name is added, name= takes a
# default out (tools/hakios-config.py args --with). -n: the given ones alone, no defaults. -v (the kernel's log on the
# screen, for a phone with no other way to show it while it runs) unless -q. The loader is xnuloader/loader.efi (-l
# another), built with the iPhone identity from your own IPSW (make loader): the image is yours, never to be published.
set -e
START=$PWD
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
OUT=$ROOT/xnu-starlte.img K=$ROOT/hakios-kernel RD=$ROOT/userland/root.apfs L=$ROOT/xnuloader/loader.efi SECS=120 VERBOSE=-v
DEFAULTS=1
while getopts o:k:r:l:s:qn opt; do
	case $opt in
	o) OUT=$OPTARG ;; k) K=$OPTARG ;; r) RD=$OPTARG ;; l) L=$OPTARG ;; s) SECS=$OPTARG ;; q) VERBOSE= ;; n) DEFAULTS= ;;
	*) sed -n 2,16p "$0"; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
# (-o, -k and -r as given, from where this was run, before the cd below took effect for them)
abs() { case "$1" in /*) echo "$1" ;; *) echo "$START/$1" ;; esac; }
OUT=$(abs "$OUT") K=$(abs "$K") RD=$(abs "$RD") L=$(abs "$L")
for f in "$L" "$K" "$RD"; do
	[ -f "$f" ] || { echo "mkimage.sh: $f is missing (make loader, make kernel, userland/build.sh)" >&2; exit 1; }
done
ARGS="$*"
if [ -n "$DEFAULTS" ]; then
	# the S9's defaults: the configuration made here if it is this phone's (make starlte_defconfig), else starlte_defconfig's
	if grep -q '^CONFIG_DEVICE="starlte"' .config 2>/dev/null; then FROM=; else FROM="--defconfig starlte_defconfig"; fi
	ARGS=$(python3 tools/hakios-config.py args $FROM --with "$ARGS")
fi
ARGS="${VERBOSE:+$VERBOSE }$ARGS"
# The kernel's line holds 607 characters, and the loader puts its own words (about 110: debug=, rd=, ufs_shared_pa=,
# hakios_kver=) before these; what does not fit is cut from the end, so say so here rather than on the phone.
LINE="loader_return_after=$SECS epoch=$(date +%s) $ARGS"
[ $(( ${#LINE} + 110 )) -le 607 ] || echo "mkimage.sh: WARNING: ${#LINE} characters of arguments and about 110 of the loader's: more than the 607 the kernel holds; the end will be cut" >&2
P=$(mktemp "${TMPDIR:-/tmp}/starlte-payload.XXXXXX")
trap 'rm -f "$P"' EXIT
python3 xnuloader/mkpayload.py -o "$P" loader.efi="$L" kernel="$K" ramdisk="$RD" \
	--cmdline "$LINE" >/dev/null
UEFI_TARGET=starlte python3 mkxnuimg.py -p "$P" -o "$OUT"
echo "mkimage.sh: $OUT: in TWRP, adb push it to /sdcard and Install Image to Boot (or heimdall flash --BOOT $OUT); power on"
if [ "$SECS" = 0 ]; then LIMIT="no time limit"; else LIMIT="the run returns after $SECS s"; fi
echo "mkimage.sh: boot-args: $ARGS; $LIMIT"
