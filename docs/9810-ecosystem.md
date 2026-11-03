# The Exynos 9810 ecosystem: what HakiOS can reuse

A survey of the public code for the Exynos 9810 (Galaxy S9 `starlte`, S9+ `star2lte`, Note9 `crownlte`, and the
Galaxy Tab Active3 `gtactive3wifi`, which has the same SoC), done on 2026-11-03. It covers GitHub, GitLab, upstream Linux
and the linux-samsung-soc patch trail. Each project below was read through the GitHub/GitLab APIs and, where it
mattered, file by file. Nothing was copied into this repository.

**Licence paths used below.** HakiOS's code is APSL 2.0 (the kernel) and MIT (user space).
- **direct**: the licence is permissive (BSD, MIT, Apache 2.0, or a dual "GPL-2.0 OR BSD-3-Clause"), so code can be
  ported, with attribution.
- **facts**: the source is GPL. We read it for register addresses, fields, sequences and measurements, and write our
  own code, the way the drivers already cite ExyHyperBrick's kernel.
- **no**: the project depends on Android vendor blobs or Halium, adds nothing new, or has no licence.

**What HakiOS already has**, so that we don't count it as new: touch (S6SY761), MAX77705 battery, charger and haptics,
the S6E3HA8 panel through DECON and DPP, Mali-G72 through Mesa Panfrost, ACPM DVFS and the CPU governor, TMU, UFS,
DWC3 gadget, PCIe and brcmfmac (scan), the front camera, the RTC, firmware-less ABOX playback to the MAX98512s, and
the M3 PMU defaults. The M3 defaults and the G3D rail and PLL facts already come from SheroAbi's S9+ port; see
`drivers/core/hakios.exynos_m3.c` and `drivers/gpu/hakios.mali.c` in the kernel repository.

## Who has a working Exynos 9810 mainline kernel

