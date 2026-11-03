# The Galaxy S9's sensors

The accelerometer and gyroscope (ST LSM6DSL), the magnetometer, the barometer (ST LPS22H) and the light and
proximity sensor (ams TMD4906; the chips as Samsung's defconfig names them) are not wired to the Exynos 9810: they hang off the sensor hub inside the Broadcom
BCM4775 B0 GNSS chip, an MCU of its own ("ssp,BCM4773" in Samsung's device tree). The AP reaches the hub over one SPI bus
and four pins, and the hub runs a firmware that the AP has to load into its RAM at every power-up. On Android that is
the proprietary daemon `lhd`'s job; here the kernel does all of it:

| Piece | Where |
|---|---|
| the driver, 6 steps (`shub=N`) | `drivers/input/hakios.ssp.c` of the kernel (CONFIG_HAKIOS_SSP, on in `configs/starlte.config`) |
| the bytes: SPI frames, packets, CRC-8, RPCs, the patch's records, SSP | `drivers/input/hakios.bcm_shub.h`, checked by `tools/bcm-shub-test.sh` |
| the SPI master (USI_CHUB00) | `drivers/core/hakios.exynos_spi.c` (shared with the audio codec) |
| the hub's firmware | `firmware/sensorhub/bcm_sensorhub_a1.bin` (its README says where it comes from) |
| the samples to user space | `/dev/hakios-sensors` (`sys/hakios.sensors.h`) |
| iOS's side | `userland/src/inject.c` in backboardd: HID services of Apple's vendor page, and the orientation |
| the console | `sensors` on the USB console (`usb_gadget=5`): the hub's state and every sensor's last sample; `sensors on N` / `off N` |

## The hardware

From Samsung's device tree (`exynos9810-starlte_eur_open_26.dts`, `spi@13AC0000` / `BCM4773@0`, the `gps` node) and its
drivers (`drivers/sensorhub/brcm/`):

| What | Where |
|---|---|
| SPI | `spi@13AC0000`, USI_CHUB00 of the CHUB block (its USI mode word `0x13A13000`: 2 = SPI); mode 3, at most 25 MHz, 64-byte FIFO; pins gph0-0..3 (pinctrl@13A80000), function 2, MISO pulled down |
| clocks | CMU_CHUB 0x13A00000: gates +0x2010, +0x2090, +0x20A8, Q-channel +0x305C, divider +0x1808 (Samsung: 177.666 MHz, i.e. CHUB's 355 MHz bus / 2; the SPI's clock is a quarter of it). The driver sets the divider to 16 (about 5.5 MHz on the wire) unless `shub_div=` says otherwise |
| MCU_REQ / MCU_RESP | gph0-5 out / gph0-4 in: before every exchange the AP raises MCU_REQ and waits for MCU_RESP |
| HOST_REQ | gpa1-7 (ALIVE): the hub has something for the AP. Polled here (Samsung: a level interrupt) |
| NSTDBY | gpg0-2 (PERIC0), the `gps` node's pin: low holds the chip in standby. Samsung's kernel leaves it low and lhd drives it |
| AP_SLEEP | gpa0-5, an output, high while the AP runs |
| supply | LDO37 of the S2MPS18, `vdd_mcu_1p8`, always-on in Samsung's tree |
| sensors' positions | `ssp-acc-position = 4`, `ssp-mag-position = 5` (told to the hub, which turns the chips' axes into Android's) |

## The protocol, from the bottom

1. **SSI** (Broadcom's SPI framing, `bcm_gps_spi.c`): reads are `[0x50][0 0]` -> `[status][len]`, then `len + 3` bytes;
   writes are `[0x58][len][bytes][0 0]`, full duplex, the chip saying in the last two bytes how many it took.
2. **Packets** (`bbd_rpc_lh.c`): `0xB0 0x00` ... `0xB0 0x01`, escaped; `[seq][size][flags][details][payload][CRC-8]`.
   Reliable packets are acknowledged; INTERNAL ones synchronise the two ends' sequence numbers.
3. **RPCs**: `[id][len][data]`. 0x00/0x03 the version, 0x05 a memory write, 0x2E "start the application", 0x20/0x21
   sensor traffic.
4. **SSP** (`ssp_*.c`): 9-byte instructions (WHOAMI 0x0F must answer 0x55, SENSOR_SCANNING 0xF4, SENSOR_ADD 0xA1 ...),
   and data frames of records (0x37 a sample: `[sensor][sample][u64 time]`).

The ROM half of the firmware download (autobaud, sync, version, writes, start) is the one part no GPL source shows; it
is taken from the Galaxy Tab Active3's sensor-hub notes (exynos-linux/samsung-gtactive3wifi `docs/re/sensorhub.md`,
section 6.3: same chip family on the same SoC, read for facts), where a driver built on it ran.

## The steps

| `shub=` | does | says when it works |
|---|---|---|
| 1 | reads only: CHUB's power domain and clock first (nothing of CHUB is read if either is off), LDO37, the pins | `CHUB's power domain: ... STATUS f` |
| 2 | LDO37 on if off, the SPI set up, NSTDBY low 20 ms then high, MCU_REQ / MCU_RESP tried | `MCU_RESP answered` |
| 3 | the ROM: 36 bytes 0x80, the sync, the version | `3: ASIC 004775b0, ROM ...` |
| 4 | the patch, 452 writes in reliable packets, started at 0x00800161, synced again | `4 (the application): ASIC ...` |
| 5 | SSP: init done, WHOAMI, the formation, SENSOR_SCANNING, the firmware revision, the accelerometer's range | `5: WHOAMI 0x55`, `the sensors found: ...` |
| 6 | the sensors on (`shub_sensors=`, default accel, gyro, magnetometer, barometer, light, proximity), read for good | `sensors` on the console |

Other arguments: `shub_ms=` (the motion sensors' period, 20 ms), `shub_div=`, `shub_keep=0` (the hub off again at the
end), `shub_chub_on=1` (power CHUB's domain if the boot left it off), `shub_log=1` (every SPI frame), `shub_req_rpc=`
and `shub_req_len=0` (the shape of the AP's sensor requests, inferred: 0x20 with a u16 length, like the hub's 0x21).

## iOS

What iOS 16.5 reads, from its binaries (backboardd, BackBoardHIDEventFoundation, CoreMotion, CoreBrightness of 20F66):

| Sensor | HID service (page 0xFF00) | Event | Who reads it |
|---|---|---|---|
| accelerometer | usage 3, Built-In | type 13, g, iOS's axes (at rest -1 g on the axis pointing up: Android's sign turned) | backboardd (BKSAccelerometer), CoreMotion |
| ambient light | usage 4 | type 12, Illuminance (0xC000B) in lux; the last one given back on copyEvent | CoreBrightness (auto-brightness) |
| proximity | usage 8, `Placement` = 1 | type 14, Receiver bit 0x40 while near | backboardd: the screen off in calls |
| gyroscope / magnetometer | usage 9 / 10 | types 20 / 21, rad/s / uT | CoreMotion (locationd) |

Rotation is the exception: backboardd takes the orientation from CoreMotion's CMDeviceOrientationManager, which on the
iPhone X it believes it runs on asks Apple's motion coprocessor. `inject.c` replaces that manager's
`startDeviceOrientationUpdatesToQueue:withHandler:`, `stopDeviceOrientationUpdates`, `deviceOrientationBlocking` and
`isDeviceOrientationAvailable`, and works the orientation out from the accelerometer (gravity over 0.75 g on one axis
for 300 ms). The log says `hakios: sensors: orientation N (...)` and backboardd "Updating device orientation from
CoreMotion to: ...".

## Runs on the phone (phone 2, 3 November)

| Image | What it showed |
|---|---|
| s3 (`shub=6`) | step 1: CHUB's domain on (STATUS 0xf), LDO37 on (CTRL 0xEC), the boot leaves NSTDBY (gpg0-2) in function 2, high; after step 2 NSTDBY an output, high. MCU_RESP never rose: the ROM's sync was never sent |
| s5, s6 | the console's experiments: MCU_RESP reads 0 even pulled up, while MISO reads 1 against its pull-down (the chip is powered and drives its pins); every always-on LDO of Samsung's tree on. With MCU_RESP not waited for (`sensors nohello 1`, `sensors retry`): the ROM answers the sync (`01 01 06 00 ff 00 00 ff`), ASIC `004775b0` ROM `0004527c`; the 452 writes in 3.2 s; the application synced, ASIC `004775b0` ROM `0006431f`; "MCU Init is done", WHOAMI 0x55, the sensors found `0x1fff07f6bf`, firmware revision 21031900, the accelerometer's range 8 g |
| s8 | the hub's frames dumped: the magnetometer's sample is 8 bytes on this firmware (the overflow byte), not Samsung's defconfig's 7 |
| s9 | everything at once, MCU_RESP no longer waited for by default: 3069 data frames, 1 bad; accelerometer `x 31 y -57 z 4076` lying flat (4096 = 1 g), gyroscope, magnetometer, barometer (`4252216` = 1038.1 hPa, the hub itself says 1038.19), proximity (far, adc 125), light (0 lux, the room dark) |
| s9, s10 | iOS: backboardd "Updating device orientation from CoreMotion to: faceUp (5)" and "Sending orientation: faceUp (5) event to SpringBoard"; with `sensors fake 4096 0 0 20` "Effective device orientation changed to: landscapeLeft (3)" and "Last effective interface orientation changed to: landscapeRight (3)", and back to portrait; "[UISensor] send prox event: Proximity"; backboardd and CoreMotion set "Shake", "ReportInterval", "GyroProperties", "DetectionMode" on the services |

Not yet confirmed: an application turned on the screen by a hand turning the phone (nobody was at it; the orientation
was fed with `sensors fake`); the gyroscope's and magnetometer's scales (inferred from the phone at rest, inject.c's
head); CoreBrightness's auto-brightness from the light service (the room was dark: 0 lux throughout). Why MCU_RESP
reads 0 is open (another pin on this board revision, or the hub never drives it): `shub_hello=1` puts Samsung's
handshake back.
