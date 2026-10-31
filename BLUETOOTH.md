# Bluetooth on the Galaxy S9

The S9's radio is a Broadcom BCM4361 module (Murata or Samsung Electro-Mechanics). Its Wi-Fi half is on PCIe
([WIFI.md](WIFI.md)); its Bluetooth half is on a UART of the SoC and speaks HCI over H4. Stage 1, written and not yet
run on the phone, is `drivers/bluetooth/hakios.bcm4361_bt.c` in the kernel repository: it powers the chip, talks HCI to
it, loads Broadcom's patch from the user's own phone and reads the version again. There is no host stack: nothing pairs,
scans or carries data, and iOS sees nothing of it.

## The hardware

All of it from Samsung's device tree for the S9 (`exynos9810-starlte_eur_open_26.dts` of its kernel) and the drivers
named; the driver's head has the same facts with every line number.

| What | Where | From |
|---|---|---|
| The UART | UART_BT at 0x10840000 (Android's `/dev/ttySAC1`), 256-byte FIFO, SPI 422 (not used: the driver polls) | dts 9480-9495; `init.samsungexynos9810.rc:637`; `bcm43xx.c:46` (BT_UPORT 1) |
| Its clock | PERIC1's UART_BT: 400 MHz CLKCMU_PERIC1_IP, divider ratio 1, so 200 MHz | `cmucal-sfr.c:1577, 1593`; `cmucal-vclklut.c:533, 1905-1907, 2074-2075` |
| Its pins | gpq0-0 RXD, -1 TXD, -2 RTS, -3 CTS (ALIVE), function 2, pull-up | dts 268-282; `pinctrl-exynos.c:1934` |
| BT_REG_ON (BT_EN) | pin 7 of the PCAL6524 GPIO expander, address 0x22 on hsi2c@10930000 (USI10_I2C of PERIC1) | dts 13866-13872 (`gpios = <76 7 0 ...>`), 6747-6786; `bcm43xx.c:272` |
| The expander's reset | gpg3-6 (PERIC1), high to run | dts 3405-3412; `gpio-pcal6524.c:418-445` |
| BT_WAKE | gpg2-0 (PERIC0), output, high while the host sends | dts 2691-2699; `bcm43xx.c:131, 318` |
| BT_HOST_WAKE | gpa2-3 (ALIVE), input | dts 531-537 |
| WLAN_REG_ON | gpg0-5 (PERIC0): a separate line | `dhd_custom_exynos.c:222-236`; dts 2670 |

BT_REG_ON and WLAN_REG_ON are separate: Bluetooth can be powered with Wi-Fi off, and the reverse. bcmdhd has one
workaround that ties the two (`si_pmu_wlan_bt_reg_on_war()`, `hndpmu.c:680-710`), and it is for the BCM4389 only.
The expander also carries the DisplayPort switch, the fingerprint sensor's sleep pin, NFC and wireless charging: the
driver changes bit 7 of port 0 and nothing else, and reads every write back.

What the chip is told is what Linux's Broadcom drivers tell it (`btbcm.c`, `hci_bcm.c`): 115200 baud, 8N1, RTS/CTS;
HCI_Reset; Read Local Version; Download Minidriver (0xFC2E), 50 ms, the `.hcd` file's records one by one, 250 ms; HCI_Reset
and Read Local Version again. The baud rate stays at 115200 (Android raises it to 4 Mbaud with 0xFC18; stage 2).

## The file from the phone

Never committed: `fw-bt/` is outside the repository's whitelist (`.gitignore`), like `fw-wifi/`.

| The phone's file | What | In `fw-bt/` as |
|---|---|---|
| `/vendor/firmware/bcm4361B2_murata.hcd` or `bcm4361B2_semco.hcd` | Broadcom's patch for the module; about 106 KB, 440 Write_RAM records and a Launch_RAM | `bcm4361B2.hcd` |
| `/data/.cid.info` | which module this phone has ("murata" or "semco", written by bcmdhd at first boot) | (to choose the `.hcd`) |

`adb shell su -c 'ls -l /vendor/firmware/*.hcd; cat /data/.cid.info'`, then
`adb pull /vendor/firmware/bcm4361B2_<module>.hcd fw-bt/bcm4361B2.hcd`. Which file Samsung's closed `libbt-vendor.so`
picks is not known from source; the module name is the likely key. The patch carries its own description (Murata's
"BCM4361B2 Crown 1QW ANT1", SEMCO's "BCM4361B2 Crown E32A ANT1"), which the driver logs. `bt_hcd=<name>` takes another
name from `fw/`. `userland/build.sh` puts every `fw-bt/*.hcd` into the small image's `fw/`.

## First runs

One flash each, with `cpus=2 bootcpu=2` in every run (README.md, The cores), reading the pstore log in TWRP after
each. The driver is off without `bt=`.

| Run | Arguments | What to look for |
|---|---|---|
| 1 | `cpus=2 bootcpu=2 bt=1` | "UART_BT's clock: ... mux ... (bit 4: CMU_TOP's), divider ... (ratio 2: 200 MHz ...)" (if not, add `bt_uart_mhz=` later); the four gates; "expander reset gpg3-6 function 1 level 1"; the UART's registers or "a gate of UART_BT is forced off" |
| 2 | `cpus=2 bootcpu=2 bt=2` | "the expander: input .. .. .., output .., direction ..; BT_EN (P0_7) ..." and no "could not be read". If it says the expander is held in reset: again with `bt_expander_reset=1` |
| 3 | `cpus=2 bootcpu=2 bt=3` | "UBRDIV 107 UFRACVAL 8 (115207 baud from 200 MHz)", "loopback: all 16 bytes came back" |
| 4 | `cpus=2 bootcpu=2 bt=4` | "BT_EN high: the chip powered", the expander's output now with bit 7 set and reading 1, "nothing from the chip on its own", then "the chip off" |
| 5 | `cpus=2 bootcpu=2 bt=5` | "HCI version .. revision ...., LMP version .. subversion ...., manufacturer 000f (Broadcom)" and a local name. No answer: the log has UFSTAT and UMSTAT (CTS) |
| 6 | `cpus=2 bootcpu=2 bt=6` (with `fw-bt/bcm4361B2.hcd` in the image) | "fw/bcm4361B2.hcd: ... 441 records ... \"BCM4361B2 Crown ...\"", "100 of 441" ... "Launch_RAM", then the version again and "before the patch a.b.c build n, after it ..." |

Each step logs what it is about to do before doing it. At the end the chip is powered off (BT_EN and BT_WAKE low)
unless `bt_keep=1`. A run that stops at the first I2C transfer with a time-out is the bus or the expander (run 2's
log); one that stops at "sending stopped" with CTS not asserted is the chip not up (BT_EN, or the module's own supply).

## Stage 2: what iOS's Bluetooth would need

Stage 1 ends with a chip running Broadcom's patch and answering HCI commands. iOS's Bluetooth is a closed user-space
daemon (`bluetoothd`, with `BlueTool` to boot the controller on the iPhones that have a UART controller) over the
kernel's serial and power interfaces. What it would take, in order, and how sure each part is:

1. **The link at speed.** Raise the baud rate with Broadcom's 0xFC18 (`hci_bcm.c:82-129`) and the UART with it: 4 Mbaud
   is a divisor of exactly 50 from 200 MHz (UBRDIV 2, UFRACVAL 2; `hakios.bcm_hci.h` works it out). Give the chip the
   phone's own address from `/efs/bluetooth/bt_addr` with 0xFC01 (`btbcm.c:93`). Small, and checkable from the
   same log as stage 1.
2. **Interrupts and power.** Take UART_BT's interrupt (SPI 422) instead of polling; use BT_WAKE and BT_HOST_WAKE the way
   `bcm43xx.c` does (assert BT_WAKE before sending, let it go a second after; wake on BT_HOST_WAKE). Broadcom's sleep
   mode is set by a vendor command that Samsung's closed `libbt-vendor.so` sends; its parameters are not in any source
   here and would have to be read from that library's behaviour (an HCI log from Android), not guessed. Until then the
   chip simply stays awake, which costs battery but works.
3. **A way to user space.** A character device carrying raw H4 packets (as Linux's `/dev/vhci` does, or a tty with
   termios), so that a host stack can run outside the kernel. This is the boundary to keep: no Bluetooth host stack in
   the kernel.
4. **iOS's own stack on top.** This is the open question, and the reason stage 2 is not simply "more of stage 1":
   - What `bluetoothd` opens on the iOS version this port runs: on iPhones with a UART controller it is a serial port
     published by IOKit (IOSerialFamily's BSD client, a `/dev/uart.*` node) and a power service; on newer iPhones the
     controller is on PCIe and the interface is Apple's own. Which one this iOS's `bluetoothd` and `BlueTool` expect, and
     the IODeviceTree properties they read (transport, the controller's vendor and product, the address), has to be
     read out of the user's iOS image (strings and the IORegistry matching of those two binaries). Nothing of that is
     verified here.
   - `BlueTool` boots Apple's own controllers with Apple's own scripts and patch files. It would have to be kept from
     doing that (the controller is already booted by the kernel at step 6) or be given a script that does nothing,
     and `bluetoothd` would have to accept a controller whose manufacturer is Broadcom with Samsung's patch.
     Older iPhones used Broadcom controllers, so HCI itself is not the obstacle; the identity checks and the boot scripts
     may be.
   - Audio: A2DP is ACL data and needs nothing more; calls (SCO) on the S9 may be routed over the chip's PCM pins to
     ABOX rather than over HCI (not checked in the BSP), which would be a second, separate piece of work.

   How realistic: steps 1 to 3 are ordinary driver work from facts already in this tree, and could be checked on the
   phone with a small user-space HCI tool (a BLE scan, say). Step 4 is research before it is code: if `bluetoothd`
   accepts a serial controller described the way it expects, the kernel side is a serial port and a power switch,
   which is modest; if it insists on Apple's controller identity or its PCIe transport, iOS's Bluetooth is not
   reachable without replacing `bluetoothd`, and the honest goal becomes a standalone stack for one profile (a BLE
   or HID keyboard), outside iOS's Settings.

## Status

Written, not yet seen. Compiled with the driver on and off; every register and value checked against the BSP (the
kernel PR has the table); the H4 framing, the HCI events, the `.hcd` reading and the UART divisor checked on a computer
(`tools/bcm-hci-test.sh`). Not run in QEMU (no such UART or expander there) and not on the phone.