| Community | Device | What works on mainline | Licence |
|---|---|---|---|
| **exynos-linux** ([samsung-gtactive3wifi](https://github.com/exynos-linux/samsung-gtactive3wifi), maintainer `@dixonSolutions`, Discord `discord.gg/exynos-linux`) | Tab Active3, SM-T570 | all 8 cores (M3s at boot), CPU+GPU DVFS through ACPM, Panfrost, own DPU KMS, UFS, rear+front cameras (CSIS → libcamera soft ISP), A-Box audio (speaker, mic, jack), accelerometer through the sensor hub, Wi-Fi (BCM4375 PCIe), suspend-to-idle; Bluetooth, S Pen, NFC drivers load. 152 kernel patches, the most complete 9810 work anywhere | GPL-2.0 |
| **SheroAbi** ([galaxy-s9plus-mainline-linux](https://github.com/SheroAbi/galaxy-s9plus-mainline-linux)) | S9+, SM-G965F | Linux 7.1 + Ubuntu/GNOME: 8 cores, UFS, DECON KMS at 60 fps, Panfrost, G3D DVFS, CPU DVFS (both clusters), PCIe Wi-Fi, USB DRD PHY, MAX77705 charger, watchdog. No audio, camera, modem, BT or suspend | GPL-2.0-only |
| **Upstream Linux** (Markuss Broks and Maksym Holovach, in mainline since 6.14) | S9, SM-G960F | `exynos9810.dtsi` + `exynos9810-starlte.dts`: CPUs, GIC, PMU, pinctrl, chipid, simple-framebuffer, gpio-keys. Pinctrl tables are in `pinctrl-exynos-arm64.c` | **dts: GPL-2.0 OR BSD-3-Clause**; drivers GPL-2.0 |
| **ntdevlabs** ([exynos9810-woa](https://github.com/ntdevlabs/exynos9810-woa)) | S9+ | Windows 11 ARM64: own UEFI with ACPI tables, UFS, HSI2C and touch drivers | **BSD-2-Clause-Patent** (touch GPL-2.0) |
| **ivoszbg** ([uniLoader](https://github.com/ivoszbg/uniLoader)) | many Exynos | the S-Boot → mainline shim that both Linux ports use (`board-starlte.c`) | GPL-2.0 |

None of the ports runs the Shannon modem, the ISP proper, MFC, G2D, the fingerprint reader, the iris camera or the
wireless charger.

## The survey table

| # | Source | Licence | What it covers, maturity | HakiOS use | Helps |
|---|---|---|---|---|---|
| 1 | [exynos-linux/samsung-gtactive3wifi](https://github.com/exynos-linux/samsung-gtactive3wifi) `docs/re/bigcores.md` | GPL-2.0 (docs are facts) | M3 power-up path, measured on hardware: the S-Boot cluster-1 power-off, PSCI CPU_ON only writing `CLUSTER1_CPUn_CONFIGURATION`, the APM's flexPMU **GRP1** wake (PMU interrupt generator 0x14070000, enable 0x100, pending 0x108, bits 0-3 = CPU4-7), `CPU_INFORM` at PMU 0x860+4n (must be 1..3, bit 16 clear), `RESET_LPI_TIMEOUT` 0x420 and `WDTRESET_LPI` 0x418, and "never write `CRP_PM_CC1_0`". It also records a late-onlined M3 dying at its first LSE atomic. All 8 CPUs boot when the LPM settings are in place before the first CPU_ON | facts | 8 cores: the 2 missing M3s (`cpus=6`), hotplug |
| 2 | same, `docs/re/bigcores.md` "DVFS tables" + patches 0099-0102, 0127, 0139 (`clk-acpm` for 9810) | GPL-2.0 | The APM's fvmap level tables: CPUCL1 (M3) 2886-598 MHz, CPUCL0 2002-208 MHz, G3D 598-260 MHz, MIF and INT. DVFS goes on ACPM **channel 0** (channel 5 is the APM's notify-only buffer), requests round down to a table level, measured | facts | M3 DVFS, GPU DVFS, MIF (memory bandwidth) |
| 3 | [SheroAbi/galaxy-s9plus-mainline-linux](https://github.com/SheroAbi/galaxy-s9plus-mainline-linux) `src/soc/s9p-g3d.c`, `s9p-g3d-pd.c`, `src/cpufreq/s9p-cpufreq.c`, `docs/01-hardware.md`, `05-performance.md`, `06-known-issues.md` | GPL-2.0-only | Working G3D DVFS: three caps (devfreq request, TMU cap, user ceiling), BUCK6 raised to 950 mV before the GPU runs, the PLL_G3D relock (`PLL_CON2 = 0x30000003`). CPU DVFS for both clusters with a busy-core rule and thermal caps (a single M3 at 2.7 GHz reaches 90 °C in 2 minutes). Validated ceilings: M3 2327 MHz, A55 1499 MHz. CPU idle states hang (documented) | facts (already the source of `hakios.mali.c`) | GPU perf/DVFS, M3 DVFS, thermal policy |
| 4 | same repo, `05-performance.md` | GPL-2.0-only | The scan-out must be below 4 GB (DECON's address is 32-bit); 320 MiB CMA. Page flips must wait for the frame end; 60 fps panel path; glmark2 840 → 1025 | facts | display/GPU perf |
| 5 | exynos-linux patch 0151 `drm/panfrost: Use AArch64 page tables on the Exynos9810` | GPL-2.0 | The legacy LPAE Mali page-table format reads stale data on G72 r0p1 (5-6 of 10 runs fault); with AArch64 tables 230 of 230 runs pass. Patch 0150: unmask the MMU interrupts at init | facts (HakiOS already uses AArch64 tables, `as0_update`; this confirms it and rules out a regression) | GPU stability |
| 6 | exynos-linux patches 0105-0110 (`ASoC: samsung: Add Exynos9810 A-Box firmware-less driver`, 44 KB) + `docs/re/abox.md` | GPL-2.0 | A firmware-less A-Box ASoC driver. The RDMA/WDMA register layout was recovered from calliope's own accessors (CTRL0 fields, BUF_STR/END/OFFSET, STR_POINT, VOL, SBANK, status). Routes are UAIFn → NSRCn → WDMAn+1 for **capture**. The DMA IRQs only reach the A-Box GIC, so periods are hrtimer-emulated. PLL_AUD 1179.648 MHz. Speaker, mic and headphone work on the tablet (codecs RT5665/RT5510, not ours) | facts | audio: **microphone/WDMA capture**, period timing; playback already done |
| 7 | Upstream `drivers/mfd/madera-*.c`, `sound/soc/codecs/cs47l92.c` | GPL-2.0 | The Cirrus Madera MFD knows **CS47L93** (`cirrus,cs47l93`); the cs47l92 codec driver covers it: register map, DSP and FLL sequences. The S9's DT has `samsung,star-madera` + `cirrus,cs47l93` | facts | audio: the CS47L93 codec (headset, earpiece, mics) |
| 8 | exynos-linux `docs/re/sensorhub.md` (45 KB) | GPL-2.0 | The Broadcom GNSS + sensor-hub path (`bbdpl`): message layouts, constants and sequences, from Samsung's GPL `drivers/sensorhub/brcm/`, cross-checked against the **Galaxy S9's copy**. The S9's DT has `ssp,BCM4773` on SPI, the same family as the tablet's BCM4775 | facts | sensors: accelerometer, gyro, compass, light, proximity; GPS |
| 9 | exynos-linux `docs/CAMERA.md` (23 KB), `pmos/duranium-build/0030-...cameras-media-CSIS...patch`, `patches/libcamera/*` | GPL-2.0 (kernel); libcamera patches LGPL-2.1 | CSIS raw capture without the ISP: CSIS at 0x16230000/0x16250000 on the tablet (check the S9's DT), the DMA PACK12 container layout (2 px in 3 bytes, 16-byte stride), black level 64 (10-bit), sensor LDOs through ACPM, SysMMU ISPPRE in bypass, rear and front at 30 fps. Soft ISP (libcamera `simple` pipeline) with AGC and contrast AF | facts (kernel); the libcamera soft-ISP ideas apply to our user space | rear cameras (2L3, 3M3) without fimc-is; AF |
| 10 | exynos-linux patches 0067-0071, 0073 (UART + BT) | GPL-2.0 | Exynos9810 UART support; **USI reset**: `UART_BT`'s USI wrapper holds the IP in reset (USI_CON 0x108400c4 = 1), so release it (assert, release, `USI_OPTION.CLKREQ_ON`) before any other write, and again on resume. `hci_bcm` binding | facts | Bluetooth (BCM4361 is on a UART on the S9) |
| 11 | exynos-linux patch 0119 `scsi: ufs: exynos: Use a 32-bit DMA mask on Exynos9810` | GPL-2.0 | UFS descriptors or buffers above 4 GB (DRAM 0x880000000) give a System Bus Fatal Error (IS bit 17); Samsung uses a 32-bit mask | facts | 4 GB RAM: a DMA-below-4 GB rule for UFS (and DECON, camera WDMA, A-Box) |
| 12 | exynos-linux patches 0095-0098 (`clk-exynos9810`, 157 KB, CMU_TOP + leaves, all CMUs incl. ISP*, MFC, G2D, IVA, DSP*, AUD, FSYS, PERIC) + `tools/cal2clk*` | GPL-2.0 | The clock tree generated from Samsung's CMUCAL tables, read-only (it reads the rates, it doesn't set them) | facts | MFC, G2D, ISP, IVA bring-up (clocks); any rate question |
| 13 | exynos-linux patches 0080-0087 (`pmdomain: samsung: Add Exynos9810`) | GPL-2.0 | Power domains (G3D first) and the "keep on during bring-up" logic | facts | GPU, MFC, ISP, AUD power |
| 14 | exynos-linux patches 0024-0025, 0140, 0141-0143 | GPL-2.0 | TMU sensor driver, LITTLE-cluster throttling, the Exynos9810 ADC (battery thermistor) | facts | thermal (cross-check of `hakios.exynos_tmu.c`), battery temperature |
| 15 | exynos-linux patches 0016-0019, 0137-0138, `docs/re/suspend.md` (23 KB) | GPL-2.0 | S2MPS18 over ACPM (read-only), CPU idle/hotplug PMU hints, core power-down idle states, the suspend investigation (s2idle works on the tablet, C2 hangs) | facts | power: idle, hotplug, sleep |
| 16 | exynos-linux `docs/re/fingerprint.md` (30 KB), `fp-gps-camera.md` | GPL-2.0 | The fingerprint path on the tablet (a different sensor from the S9's `etspi,et5xx`; the SPI and TrustZone constraints carry over) | facts (limited) | fingerprint (feasibility) |
| 17 | exynos-linux patches 0040-0041 (`wacom_w9000: Add W9019`) | GPL-2.0 | Wacom W90xx I2C digitiser support (the tablet's S Pen) | facts | Note9 S-Pen (a Wacom W90xx-family digitiser: check the crownlte DT) |
| 18 | exynos-linux patches 0064-0065, 0072 (`PCI: dwc: Add Samsung Exynos9810 PCIe Gen2`, 24 KB) + SheroAbi `src/pci/pcie-exynos9810.c` | GPL-2.0 | PCIe RC for brcmfmac: INTx not MSI, no `dma-coherent`, BCM4361 RAM base 0x170000, link-timeout guard | facts | Wi-Fi past scan (already used) |
| 19 | [ntdevlabs/exynos9810-woa](https://github.com/ntdevlabs/exynos9810-woa) `drivers/Exynos9810Ufs`, `drivers/Exynos9810Hsi2c` | **BSD-2-Clause-Patent** (HSI2C also MS-PL) | Windows KMDF UFS and SpbCx HSI2C drivers, proven on the S9+ | **direct** (an alternative implementation and cross-check; we have both drivers) | UFS/I2C robustness |
| 20 | same, `firmware/Platform/Star2LtePkg/AcpiTables` (MADT, PPTT, GTDT, DSDT, HSI40 SSDT), `Exynos9810Pkg` | **BSD-2-Clause-Patent** | ACPI description of the 9810: GIC-400 GICD/GICC/GICH/GICV (0x10101000/2000/4000/6000), both clusters' MPIDRs and topology (PPTT), HSI2C bus 40 at 0x14360000 IRQ 38 with the MAX77705 at 0x66/0x25, a framebuffer DXE, GPIO handoff | **direct** | device tree / topology for 8 cores, MAX77705 bus |
| 21 | Upstream `arch/arm64/boot/dts/exynos/exynos9810.dtsi`, `exynos9810-starlte.dts`; the `exynos9810.dtsi` additions in exynos-linux patches 0011, 0030, 0032, 0055, 0083, 0093, 0097, 0109 | upstream dts **GPL-2.0 OR BSD-3-Clause**; the patches follow the file they patch | A clean, reviewed SoC description (CPUs with `samsung,mongoose-m3`, the PMU, pinctrl, chipid) and bindings. Patch 0093 adds CPU capacities (M3 1024, A55 318) | **direct** for the upstream dts; facts for the patch series | the platform layer, scheduler capacities |
| 22 | [Project-Silicium/Mu-Silicium](https://github.com/Project-Silicium/Mu-Silicium) `S5E9810Pkg`, `starltePkg` | BSD-2-Clause | Our UEFI (already used) | direct (in use) | — |
| 23 | [Project-Silicium/Carbon-Hypervisor](https://github.com/Project-Silicium/Carbon-Hypervisor) | GPL-2.0 | EL2 + PSCI for Exynos (in use as `Hyp.bin`) | binary in use; facts | PSCI/hotplug: where CPU_ON/OFF goes |
| 24 | [FirmWire/FirmWire](https://github.com/FirmWire/FirmWire) | **BSD-3-Clause** | An emulator for Shannon basebands: the TOC/boot image loader, the memory map, the SoC peripherals the CP firmware expects. It is a research tool, not a host driver | **direct** (loader/TOC parsing) + facts | the Shannon modem: parsing the `modem.bin` TOC, its load addresses |
| 25 | vendor 4.9 kernels: [ExyHyperBrick](https://github.com/ExyHyperBrick/android_kernel_samsung_exynos9810) (our BSP fork), [exynos-linux-stable/starlte](https://github.com/exynos-linux-stable/starlte), crownlte, [duhansysl/exynos9810-kernel](https://github.com/duhansysl/exynos9810-kernel), Apollo, jesec, krazey, … (~60 forks) | GPL-2.0 | Samsung's BSP (fimc-is, MFC v10, G2D, abox, `modem_if`/`cbd`, `sec_nfc`, `ssp`, `etspi`, `idt,mfc-charger`, `s2mpb02` camera PMIC) | facts (already our source) | everything not covered above: MFC, G2D, MFC wireless charger, iris |
| 26 | Upstream `drivers/nfc/s3fwrn5/` | GPL-2.0 | Samsung NFC (NCI) over I2C/UART. The S9 has Samsung's `sec-nfc` at I2C 0x27 (chip model to confirm against the vendor driver), with `ven`, `irq`, `firm` and `clk_req` GPIOs | facts | NFC |
| 27 | LineageOS trees (`android_device_samsung_*`, Apache-2.0) | Apache-2.0 | configs: audio policy, firmware names, init | direct for data (e.g. the firmware list) | small |
| 28 | [Sexynos/adaptation-droidian-exynos9810](https://github.com/Sexynos/adaptation-droidian-exynos9810), UBports community port ([GitLab](https://gitlab.com/ubports/porting/community-ports/android10/samsung-galaxy-s9/samsung-exynos9810)), PixelExperience/crDroid/UN1CA trees | mixed | Halium/Android user spaces on vendor blobs | no | — |
| 29 | [parukovvadim/ios-crownlte](https://github.com/parukovvadim/ios-crownlte) | none stated (derives from HackiOS) | another iOS 16 on Note9 attempt: shim probes for display, PMIC, SMP, touch, UFS. Early | no (no licence; nothing ahead of us). The Note9 DECON trigger (`0x16030070 = 0x1281`) is a datum to check | Note9 port |
| 30 | [nergzd723/elixir9810](https://github.com/nergzd723/elixir9810), `linux-star` | GPL / empty | an old vendor kernel and an empty tree | no | — |

## Top 10 reuse opportunities, prioritised

Effort: S = days, M = 1-2 weeks, L = more.

| # | Item | Source | Licence path | Effort | Why first |
|---|---|---|---|---|---|
| 1 | **All 8 cores**: bring up the two missing M3s, then hotplug | exynos-linux `docs/re/bigcores.md` (GRP1 wake, `CPU_INFORM`, LPM before the first CPU_ON, the LSE-atomic death of a late-onlined M3, `RESET_LPI_TIMEOUT`), SheroAbi `patch_tree.py` (the six PMU writes, already in `hakios.exynos_m3.c`) | facts | M | It's the biggest jump in CPU capacity (M3 capacity 1024 against the A55's 318), and the tablet port has measured it working |
| 2 | **M3 and MIF DVFS** with real tables | exynos-linux fvmap tables + `clk-acpm` patches (channel 0, rounding down), SheroAbi `s9p-cpufreq.c` (busy-core rule, thermal caps, validated ceilings 2327/1499 MHz) | facts | S | `hakios.exynos_acpm.c` already speaks channel 0, so this is mainly tables and policy |
| 3 | **GPU DVFS / performance** | SheroAbi `s9p-g3d.c` (min of devfreq, TMU and user caps; BUCK6 before the rate goes up), G3D fvmap 598-260 MHz, exynos-linux `pmdomain` 0081/0087, SheroAbi `05-performance.md` (flip at frame end, buffers below 4 GB) | facts | S-M | The PLL switch and rail are already in `hakios.mali.c`; what's missing is a load-driven governor with a thermal cap, and the MIF floor while the GPU is busy |
| 4 | **Use all 4 GB of RAM** safely | exynos-linux 0119 (UFS needs DMA below 4 GB), SheroAbi (DECON 32-bit), our own camera WDMA note | facts | M | Give XNU the 0x80000000-0xFFFFFFFF RAM as well as the 2 GB at 0x880000000, with a below-4 GB pool for UFS, DECON, camera and ABOX DMA |
| 5 | **Audio capture + CS47L93** | exynos-linux A-Box 0106 (WDMA layout, NSRC routing, hrtimer periods), upstream madera/cs47l92 (CS47L93) | facts | M (mic via WDMA) / L (CS47L93 earpiece and headset) | Playback works; the mic and calls need WDMA and the codec |
| 6 | **Bluetooth over UART** | exynos-linux 0068/0073 (USI reset sequence, UART variant), 0070 (`hci_bcm`), SheroAbi `hciattach-bcm4361.service` + `bcm4361B2_semco.hcd` (already in `firmware/bt/`) | facts | S | The likely reason a BCM UART won't answer is the USI reset; this is a small fix |
| 7 | **Sensors** (accelerometer, gyro, compass, light, proximity) | exynos-linux `docs/re/sensorhub.md` (bbdpl protocol, written against the S9's copy too); S9 DT `ssp,BCM4773` on SPI | facts | L | One protocol gives every sensor and GPS; it's needed for auto-rotation |
| 8 | **Rear cameras without fimc-is** | exynos-linux `CAMERA.md` + CSIS patch + libcamera soft-ISP (AGC, contrast AF) | facts (kernel); LGPL ideas (user space) | M | The same raw-CSIS route as our front camera; the 2L3/3M3 sensor init comes from the BSP. Dual-pixel AF is not needed for a first picture |
| 9 | **Platform description from permissive sources** | upstream `exynos9810.dtsi` (GPL-2.0 OR BSD-3-Clause), ntdevlabs ACPI tables (BSD-2-Clause-Patent: MADT/PPTT/GTDT, HSI40 + MAX77705), exynos-linux CPU capacities (facts) | **direct** | S | It can be copied as is: cluster topology and capacities for XNU's scheduler (P/E cores), GIC, HSI2C 40 |
| 10 | **Shannon modem: image loading** | FirmWire (BSD-3-Clause: TOC parsing, load map), vendor `modem_if` (facts) | **direct** + facts | L | It's the only permissive modem code in the whole ecosystem; it fits `docs/modem-plan.md`'s first step (put the CP image in `modem_if` and start it) |

Also worth a look, but not in the top 10: NFC through the upstream `s3fwrn5` facts (S), the Note9 S-Pen through the
Wacom W90xx patch (M, needs a Note9), the TMU/ADC cross-check (S), the clock tree tables before any MFC/G2D/ISP work
(S, reference), and the WoA UFS driver as a second implementation (BSD) for when the UFS gear or power mode misbehaves.

**Nothing usable found** for: the MFC video codec and G2D (only the vendor kernel), the ISP pipeline proper (fimc-is
is vendor-only, and no mainline port runs it), DSP/IVA, the iris camera, the fingerprint sensor on the S9 (`etspi,et5xx`,
TrustZone), and the MFC wireless charger (`idt,mfc-charger`: vendor driver only).

## How to follow these sources

The exynos-linux port is moving fastest: 152 kernel patches, most of them from October 2026, written with an AI-assisted workflow
and measured notes in `docs/re/`. Its `docs/STATUS.md` and `PLAN.md` are worth re-reading each week. When a fact
from it lands in a HakiOS driver, cite the patch number and the file, as the drivers already do for SheroAbi's port
and ExyHyperBrick's kernel.
