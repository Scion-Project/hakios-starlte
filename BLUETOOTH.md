# Bluetooth on the Galaxy S9

The S9's radio is a Broadcom BCM4361 module (Murata or Samsung Electro-Mechanics). Its Wi-Fi half is on PCIe
([WIFI.md](WIFI.md)); its Bluetooth half is on a UART of the SoC and speaks HCI over H4. The kernel's
`drivers/bluetooth/hakios.bcm4361_bt.c` powers the chip, talks HCI to it, loads Broadcom's patch from the user's own
phone, raises the link to 4 Mbaud and keeps the chip up for the USB console (`bt`, `bt scan`) and for user space
(`/dev/cu.bluetooth`). There is no host stack in the kernel; iOS's own (`bluetoothd`) gets as far as the section
"iOS" below says.

## The hardware

All of it from Samsung's device tree for the S9 (`exynos9810-starlte_eur_open_26.dts` of its kernel) and the drivers
named; the driver's head has the same facts with every line number.

| What | Where | From |
|---|---|---|
| The UART | UART_BT at 0x10840000 (Android's `/dev/ttySAC1`), 256-byte FIFO, SPI 422 (not used: the driver polls). Held in reset by its USI wrapper until USI_CON (0xC4) is written 1 then 0 and USI_OPTION (0xC8) 2: it reads 1 as the boot loader leaves it | dts 9480-9495; `init.samsungexynos9810.rc:637`; `bcm43xx.c:46` (BT_UPORT 1) |
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
and Read Local Version again. Then (bt=7) 0xFC18 with 4000000, answered at 115200, and the UART to 4 Mbaud
(UBRDIV 2, UFRACVAL 2 from 200 MHz: exact). Linux sends 0xFC45 (the UART clock to 48 MHz) first above 3 Mbaud; this
module's BCM4347B2 does not know it (status 01) and runs at 4 Mbaud without it.

## The patch

Broadcom's patch, one for each module maker: `bcm4361B2_murata.hcd` ("BCM4361B2 Crown 1QW ANT1") and
`bcm4361B2_semco.hcd` ("BCM4361B2 Crown E32A ANT1"), about 106 KB each. The project carries both (`firmware/bt/`, from
the LineageOS 24 vendor image; its README has the sums) and the phone has them in its VENDOR partition. At step 6 the
driver takes, in order: `fw/<bt_hcd>` if `bt_hcd=` names one there (a developer's own `fw-bt/`); then, for the module,
`fw/bcm4361B2_<module>.hcd` (`userland/build.sh DEVICE=starlte`) and the phone's own `/vendor/firmware/` and
`/vendor/etc/bluetooth/`, read at run time (`ufs=2`, `drivers/storage/hakios.ext4.c`, as for Wi-Fi; `bt_vendor=0` leaves
VENDOR alone).

Which module: `bt_module=murata` or `semco`; else what Wi-Fi read from the chip's OTP in the same run (`brcmfmac=2` and
up: the module's ID, WIFI.md; the driver waits up to 30 s for it); else Murata's first, and the log calls it a guess.
The patch's own description, which the driver logs, names the module it is for.

## On the phone (3 November 2026, phone 2, SEMCO module)

`bt=7` turns Bluetooth on; it is not one of the S9's defaults (it would take the line's last 5 characters: README.md,
Defaults), so give it to `mkimage.sh` for a run. One image, `bt=7 bt_scan=1 wifi_pcie=6 brcmfmac=8 ...` (Wi-Fi reads the module from the chip's OTP; the patch then comes
from the phone's VENDOR). What the log said, step by step:

| Step | What it said |
|---|---|
| 1 | `USI_CON 1 USI_OPTION 1` (the UART in reset), gates open, PERIC1 mux on CMU_TOP, divider 1 (200 MHz) |
| 2 | the expander: `input 10 08 20, output 10 08 00, direction 2f f5 ff`; BT_EN an output, low; its reset pin already high |
| 3 | `UBRDIV 107 UFRACVAL 8 (115207 baud from 200 MHz)`, `USI_CON 0 USI_OPTION 2`, `loopback: all 16 bytes came back` |
| 4 | `BT_EN high`, the expander reading 90 on port 0, `UMSTAT 11 (CTS asserted)`, nothing from the chip on its own |
| 5 | `HCI version 9 revision 0000, LMP version 9 subversion 4309, manufacturer 000f (Broadcom)`, local name `BCM4347B2` |
| 6 | `the module is semco's, as Wi-Fi read it`, `VENDOR:/firmware/bcm4361B2_semco.hcd: 108067 bytes, 440 records`, all sent, Launch_RAM; after it `revision 00e8`, name `BCM4361B2 Crown E32A ANT1 [Version: 0110.0232]`: 2.3.9 build 0 before, build 232 after |
| 7 | `fc45: status 01`, then `at 4000000 baud, flow control on: Read Local Version answers`; address `43:61:b2:00:1f:ac`; the scan: inquiry complete (no BR/EDR device was discoverable), 21 LE devices with RSSI, among them `LE_WH-1000XM3`; 0 receive errors |

`bt scan` on the USB console did the same again a minute later (18 LE devices). `bt` says the state: `up, patched,
4000000 baud with RTS/CTS; LMP subversion 4309 HCI revision 00e8 manufacturer 000f; address 43:61:b2:00:1f:ac`.

The chip's address is Broadcom's default (43:61:b2:...), not the phone's own: Samsung writes the phone's from
`/efs/bluetooth/bt_addr` with 0xFC01, which is not done here yet.

## iOS

What iOS 16.5's `bluetoothd` (the iPhone X build this port runs) wants, read from the binary and seen on the phone:

1. **A serial port**: `/dev/cu.bluetooth` or `/dev/uart.bluetooth` (it tries both). The kernel makes both, and
   `/dev/tty.bluetooth`, at bt=7: one tty of XNU's own (termios, select), its output to UART_BT and the chip's bytes
   into it; a speed set with `tcsetattr()` is set on the UART too.
2. **The transport**: the environment variable `BT_HCI_TRANSPORT` (H4, H4DS, H4BC, H5, USB, APPLEBT, PCIE); else a plist.
3. **An address**: a service named `marconi-bt` or `bluetooth` with `local-mac-address`
   (`IORegistryEntrySearchCFProperty` from it, the device tree plane). Without one: "Not a valid MAC address (all 00s)",
   "No bluetooth on this device.", exit. `BT_DEVICE_ADDRESS` is read and then zeroed in this build (an internal
   feature compiled out). The kernel's `hakios.bt_node.cpp` makes the service with the chip's address; then:
   "bluetooth: Got local-mac-address: 43:61:b2:00:1f:ac", "Server attached, going into msg loop."
4. **BlueTool**, which `bluetoothd` asks over XPC (`com.apple.BlueTool`, `RunBuiltinScript` "boot") to boot the chip
   before it opens the port. Here it stops: BlueTool says "Device not open yet, use 'device' to open it." and exits 1
   after 31 s, again and again, without asking for any `/etc/bluetool/<HW model>.boot.script` (an interposer put into it
   to send those paths to the small image saw no such request). Its default device comes from IOKit
   (`com.apple.uart.bluetooth`) or `BT_UART`; what it decides from the platform and the chip before that is the next
   thing to read out of it. The way round it that `bluetoothd` itself has, the preference `BlueToolBTResult`
   (`HWRepair`), is read behind a check that looks like an internal-build one.

So in Settings Bluetooth is not on yet: `bluetoothd` runs and waits for BlueTool's boot. The launchd job of
`bluetoothd` is not in the default job list (`userland/mkjobs.py` DENY has "bluetooth"); the runs above used a small
image with it added (and `BT_HCI_TRANSPORT=H4`, `BT_BAUDRATE=4000000`).

## Before it ran: what iOS's Bluetooth would need (the plan, kept)

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

Stages a to e on the phone (3 November 2026): the UART out of its USI reset and in loopback, the chip powered, HCI_Reset
and its version, Broadcom's patch and the version after it, 4 Mbaud with RTS/CTS, and an inquiry and an LE scan from the
USB console (`bt scan`). For iOS: the tty and the registry entry are there and `bluetoothd` stays up with the chip's
address; BlueTool's boot is what it waits on (the section "iOS").
