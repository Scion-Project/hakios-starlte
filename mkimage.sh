#!/bin/bash
# The Galaxy S9's boot image for one run: the boot shim, HakiOS's UEFI for starlte (prebuilt/ or a Mu-Silicium/ built
# here) and a payload with everything in it -- the loader, the kernel, the small root image, the command line. Samsung's
# boot loader has no fastboot and Silicium's UEFI no USB gadget, so there is no resident loader to send runs to as on the
# POCO: every run is an image flashed to BOOT, TWRP kept in RECOVERY (README.md, "On the phone"). The run ends by itself after SECS seconds
# (loader_return_after=): the loader keeps the log in Samsung's pstore RAM and restarts the phone.
#
#   devices/starlte/mkimage.sh [-o xnu-starlte.img] [-k kernel] [-r root.apfs] [-s SECS] [-q] [boot-args...]
#
# The kernel is the S9's own configuration (make starlte_defconfig && make kernel: hakios-kernel); the boot-arguments
# default to that configuration's (tools/hakios-config.py args), with -v (the kernel's log on the screen, for a phone
# with no other way to show it while it runs) unless -q. The loader is xnuloader/loader.efi, built with the
# iPhone identity from your own IPSW (make loader): the image is yours, never to be published.
set -e
START=$PWD
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
OUT=$ROOT/xnu-starlte.img K=$ROOT/hakios-kernel RD=$ROOT/userland/root.apfs SECS=120 VERBOSE=-v
while getopts o:k:r:s:q opt; do
	case $opt in
	o) OUT=$OPTARG ;; k) K=$OPTARG ;; r) RD=$OPTARG ;; s) SECS=$OPTARG ;; q) VERBOSE= ;;
	*) sed -n 2,14p "$0"; exit 2 ;;
	esac
done
shift $((OPTIND - 1))
# (-o, -k and -r as given, from where this was run, before the cd below took effect for them)
abs() { case "$1" in /*) echo "$1" ;; *) echo "$START/$1" ;; esac; }
OUT=$(abs "$OUT") K=$(abs "$K") RD=$(abs "$RD")
L=xnuloader/loader.efi
for f in "$L" "$K" "$RD"; do
	[ -f "$f" ] || { echo "mkimage.sh: $f is missing (make loader, make kernel, userland/build.sh)" >&2; exit 1; }
done
ARGS="$*"
if [ -z "$ARGS" ]; then
	# the arguments of the configuration made here, which must be this phone's (make starlte_defconfig)
	grep -q '^CONFIG_DEVICE="starlte"' .config 2>/dev/null || {
		echo "mkimage.sh: .config is not the S9's: make starlte_defconfig first, or give the boot-arguments" >&2; exit 1; }
	ARGS=$(python3 tools/hakios-config.py args)
fi
ARGS="${VERBOSE:+$VERBOSE }$ARGS"
P=$(mktemp "${TMPDIR:-/tmp}/starlte-payload.XXXXXX")
trap 'rm -f "$P"' EXIT
python3 xnuloader/mkpayload.py -o "$P" loader.efi="$L" kernel="$K" ramdisk="$RD" \
	--cmdline "loader_return_after=$SECS epoch=$(date +%s) $ARGS" >/dev/null
UEFI_TARGET=starlte python3 mkxnuimg.py -p "$P" -o "$OUT"
echo "mkimage.sh: $OUT: in TWRP, adb push it to /sdcard and Install Image to Boot (or heimdall flash --BOOT $OUT); power on"
echo "mkimage.sh: boot-args: $ARGS; the run returns after $SECS s"
