# Samsung Galaxy S9 (starlte, SM-G960F, Exynos 9810)

HakiOS on the Galaxy S9 the way it runs on the POCO: the phone's boot loader starts a UEFI, the UEFI starts `xnuloader`, the
loader starts XNU. Nothing of Android's virtualization is involved (that is the Pixel's route, `avf/`).

**The repository.** This is the S9's device repository: its configuration, its SoC layer (`soc/`), its UEFI platform and
the UEFI built from it (`uefi/`, `prebuilt/`), and the image script. It is checked out at `devices/starlte` of the kernel's
common repository, [Scion-Project/hackios-xnu-kernel](https://github.com/Scion-Project/hackios-xnu-kernel), which names it in
`devices/manifest.conf` at a revision (`tools/hakios-device.py sync starlte`). The S9's drivers are in the common
repository, as the POCO's are: `drivers/core/hakios.exynos_hsi2c.c`, `drivers/input/hakios.exynos_keys.c` and
`hakios.s6sy761.c`, `drivers/power/hakios.max77705.c`, `drivers/gpu/hakios.s6e3ha8.c` and `hakios.mali.c`/`.cpp`; and so
are the GICv2, the loader's platform and the image packing (`mkxnuimg.py`).

**State: written, not yet run on the phone.** The kernel's and loader's half is tested in QEMU with the same interrupt
controller (`qemu/run.sh` with `QEMU_GIC=2`). What is known and what is not is below; `device.conf` is the record.

## How it starts

```
S-Boot (Samsung's, unlocked)  -->  boot image on BOOT      -->  HakiOS UEFI                    -->  xnuloader  -->  XNU (EL1)
  power on                          BootShim + FD + XNUP         Mu-Silicium's starltePkg,           (platform        GIC-400, 4 x A55,
                                                                 Carbon Hypervisor at EL2 (PSCI),    "starlte")       UEFI's framebuffer
                                                                 the panel's buffer as GOP
```

- **The UEFI** is [Project Silicium's](https://github.com/Project-Silicium/Mu-Silicium) `starltePkg` on the `S5E9810Pkg`
  silicon package, with HakiOS's changes (`uefi/`: the boot shim copies the payload, the boot manager starts the loader).
  It is open source throughout, unlike a Qualcomm phone's: no vendor driver is extracted from the phone. The one binary in
  it, `Hyp.bin`, is Silicium's [Carbon Hypervisor](https://github.com/Project-Silicium/Carbon-Hypervisor) (GPL-2.0), which
  takes EL2 and answers PSCI itself, because the Exynos 9810's own firmware does not do it properly. `uefi/BASE` pins a
  Silicium commit of 2026-10-09, older than Carbon's update of 2026-10-13.
- **This port's change to the platform** (`uefi/files/`): the region the payload is copied to, 0xF0000000 + 64 MB, is
  reserved in the memory map. In Samsung's device tree that is the modem's region (`modem_if`); Android's `cbd` puts the modem
  image there and the boot loader does not, and HakiOS starts no modem.
- **The image** (`mkxnuimg.py`, `UEFI_TARGET=starlte`): an Android boot image (header v1) whose kernel is the boot shim, the
  UEFI image and the payload, **uncompressed and without a device tree** (Samsung's boot loader takes the device tree from
  the phone's own `dtb` partition and does not unpack a gzip), as Silicium's `starlte.toml` says.

## The BSP: Scion-Project's forks

The S9's drivers here are written afresh from the facts of Samsung's BSP (its LineageOS trees, by ExyHyperBrick),
which Scion-Project keeps as forks so that what the drivers cite does not move. The kernel is GPL-2.0: it is read
for register addresses, fields and sequences, never copied into this kernel (APSL, `LICENSE` of the common repo).
A driver's "Sources" comment names files of the kernel fork at the commit below.

| Fork | Branch | Commit read |
|---|---|---|
| [`android_kernel_samsung_exynos9810`](https://github.com/Scion-Project/android_kernel_samsung_exynos9810) | `lineage-24.0` | `e5906667068e` |
| [`android_device_samsung_starlte`](https://github.com/Scion-Project/android_device_samsung_starlte) | `lineage-24.0` | `bdfc23b06e4d` |
| [`android_device_samsung_exynos9810-common`](https://github.com/Scion-Project/android_device_samsung_exynos9810-common) | `lineage-24.0` | `c386c0516b98` |
| [`proprietary_vendor_samsung_starlte`](https://github.com/Scion-Project/proprietary_vendor_samsung_starlte) | `lineage-24.0` | `372082bbd32f` |
| [`proprietary_vendor_samsung_exynos9810-common`](https://github.com/Scion-Project/proprietary_vendor_samsung_exynos9810-common) | `lineage-24.0` | `4884d8b2e4be` |
| [`android_hardware_samsung_slsi`](https://github.com/Scion-Project/android_hardware_samsung_slsi) | `lineage-20-slsi` | `34f6c246e7fe` |
| [`android_hardware_samsung_slsi_exynos`](https://github.com/Scion-Project/android_hardware_samsung_slsi_exynos) | `lineage-20-slsi` | `41256bda9dd8` |
| [`android_hardware_samsung_slsi_exynos_dtbh`](https://github.com/Scion-Project/android_hardware_samsung_slsi_exynos_dtbh) | `lineage-23.2` | `c9bceb0d9b7e` |
| [`android_hardware_samsung_slsi_graphics`](https://github.com/Scion-Project/android_hardware_samsung_slsi_graphics) | `lineage-20-slsi` | `e48c45d324c1` |
| [`android_hardware_samsung_slsi_openmax`](https://github.com/Scion-Project/android_hardware_samsung_slsi_openmax) | `lineage-20-slsi` | `04b17f6f0470` |
| [`android_hardware_samsung_slsi-linaro_config`](https://github.com/Scion-Project/android_hardware_samsung_slsi-linaro_config) | `lineage-21` | `bfe1bee06e1e` |
| [`android_hardware_samsung_slsi-linaro_exynos`](https://github.com/Scion-Project/android_hardware_samsung_slsi-linaro_exynos) | `lineage-23.2` | `ab48fc5ba935` |
| [`android_hardware_samsung_slsi-linaro_graphics`](https://github.com/Scion-Project/android_hardware_samsung_slsi-linaro_graphics) | `lineage-21` | `c7361ca484db` |

## The hardware, and where each fact comes from

| What | Value | Source |
|---|---|---|
| RAM | 4 GB: 0x80000000-0xFFFFFFFF and 0x880000000 on; secure holes taken out by Silicium's RamManagerLib | Silicium `SamsungPkg/Library/RamManagerLib`, the device tree's `androidboot.dram_info` |
| Kernel window | the largest free block UEFI reports (the loader's choice) | `xnuloader/loader.c` `choose_window()` |
| Interrupts | GIC-400 (GICv2): distributor 0x10101000, CPU interface 0x10102000 | device tree `interrupt-controller@10100000` (`arm,cortex-a15-gic`) |
| Timer | the architected timer, 26 MHz; virtual timer PPI 27 | device tree `timer` |
| Cores | 0-3 Cortex-A55 ("ananke", MPIDR 0x000-0x003), 4-7 Exynos M3 ("meerkat", 0x100-0x103); PSCI by SMC | device tree `cpus`, `psci` |
| Display | 1440 x 2960, 32 bits, at 0xCC000000 (the boot loader's buffer, `s3cfb.bootloaderfb`); S6E3HA8 panel on DSIM 0x16080000 | Silicium `starlte.dsc`, the device tree |
| Touch | Samsung S6SY761 (`sec,sec_ts`) at 0x48 on HSI2C 0x104B0000 (SPI 0x194) | device tree `touchscreen@48` |
| Buttons | GPIO keys: power, volume up and down, Bixby | device tree `gpio_keys`; Silicium `KeypadDeviceLib` |
| Storage | UFS at 0x11120000 (UFSHCI), its vendor registers at 0x11121100, UniPro 0x11110000, the protector (FMP) 0x11130000, the PHY's PMA 0x11124000; SPI 242; PMU UFS_PHY_CONTROL 0x14060724; Silicium's UEFI has UniPro at 0x11130000 (base + 0x10000), the Samsung kernel and its device tree at 0x11110000 | device tree `ufs@11120000` (its reg, `ufs-phy`, `ufs-phy-sys`); the Samsung kernel's `ufs-exynos.c`; Silicium `PlatformUfsLib` |
| GPU | Mali-G72 MP18 at 0x17500000 (GPU_ID >> 16 = 0x6221); SPI 282/281/283 (job, MMU, GPU); power domain `pd-embedded_g3d` (PMU 0x14064040/44); PLL_G3D in CMU_G3D 0x17400000 | device tree `mali@17500000`; ExyHyperBrick's kernel (G3D CAL) |

The device tree is Samsung's own (Silicium's `Resources/DTBs/starlte.dts`). Pull your phone's
(`adb shell su -c 'cat /sys/firmware/fdt'`) and compare before believing an address from it. The
[WoA port for the S9+](https://github.com/ntdevlabs/exynos9810-woa) and
[ExyHyperBrick's kernel](https://github.com/ExyHyperBrick/android_kernel_samsung_exynos9810) (GPL-2.0: read for facts, never
copied into this tree) are the references for the drivers still to write.

## The cores

Cores 0-3 are Cortex-A55s (MPIDR 0x000-0x003). Cores 4-7 are Exynos M3s (0x100-0x103, 2.7 GHz), which Carbon's PSCI
starts. The loader numbers them through `platform_starlte.core_mpidr`. The default configuration (`cpus=2 bootcpu=2`) gives
the kernel A55s 2 and 3, the only cores it can have so far (seen on the phone, 30 October 2026):

- core 1: S-Boot powers it up and parks it before the hand-over, so CPU_ON for it never brings it to the kernel (the loader
  leaves it out: `platform_starlte.parked_cores`);
- the M3s: the firmware's CPU_ON for one (Carbon, then Samsung's EL3) never returns, and the processor that asked stays
  inside it for good (patch 1505's log);
- the A55s' own MPIDR has them one affinity field up (core 2 reads 0x81000200, MT set) from the numbers the device tree and
  the firmware use (0x2); the kernel notices and translates (patch 1504).

The M3s implement ARMv8.0, while the A55s and the iPhone X's A11 implement 8.2. That does not keep iOS off them: a count
over three files of the iPhone X's shared cache (57.6 million words) found 7088 `LDAXR`s and 7208 `STLXR`s, the 8.0 way of
doing atomics, while `CAS`/`LDADD`/`SWP` turn up no more often than random bytes would. What remains is code that asks
which features the processor has (`hw.optional.arm.FEAT_*`) and then uses them. XNU answers from the core it boots on, so
**a kernel with the M3s boots on one: `bootcpu=4 cpus=8`.** It then reports no more than every core can do, runs on
the big cores first, and leaves core 0 to the loader, which is also what the storage needs (below).

## Build

```sh
make starlte_defconfig && make kernel        # the common kernel, no driver of another phone (configs/starlte.config)
make loader                                  # with the iPhone identity from your own IPSW
(source ./xnu-env.sh; cd userland && GL=1 NO_AIR=1 REST=1 ALONE=1 bash build.sh)   # the small root, the whole root here (ALONE=1)
devices/starlte/mkimage.sh -s 120            # xnu-starlte.img: the shim, the UEFI, the loader, the kernel, the small root
devices/starlte/mkimage.sh -s 300 cpus=2 bootcpu=2 exynos_keys=1     # the same with other boot-arguments
```

Samsung has no `fastboot boot`, and Silicium's UEFI has no USB gadget, so there is no resident loader to send runs to as
on the POCO (the kernel's own USB link, below, gives the log and a console, not a way to send runs). Each run is an image, and the run returns to the loader by itself after `-s` seconds. The loader then keeps
the log in RAM and restarts the phone. The UEFI comes from `prebuilt/` (built from source, open throughout:
`prebuilt/README.md`), or from `Mu-Silicium/` when one is built here (`devices/starlte/uefi/apply.sh`, then
`build_uefi.py -d starlte -r RELEASE`).

## On the phone

**First, the backups. Samsung has no `fastboot boot`, so every try is a flash.**

1. Make sure the bootloader really is unlocked: Download mode (Vol Down + Bixby, then plug in USB) shows `OEM LOCK: OFF`.
2. In TWRP, or with root, back up `EFS` (the IMEI: losing it is permanent), `BOOT` and `RECOVERY` to the computer.
3. Flash the image to **BOOT** and keep TWRP in RECOVERY, as the WoA port for the S9+ does: TWRP is where the log is
   read after a run and where Android is put back. From TWRP: `adb push xnu-starlte.img /sdcard/`, then Install, Install
   Image, Boot (or `heimdall flash --BOOT xnu-starlte.img` from Download mode).
4. Power on: HakiOS starts. A run restarts the phone into recovery when it ends (the loader sets the reset reason
   S-Boot reads, PMU INFORM3 = 0x12345674, as Android's `reboot recovery` does; `recovery=0` turns it off), so TWRP
   comes up with the log still in RAM. If the phone hangs instead, hold Vol Down + Power until it restarts, then at
   once Vol Up + Bixby + Power for TWRP. Android back: restore the BOOT backup in TWRP.

The default command line (`cpus=2 bootcpu=2 ...`, and `-v` from `mkimage.sh`) runs the kernel on cores 2 and 3 and leaves
core 0 to the loader, which watches it: if the kernel hangs, the loader writes its log into the pstore RAM and restarts
the phone, so a hang leaves something to read. `-v` shows the kernel's log on the screen while it starts.

What to look for, in this order:
1. HakiOS's logo (the UEFI started).
2. The loader's banner, with `platform starlte, GICv2` and `CurrentEL=1` (Carbon has EL2).
3. The kernel's log, `gic: v2 ... cpu 0 is interface 2` (the kernel starts on core 2), `2 of 2 processors are running`.
4. launchd.

Photograph the screen as well. The loader's `logdump` is a Qualcomm partition, and this phone has none. Instead, the
loader keeps the log in Samsung's pstore RAM (0xFED14000, 16 KB: the head of the loader's log and the tail of the kernel's),
which a restart leaves alone. Restart into TWRP or Android (Vol Down + Power) and read it:
`adb shell su -c 'ls /sys/fs/pstore; cat /sys/fs/pstore/pmsg-ramoops-0'`. If no file shows up there, the phone's own kernel
lays the zones out differently: `cat /sys/module/ramoops/parameters/*` and the `log_pstore` node say how, and
`platform_starlte.ram_log` in `xnuloader/loader.c` is the one number to change.

The pstore's first half (0xFED10000, 16 KB) is ramoops' one dmesg record. The loader writes the start of the kernel's
log there, behind the header line ramoops needs, so a run that comes back leaves `dmesg-ramoops-0` (the start) beside
`pmsg-ramoops-0` (the loader, then the end). Before the panic buffer exists (`arm_vm_init`), a panic's text, the last
exception's ESR/FAR/ELR and the frames that led to it go straight into that log (patch 1503). With boot-arg
`early_log=1`, every kprintf from `PE_init_platform` on and the processors as the kernel sees them (MPIDR, the
topology's phys ids) go there as well. That's for a phone that dies before its console works, at the cost of filling
the 32 KB sooner.

## Building in CI: the installer in one click

Actions > **s9-installer** > Run workflow (`.github/workflows/s9-installer.yml`). One job, about two hours on GitHub's
Ubuntu runner:
1. It downloads iOS 16.5 (20F66) for iPhone10,3 from Apple's CDN, checked by size and hash, and unpacks it.
2. It builds the S9 kernel, the loader with the iPhone identity, Mesa, the small root and the system image.
3. It makes the TWRP installer (scion-packaging), with the system image going to SYSTEM unless the run says
   otherwise.

The artifact `scion-s9-installer` is a 7z archive, AES-256 with its file names hidden. Its passphrase is the
repository secret `INSTALLER_PASSPHRASE`, and the job refuses to run without it. The installer carries iOS's own
files, and anyone signed in to GitHub can download a public repository's artifacts. Artifacts are kept for 3 days.

To use it:
1. Download the artifact.
2. Open the archive with the passphrase (`7zz x scion-s9-installer.7z`, or Keka / 7-Zip).
3. Check `SHA256SUMS`.
4. Flash `scion-starlte-installer.zip` from TWRP as it is.

The run's inputs: the kernel and packaging refs, the partition, and extra boot-arguments.

## Storage: iOS from the phone's flash

**The installer:** [Scion-Project/scion-packaging](https://github.com/Scion-Project/scion-packaging) `starlte/mkinstaller.sh`
makes one TWRP zip. It writes the boot image (`-s 0`, `ufs=2 system_apfs=ufs_SYSTEM`) to BOOT and `userland/system.apfs`
to SYSTEM, then checks both by SHA-256. On boot, init mounts the system image from `/dev/ufs_SYSTEM` and makes it the
root, and the boot goes on as a RAM boot does. This is rehearsed in QEMU up to SpringBoard (GICv2, 4 GB, a GPT
partition read through the loader). The small root for it is built with `ALONE=1 RC=rc.launchd`.


Silicium's UEFI drives the UFS and stays resident. With `ufs=2` (and the default `cpus=2 bootcpu=2`), the loader keeps core 0 and reads for the kernel, which runs on cores 2 and 3: the same
service the POCO uses (`drivers/storage/hakios.ufs.c`). Every GPT partition becomes `/dev/ufs_NAME`, read-only, and
`root_apfs=ufs_NAME` mounts iOS's root volume from one.

The iOS system image (`userland/system.apfs`) needs a partition of its own, written once from TWRP:
`adb push system.apfs /tmp/ && adb shell dd if=/tmp/system.apfs of=/dev/block/by-name/NAME bs=4M`. Which partition
decides what is lost:
- `SYSTEM`: Android stops booting, TWRP still works.
- `USERDATA`: Android's data is wiped.

List the partitions and their sizes first: `adb shell ls -l /dev/block/by-name`.
Then: `devices/starlte/mkimage.sh cpus=2 bootcpu=2 exynos_keys=1 ufs=2 root_apfs=ufs_NAME`. Nothing writes to the flash: `ufs_write=1` is for the
POCO's `darwin` partition only, and the loader refuses any other.

**The kernel's own UFS driver** (`drivers/storage/hakios.ufshc.c`, `ufs_native=4 ufs_native_soc=exynos9810`, off by default;
written, not yet seen on the phone) drives the controller itself instead, with no core kept back for the loader. It does not
reset or bring up anything: it takes the controller as Silicium's UEFI left it (HS-G3, two lanes), reads back what UEFI set
up, and gives it back as it was at the end. It goes in steps, `ufs_native_step=N`, 1 by default:

| Step | What it does | What it writes |
|---|---|---|
| 1 | look: UFSHCI and vendor registers, the PHY's power (PMU), the device's reset line, the clock gating, IO coherency, UEFI's own descriptors (their PRDT entry size: the FMP's descriptor type) | nothing |
| 2 | the link: lanes, gears, power mode and series by DME_GET; UniPro's last results; the PHY's calibration read back | DME_GET's registers only |
| 3 | NOP OUT through the kernel's own transfer list, then UEFI's list back | its own list |
| 4 | each unit's descriptor, TEST UNIT READY, READ CAPACITY; UEFI's list back | its own list |
| 5 | LBA 0 and each unit's GPT; `/dev/ufs_NAME` for every partition, read only | its own list |

It is read only. `ufs_native_write=NAME` alone makes one partition writable, and never EFS, SEC_EFS, CPEFS, BOOT, RECOVERY,
PARAM, PERSISTENT, STEADY, RADIO or the rest of the boot chain (the list is in `drivers/storage/hakios.ufs.c`), nor a
boot or write-protected unit; the controller's driver refuses any write outside that partition's blocks again. Leave it
unset. Without `ufs=2`, the root comes from the image (the small root, `-s`). The first runs, one image each, the log read
in TWRP after each:

```sh
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 ufs_native=4 ufs_native_soc=exynos9810                     # step 1
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 ufs_native=4 ufs_native_soc=exynos9810 ufs_native_step=2   # the link
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 ufs_native=4 ufs_native_soc=exynos9810 ufs_native_step=3   # NOP OUT
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 ufs_native=4 ufs_native_soc=exynos9810 ufs_native_step=4   # READ CAPACITY
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 ufs_native=4 ufs_native_soc=exynos9810 ufs_native_step=5   # the GPTs, /dev/ufs_*
```

Each step says what it found (`ufs: own: ...`) and stops with `ufs: own: step N done`; go on only when it says what
the table above expects.

## Touch

`drivers/input/hakios.s6sy761.c` (`s6sy761=1`, off by default until it has been seen working). Its first run on the phone should go one step at a
time: `s6sy761_steps=1` only reads (the bus's clock divider among other things: if it says the HSI2C's input clock is not
200 MHz, `s6sy761_ipclk=` corrects the timing); 4 asks the chip its boot status, which should be 0x20 (its firmware
running, powered as the boot loader left it); 6 is touch. The coordinates are the chip's own range (its panel
information, else 0-4095 on both axes), spread over the whole panel, which is where the iPhone's picture is drawn.

## Battery

`drivers/power/hakios.max77705.c` (`max77705=1`, off by default until it has been seen working) reads the MAX77705's fuel gauge (0x36) and charger
(0x69) on CMGP's HSI2C every 5 seconds, and hands the charge, voltage, current, capacity, cycles and charger state to
iOS's power source. It never writes the chip. The temperature is the battery's thermistor (channel 4 of CMGP's ADC,
through the phone's own table), as Android reads it. Touch and battery share `drivers/core/hakios.exynos_hsi2c.c`.

## Brightness

`drivers/gpu/hakios.s6e3ha8.c` (`panel=1`, off by default until it has been seen working). The S6E3HA8 has no DCS brightness command, so the driver
sends Samsung's AOR, the part of each frame the pixels are off, through DSIM0's command FIFO. The range runs from
the boot loader's level down to about 2 % of it; the gamma for the panel's full range is this panel's own and comes
from Android's boot log (`dmesg | grep 'gamma\['`). `sysctl kern.hakios.brightness=0..255` sets it, and
`panel_brightness=N` sets it at start. The panel's gamma and AOR tables were checked against the BSP (every value of the
256 AOR levels and 74 gamma rows, and the calculation for 702 MTPs, byte for byte).

What iOS sets reaches the panel through `drivers/gpu/hakios.backlight.cpp`, where the driver registers at start
(`hakios: panel brightness: s6e3ha8 registered`); on a phone without a panel driver nothing registers and nothing
changes. Which property iOS sets when its slider moves is not known yet, so there are two ways in, both logged:

- the display service: a key named `brightness` (0-1 or 0-255), always; each key it is sent is said
  (`IOMobileFramebuffer: <process> sets <key> = <value>`);
- `backlight=1` publishes `AppleARMBacklight` (the class XNU knows as an ARM phone's backlight) under `disp0`, with
  IOGraphics' `IODisplayParameters` (`brightness` and `linear-brightness`, 0-65536). It says every key it is set
  (`AppleARMBacklight: <process> sets ...`), every property asked of it that it lacks (`... asks for ...: not there`)
  and who opens it. `backlight=2` also takes its `brightness` and `linear-brightness` as the panel's brightness.

Written, not yet seen. First run: `backlight=1`, move the slider in Control Center, and read those lines.

## The GPU

`drivers/gpu/hakios.mali.c` and `hakios.mali.cpp` (`CONFIG_HAKIOS_MALI`, built in): HakiOS's Mali-G52 driver of the
Infinix Hot 20 ([hakios-mt6768](https://github.com/oosexgang/hakios-mt6768), `redwood_mali.c` and `RedwoodMali.cpp`),
with MediaTek's power and clocks replaced by the Exynos 9810's, as the mainline Linux port to the S9+ brings the same
GPU up from S-Boot's state. `mali=N` makes the first N of nine steps, each said in the log before it is made, and
nothing without it (it is not on the default command line):

| Step | What |
|---|---|
| 1 | reads only: the PMU's G3D configuration and status, CMU_G3D (PLL_G3D and its rate, the muxes, the bus dividers), and through ACPM the S2MPS18's B6CTRL and B6OUT (BUCK6, vdd_g3d). The GPU itself is not read |
| 2 | B6OUT = 0x68 (950 mV, the regulator's most in the device tree) through ACPM and read back, or the steps end; PLL_G3D to `mali_mhz` (260, S-Boot's, unless said); then, if the domain is off, Samsung's power-on: CMU_G3D +0x148 = 0x30000003, +0x140 and +0x100 bit 4, PMU 0x14064040 [3:0] = 0xF and its status waited for |
| 3 | after a power-on of its own only: the DTZPC restore, SMC 0x82000410 (1, 0x17410204), passed to EL3 by Carbon; then the bus dividers (BUSD = the PLL, BUSP = a quarter) |
| 4 | the first read of the GPU: GPU_ID (a G72, arch 6, product 1), MMU_FEATURES (35 bits of GPU address at least, 36 of physical), the cores |
| 5 | a soft reset (a hard one if it does not finish), COHERENCY_ENABLE = 31 (none: the phone's device tree asks kbase for no coherency), L2_MMU_CONFIG's external read and write limits cleared |
| 6 | the L2, then the shader cores, then the tiler, each waited for |
| 7-8 | one write-value job on slot 1, in identity mode, then through the GPU's own AArch64 page tables (four levels on a GPU of 48 bits, as kbase and panfrost walk it) |
| 9 | HakiosMali, the IOKit service Mesa's panfrost draws through |

`mali_mhz=455` or `572` picks another of the stock table's rates (M/P/S inside the PLL's range: Samsung's PLL_1018X
limits); `mali_acpm=0` leaves the rail as found, which hung the S9+ (a test only). Short of step 9 a domain the driver
switched on is switched off again (reset first, Samsung's low-power settings, the DTZPC save) and B6OUT put back; a
domain the boot left on is left on, with the rail at 950 mV under it. Start with `mali=1`, then one step more per run
(`mkimage.sh cpus=2 bootcpu=2 mali=1 ...`); `sysctl kern.hakios.mali` says the last step done. With 9,
`/redwood/bin/mali_test` (run by rc.jobs) checks the program side without Mesa, and the window server draws with
OpenGL ES through Mesa's panfrost (`tools/mesa`, the root built with `GL=1`). Written and checked against Samsung's
kernel (CAL, kbase, ACPM, the device tree) and the S9+ port; not yet run on the phone.

## Vibration and the flashlight

`max77705_haptic=1` gives iOS the vibration motor: the MAX77705's haptic block (the same chip as the charger: two of
its registers written, in their haptic bits only, each read back) driven by channel 1 of the SoC's PWM, as Samsung's
driver drives it. `torch=1` looks at the S2MPB02's flash block, `torch=3` gives iOS the flashlight (lit by a pin, so a
restart puts it out; never above Android's 60 mA). Both are off on the default command line until seen working.

## Wi-Fi, stage 1

`drivers/wifi/hakios.exynos_pcie.c` (`wifi_pcie=N`, built in, off by default): the Exynos 9810's PCIe root complex of
channel 0 and the BCM4361 behind it, as far as the link and the chip's identity. 1 only looks (the PHY's isolation in the
PMU, CMU_FSYS1's gates, the pins), 2 powers the radio (WLAN_REG_ON, gpg0-5, 200 ms), 3 brings the PHY up, 4 trains the
link, 5 reads the endpoint's ID (Broadcom 14e4:441f expected) and sizes and places its BARs. No firmware is loaded.
Go up one step a run: `mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=1`, and so on; every line starts with `exynos_pcie:`.
[WIFI.md](WIFI.md) has the steps and what each should print. Written, not yet run.

Stage 2 (`drivers/wifi/hakios.brcmfmac.c`, `wifi_pcie=6 brcmfmac=N`, built in, off by default): Linux's brcmfmac
(ISC) on the Linux layer the POCO's ath11k runs on, its object made by `tools/mk-brcmfmac.sh` before the kernel is
built. 6 hands the device on; then `brcmfmac=1` reads the chip's ID through BAR0, 2 asks for the firmware, NVRAM and CLM
(from the user's own phone, in `fw-wifi/` under brcmfmac's names: WIFI.md has the table), 3 starts the firmware, 4 sends
it its first command (the first DMA) and registers the wiphy. 5 takes the chip's interrupt by INTx (SPI 253) instead of
a thread that looks (`brcmfmac_poll=1` keeps the thread), 6 gives the firmware the phone's address (`fw-wifi/mac.info`,
the phone's `/efs/wifi/.mac.info`), 7 is the station: the interface up, en0 on it, iOS's Wi-Fi settings scan through it,
and 8 joins: an open network or WPA2 with a passphrase (the four-way handshake by the kernel's own `lx_wpa.c`, as on the
POCO), and the network of `fw-wifi/network` at once if there is one. On the way back to the loader the driver is taken
down and the radio unpowered (WLAN_REG_ON low). Written, not yet run.

## Speaker audio

Two drivers, both built in and off until asked: `abox=N` (`drivers/audio/hakios.exynos_abox.c`, 8 steps) is the SoC's
side, ABOX with its own CPU off: memory -> RDMA0 -> SIFS0 -> UAIF1, I2S at 48 kHz, 2 x 16 bits; `max98512=N`
(`drivers/audio/hakios.max98512.c`, 3 steps) is the two amplifiers on I2C. Step 8 of ABOX makes it the sink of
`/dev/hakios-audio`, the same way in for iOS's sound as on the POCO, with iOS's volume and mute followed. Whether
ABOX's DMA runs without its firmware is something Android's source cannot say (Android never tries); what it does say,
and the runs that will tell, are in [AUDIO.md](AUDIO.md). Written, not yet heard.

## Temperatures

Android keeps the S9 cool with Linux's thermal framework and Samsung's APM firmware: the big cores slowed from 83
degrees and taken away at 96, the GPU slowed from 88, every zone's "hot" trip at 115. HakiOS has none of that, so
`drivers/power/hakios.exynos_tmu.c` (`tmu=N`, built in, off by default) at least watches. It reads the Exynos 9810's TMU
itself: TMU_TOP at 0x10070000 (BIG: sensors 1, 2, 3, 4, 6; LITTLE: 5) and TMU_SUB at 0x10074000 (G3D: 1; ISP: 2), each
sensor's 9-bit code made degrees with its own fuses (TRIMINFO: the codes at 25 and 85 degrees), the arithmetic of the
BSP's `exynos_tmu.c` (checked on the host: `tools/exynos-tmu-test.sh`). `tmu=1` only reads (the TMU's clock gate in
CMU_PERIS first, then the blocks as the boot left them, every sensor's fuse, code and temperature, and the thresholds
S-Boot may have armed), `tmu=2` publishes `sysctl kern.hakios.temp.*` (`big_mc`, `little_mc`, `g3d_mc`, `isp_mc`,
`max_mc`, `hottest`, `sensors`, `battery_c`) and the POCO's `kern.hakios.thermal_*`, `tmu=3` ends the run when a zone
reads `tmu_stop` (110, five under Android's hot trip) or the battery `tmu_batt_stop` (60) three times in a row: a loud
"TOO HOT" in the log, then back to the loader, which stops every core and restarts into TWRP with the log kept. With
`tmu_off=1` and no charger it powers the phone off instead (PS_HOLD low, as Samsung's power-off does; the log is lost).
Nothing slows anything down: the stop is the whole protection. If S-Boot leaves the TMU stopped, `tmu_enable=1` starts
it the way Android does, but never arms its hardware trip. Written, not yet run.

## USB: the whole log and a console over the cable

pstore holds 32 KB, read in TWRP after the run. `usb_gadget=N` (drivers/core/hakios.dwc3.c with the Exynos 9810's glue
hakios.exynos_usb.c; built in, off by default) makes the phone's USB-C port a USB serial device instead: the kernel's
log from its first line, live, for as long as the run lasts, the panic text at the end, and a line console back. It is
the DWC3 at 0x10C00000 in device mode, high speed, with a CDC-ACM function (pid.codes' test ID 1209:0001, "HakiOS kernel
log and console"): `/dev/ttyACM0` on Linux, `/dev/cu.usbmodem*` on a Mac. The PHY is brought up with the BSP's USB 3.1
CAL sequence for the 2.0 side only, the SuperSpeed lanes held idle (the head of hakios.exynos_usb.c has every register
and its line in the BSP). Silicium's UEFI has no USB driver in this FD, so only S-Boot can have touched the controller:
step 1 says what it left, step 2 stops it if it runs, step 3 resets it whatever it finds.

The steps: 1 reads (the PMU's isolation, the clocks, LDO9-14 through ACPM, the PHY's and the DWC3's registers), 2 the
PHY, 3 the core reset and set up as a device with the pull-up off, 4 the pull-up on and the host's requests answered
(each said in the log), 5 the log streamed and the console. On the way back to the loader the rest of the log is sent
for up to `usb_gadget_drain` ms (1000) before the controller is stopped. Options: `usb_gadget_clk=1` opens a clock S-Boot
left shut (Android's mux, divider and gate), `usb_gadget_ldo=1` puts LDO9-14 into Android's USB mode (read back),
`usb_gadget_fs=1` full speed.

On the host (a Linux machine; a Mac the same with `/dev/cu.usbmodem*`):

```sh
sudo systemctl stop ModemManager       # or it may open the port first; a udev rule with ID_MM_DEVICE_IGNORE=1 for 1209:0001 does the same
dmesg -w                               # step 4: "idVendor=1209, idProduct=0001", "cdc_acm ...: ttyACM0: USB ACM device"
while :; do [ -e /dev/ttyACM0 ] && stty -F /dev/ttyACM0 raw -echo && cat /dev/ttyACM0 >> s9-run.log; sleep 0.2; done
picocom -q /dev/ttyACM0                # the console: type help and Enter (the phone echoes the line, "usb> help")
```

The console's commands: `help`, `stat` (the link's counters), `uptime`, `sysctl NAME`, `log` (the kernel's log again from
its start), `return` (end the run: the loader restarts the phone into TWRP). It is the kernel's, not a shell.
Written, not yet run; the descriptors and requests are checked on the host (`tools/usb-acm-test.sh`). Not known: whether
the MAX77705's switch routes D+/D- to the SoC while HakiOS runs (step 4's "waiting for a host: line ..." says what the
PHY sees), and whether S-Boot leaves the clocks open.

## First runs of the drivers, one flash each

Each driver is written from the BSP's facts and has not run on the phone yet. Bring them up one at a time, each
step on its own flash, reading the pstore log in TWRP after each (`devices/starlte/mkimage.sh -s 120 cpus=2 bootcpu=2
<args>`). Note that `mkimage.sh` given any arguments uses those alone, in place of the configuration's (`cpus=2
bootcpu=2`): keep those two in every run, as the column below leaves them out.

| Run | Arguments | What to look for |
|---|---|---|
| 1 | none of the drivers | the loader's banner, "2 of 2 processors are running" |
| 2 | `exynos_keys=1` | "exynos-keys: power: bank 0x60 pin 4, CON f (interrupt), released", then down/up on presses |
| 3 | `s6sy761=1 s6sy761_steps=1` | "USI mode 4 ... divider ...": if the divider is not 1 on a 400 MHz branch, add `s6sy761_ipclk=` |
| 4 | `s6sy761=1 s6sy761_steps=4 s6sy761_ldo=0` | "boot status 20 (its firmware runs)" and "panel: 1440 x 2960 ..."; with no answer, again without `s6sy761_ldo=0` |
| 5 | `s6sy761=1` | "step 6: watching the IRQ pin", then touches |
| 6 | `max77705=1 max77705_steps=1`, then `_steps=4` | "version N, revision N", "now: NN.NN%, NNNN mV ..."; `max77705_ipclk=` if the clock logged differs |
| 7 | `max77705=1 max77705_haptic=1` | "haptic: the motor for iOS ... PWM 1270 ticks of 26000000 Hz" |
| 8 | `torch=1`, then `torch=2 torch_secs=2` | "ID ...; FLED_CTRL1 ..., CTRL2 ..." (reads only), then lit for 2 s at 60 mA |
| 9 | `panel=1 panel_gamma=1`, then `backlight=1` | the gamma read and logged only; then which key iOS's brightness slider sets (Brightness, above) |
| 10 | `abox=1` up to `abox=6`, one step a run | "the AUD domain is on", "IP_INDEX ... = 0x41424f58", "PLL_AUD 1179648xxx Hz", "UAIF1_CTRL1 ... reads 0x984f000", the sample banks ([AUDIO.md](AUDIO.md)) |
| 11 | `max98512=1`, then `max98512=2` | "max98512: top (0x39): MAX98512, revision ..." and the bottom one's; their registers |
| 12 | `abox=7`, then `abox=7 max98512=3` | "RDMA0 STATUS each ms" moving and about 192000 bytes a second read; then a 1 kHz tone for 3 s |
| 13 | `tmu=1` | "tmu: 1: gate ... open", each block's "CONTROL ... (CORE_EN 1 ...)", every sensor's "TRIMINFO ... (25 C = NN ...), code NN = NN.0 C" near the room's temperature plus a few; if CORE_EN is 0 or no sensor reads, again with `tmu_enable=1`; if the gate is CLOSED, with `tmu_ungate=1` |
| 14 | `tmu=2` | "tmu: 2: publishing ...", then `sysctl kern.hakios.temp` from the shell (the big zone is the M3s', which cannot be started yet: The cores, above) |
| 15 | `tmu=3 tmu_stop=T`, T a degree or two under the hottest zone run 13 read (40 at least) | within a few seconds "tmu: 3: ... 1 of 3 reads in a row", then "--- tmu: TOO HOT ..." and TWRP with the log: the stop works; later runs keep `tmu=3` at its default 110 |
| 16 | `mali=1` up to `mali=9`, one step a run | "PLL_G3D as found: ... 260.000 MHz" and "B6OUT ... mV"; then "BUCK6 (vdd_g3d) now: ... 0x68 = 950 mV", "the domain is on", "SMC 0x82000410 returned 0", "GPU_ID 0x6...", "reset", "all powered", "the GPU ran it" twice ([The GPU](#the-gpu)) |
| 17 | `bt=1` up to `bt=6`, one step a run (6 needs `fw-bt/bcm4361B2.hcd`) | "UART_BT's clock ... (ratio 2: 200 MHz", the expander's ports and BT_EN, "loopback: all 16 bytes came back", "the chip powered", "manufacturer 000f (Broadcom)", then the patch and the version after it ([BLUETOOTH.md](BLUETOOTH.md)) |
| 18 | `usb_gadget=1` | "usb: exynos9810: PMU USB PHY ...", "CMU_TOP CLKCMU_FSYS0_USB30DRD: ... gate ..." (if SHUT, the next runs add `usb_gadget_clk=1`), "LDO9-14 CTRL: ...", "USBCON as the boot left it", "DWC3 as the boot left it: GSNPSID 5533...", DCTL's RUN_STOP |
| 19 | `usb_gadget=2` | "2a: PMU +0x72C ... -> ...1" to "2l: COMBO_PMA_CTRL ...", none "(NOT as written)"; "USBCON after: ... (SIDDQ 0, line ...)" |
| 20 | `usb_gadget=3` | "3: reset done in N us", "DWC3 set up: ... DCTL ... event buffer ..."; "did not finish in 500 ms" means the PHY gives the link no clock |
| 21 | `usb_gadget=4`, the cable in a Linux host running `dmesg -w` | the host: a new high-speed device 1209:0001 and ttyACM0; the phone: "bus reset 1", "connected at high speed", "setup 1: 80 06 0100 ...", "address N", "configured"; with none, "waiting for a host: line ..." every 10 s (then `usb_gadget_ldo=1`, or `usb_gadget_fs=1`) |
| 22 | `usb_gadget=5`, `-s 300` | the whole log on the host as it is written (above); `help`, `stat`, then `return`: the phone restarts into TWRP and the host's log ends with the run's last lines |

The HSI2C core has no bus recovery: a chip that holds SDA low makes every transfer time out after 1 s. With
`max77705_haptic=1` the MAX77705 driver writes two registers (haptic bits only, read back); without it, it only reads.

## What comes next

| Step | How |
|---|---|
| iOS's brightness slider | a run with `backlight=1` (above) says which key the slider sends; then make it the one taken (`backlight=2`, or the display service's key) |
| Speaker audio | runs 10-12 above; should RDMA0 not move with its CPU off, a firmware mode (calliope booted once, RDMA0's registers read back) or a register dump from Android while sound plays ([AUDIO.md](AUDIO.md)) |
| Bluetooth | stage 1 (power, the UART, HCI_Reset, the patch) is written: `bt=1..6`, run 17 above ([BLUETOOTH.md](BLUETOOTH.md)); stage 2, iOS's side, needs research into what `bluetoothd` opens first |
| Wi-Fi | stage 1 (the link) and stage 2 (brcmfmac, INTx, the phone's address, the station, joining) are written: `wifi_pcie=1..6`, then `brcmfmac=1..8`, one run each ([WIFI.md](WIFI.md)); not yet run |
| A longer log | USB is written (`usb_gadget=5`, runs 18-22 above); a partition of the phone's would keep one without a host |
| Storage, writing | /private/var kept between runs needs a writable partition of the port's own (the POCO's `darwin`) |
| Buttons | GPIO keys: a driver, the pins from `gpio_keys` |
| The M3s | the ISA question above, then a loader that numbers two clusters |
