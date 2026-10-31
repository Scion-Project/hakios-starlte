# Wi-Fi on the Galaxy S9

The S9's radio is a Broadcom BCM4361 (a module by Murata or Samsung Electro-Mechanics) on PCIe channel 0 of the Exynos
9810. Android drives it with Broadcom's own driver, bcmdhd (GPL), through Samsung's root-complex driver
(`drivers/pci/host/pci-exynos.c`). Neither can come into this tree. The plan is in two stages.

## Stage 1: the link (written, not yet run)

`drivers/wifi/hakios.exynos_pcie.c` in the common repository (`CONFIG_HAKIOS_EXYNOS_PCIE`, built into the S9's kernel,
off until `wifi_pcie=N`). It goes as far as Android's `exynos_pcie_poweron()` does before Linux's PCI core takes over:

| Step | What | Expected on the phone |
|---|---|---|
| 1 | reads only: the PMU's PHY isolation, CMU_FSYS1's gates and Q-channels of the Gen2 controller, the five pins | no gate `CLOSED`; WLAN_REG_ON (gpg0-5) CON 1 or 0, PERST# (gpf2-2) low |
| 2 | PERST# low, CLKREQ# to the controller, WLAN_REG_ON high, 200 ms (Samsung's `dhd_custom_exynos.c`) | `WLAN_REG_ON ... DAT 1` |
| 3 | the PHY out of isolation and power-down, the core's soft reset, PERST# high, the PHY's tables (26 MHz, Gen2), the resets of PCS, PMA, MAC and CDR | `PHY PLL 3` (Samsung's own check calls bits 1:0 set a lock); the core's own ID, not all ones (Android rewrites it to 144d:ecec, this does not) |
| 4 | the root complex set up (x1, Gen2), the LTSSM let go, 20 ms for L0, up to `wifi_pcie_tries` (3) times | `LINK UP after N us (state 11): Gen2 x1` |
| 5 | the endpoint's ID, class and capabilities through the iATU; every BAR sized and placed in 0x11800000-0x127EFFFF | `1:00.0 is 14e4:441f (Broadcom)`, two 64-bit BARs (Broadcom's: 32 KB of registers, then the chip's RAM window, a few MB) |
| 6 | 1:00.0's memory decoding on (command bit 1), and the device handed to stage 2's driver (below) | `command/status now ...0002`; then `brcmfmac:` lines |

Every step says what it does before it does it. A link that does not come up is put back (PERST# low, the LTSSM off,
WLAN_REG_ON low) and the LTSSM's history is printed (32 states, oldest first). Nothing writes a PMIC. A CMU gate that is
closed stops step 3 before the controller is touched; `wifi_pcie_ungate=1` forces it open.

The first runs, one per image, each read from pstore afterwards (README.md, "On the phone"):

```sh
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=1     # a look
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=2     # the radio's power
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=3     # the PHY
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=4     # the link
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=5     # the chip's ID and BARs: stage 1 done
```

Every line of the driver starts with `exynos_pcie:`. What to compare against: Android's own boot log
(`adb shell su -c dmesg | grep -i pcie`) has `exynos_pcie_establish_link: Link up:11` (or similar),
`Current Link Speed is GEN2`, and `lspci`-like facts in `/sys/bus/pci/devices/0000:01:00.0/{vendor,device,resource}`.
Read those once from Android before the first run: they are the numbers step 5 should print.

## Stage 2: the radio (first slice written, not yet run)

Linux's **brcmfmac**, Broadcom's ISC-licensed FullMAC driver, on the scheme the POCO's ath11k uses: compiled unmodified
but for one patch, on FreeBSD's LinuxKPI headers and our `wifi/lx`, and tied into one object the kernel links, which
shows only `lx_prepare()`, `lx_start()`, `lx_stop()` and `lx_transmit()`. What is written, in the common repository:

| Where | What |
|---|---|
| `tools/mk-brcmfmac.sh` | the twin of `mk-ath11k.sh`: brcmfmac, brcmutil and their headers from the same pinned Linux (7.0.14), every file's ISC licence checked, `wifi/lx/brcmfmac/patches/bcm4361.patch` applied; 24 of brcmfmac's files built (`pcie.c`, `chip.c`, `firmware.c`, `core.c`, `msgbuf.c`, `commonring.c`, `flowring.c`, `fwil.c`, `fweh.c`, `feature.c`, `cfg80211.c`, `p2p.c` and the rest; no SDIO, USB or BCDC); `out/brcmfmac.o`. Only `debug.c`'s three debugfs functions are stubs |
| `wifi/lx/brcmfmac/patches/bcm4361.patch` | the BCM4361 in brcmfmac: PCI device 0x441f in its table; chip IDs 0x4361 and 0x4347 (the chip says one or the other: bcmdhd's `dhd_validate_chipid()`); RAM base 0x170000 for both (`CR4_4347_RAM_BASE`); firmware `brcmfmac4361b0-pcie` for revisions 3 and 4 (B0, B1), `brcmfmac4361b2-pcie` from 5 (B2); and the two lines where `brcmfmac=N` stops it (by returning, leaving things as they are: brcmfmac's way of failing would reset the chip) |
| `wifi/lx/brcmfmac/lx_pci.c` | the `struct pci_dev`: configuration space a word at a time through the kernel, the BARs where stage 1 put them, the PCI driver registered and the device probed as Linux's PCI core would, and the interrupt: brcmfmac's handler called by a thread every `brcmfmac_poll_ms` (2) ms, since MSI is off here and INTx (SPI 253) is not attached yet |
| `wifi/lx/brcmfmac/lx_kpi.c`, `lx_brcmf.c` | what else brcmfmac asks of LinuxKPI (firmware in the background, a wiphy and a net_device as memory, cfg80211's channel arithmetic), and the steps |
| `drivers/wifi/hakios.brcmfmac.c` (`CONFIG_HAKIOS_BRCMFMAC`) | the kernel's side: the log, the options, the files from `fw/`, memory shown to the chip at its physical address; `lx_os_pci_*()` on `sys/hakios.exynos_pcie.h` |
| `drivers/wifi/hakios.exynos_pcie.c` | `wifi_pcie=6`: memory decoding on, the device handed to the driver |
| `drivers/wifi/hakios.lx.c` (`CONFIG_HAKIOS_LX`) | unchanged, now a driver of its own that both radios' drivers require |
| `tools/brcmfmac-test.py` | host checks: the configuration-space arithmetic; for both chip IDs and every revision, the firmware name the patched table gives; the RAM base; the device table |

DMA comes from `lx_os_radio_memory()` (44 MB in one physical piece, uncached), shown to the chip at its physical address.

### The steps

`wifi_pcie=6 brcmfmac=N`, each line said before it is done; every line of this stage starts with `lx:`, `brcmfmac:` or
brcmfmac's own (`brcmfmac_debug=MASK`, `0x180004` by default: INFO, PCIE, FWCON).

| Step | What | Expected on the phone |
|---|---|---|
| `brcmfmac=1` | the pci_dev, brcmfmac's PCI driver and its probe: BAR0 and BAR1 mapped, bus mastering on, the chip's ID and cores through BAR0's window; the firmware is asked for and never given | `lx: pci: 1:00.0 is 14e4:441f, class 0280xx`; `lx: pci: brcmfmac's probe of 1:00.0`; brcmfmac's line for the chip (4361 or 4347, and its revision: 5 for B2) and its cores (ARM CR4, PCIe2 Gen2 rev, ...); `stops before step 2`; `the probe returns 0` |
| `brcmfmac=2` | ... the files asked for and found | `lx: the driver asks for the file "brcm/brcmfmac4361b2-pcie.bin": there` (and `.txt`, `.clm_blob`; `.txcap_blob` is not there and need not be); `stops before step 3` |
| `brcmfmac=3` | ... the firmware and NVRAM into the chip's RAM through BAR1, its processor started, its shared area read, the rings set up | brcmfmac's `Shared RAM addr: 0x...` and `PCIe protocol version` 5 to 7; the firmware's console (`FWCON`) printing its version; `stops before step 4` |
| `brcmfmac=4` | ... the chip's interrupt (a thread that looks), and `brcmf_attach()`: the first command over the rings, which is the first time the chip reads and writes memory (DMA), the events, cfg80211's wiphy | `Firmware: BCM4361/5 wl0: ... version ...`; `lx: cfg80211: band 0: 14 channels`, `band 1: ...`; `the wiphy is registered` |

### The first runs

One image a run, read from pstore afterwards (README.md, "On the phone"). Stage 1 first, as above, up to
`wifi_pcie=5`; then:

```sh
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6                 # hand-over only: "not started (brcmfmac=N)"
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=1      # the chip's ID through BAR0
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=2      # needs fw-wifi/ (below)
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=3      # the firmware up
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=4      # its interface: the first DMA
```

The kernel has the driver only if `tools/mk-brcmfmac.sh` ran before it was built; one built without says
`THE DRIVER IS NOT BUILT IN`. What to look at when a step fails:

- 1: no line `brcmfmac's probe`: the device table's class match (`0x0280xx`) against what stage 1 read. `brcmf_chip_attach`
  failing: BAR0's window (config 0x80) not taking, or the chip in reset (PERST#, WLAN_REG_ON).
- 2: a file `not there`: its name in `fw-wifi/` (below). If the revision is neither 3, 4 nor 5 and up, there is no line
  for it: the log has the chip's revision, and the patch's table is where to add it.
- 3: `Invalid shared RAM address` or no answer in 5 s: Samsung's firmware not starting under brcmfmac's download (it
  writes a random seed only for `WCC_SEED` chips; bcmdhd's own steps before the download are where to look next).
  `Unsupported PCIE version`: the firmware's msgbuf revision is outside brcmfmac's 5 to 7.
- 4: the first command timing out (`brcmf_msgbuf_query_dcmd: Timeout on response`): the chip cannot reach memory. That is
  the open question of the PCIe SysMMU (0x11420000) and the controller's inbound path; the next step is then to look at
  whether Android's SysMMU leaves the controller's stream in bypass, and at SYSREG_FSYS1 +0x700 (I/O coherency).

### What remains

- The station above it: brcmfmac registers with cfg80211, not mac80211. A cfg80211 stand-in for this radio (scan
  through `cfg80211_ops.scan`, `cfg80211_inform_bss`, `.connect`), then `WIFI_STA`'s ops on it, as `lx_80211.c` does for
  the POCO; the four-way handshake by the firmware (`BRCMF_FEAT_FWSUP`, if Samsung's firmware has "sup") or by
  `lx_wpa.c`. `lx_transmit()` answers `ENETDOWN` until then.
- The interrupt: INTx on SPI 253 through ELBI's `PCIE_IRQ_PULSE` (INTA bit 0, enabled in `PCIE_IRQ_EN_PULSE` 0x00C) in
  place of the thread that looks; the S9's GIC is not the POCO's.
- The phone's MAC address (`/efs/wifi/.mac.info`); brcmfmac takes the NVRAM's or the OTP's until then.
- Taking it down: `lx_stop()` is written but nothing on the S9 calls it on the way back to the loader yet; the restart
  takes the radio's power with it.

### The files from the phone

Pulled from the user's own phone, never committed. LineageOS has them in `/vendor/firmware/`; Samsung's Android in
`/vendor/etc/wifi/`. Look in both:

| The phone's file | What | In `fw-wifi/` as |
|---|---|---|
| `bcmdhd_sta.bin_b2` (`_b0`) | the station firmware of the chip's revision (the S9's is expected to be B2: its Bluetooth patch is `bcm4361B2_*.hcd`) | `brcmfmac4361b2-pcie.bin` (`brcmfmac4361b0-pcie.bin`) |
| `nvram.txt_r02a_b2`, `nvram.txt_r02b_b2`, `nvram.txt_murata_r041_b2` ... | the board's NVRAM; bcmdhd chooses one by the module `/data/.cid.info` names | the one `.cid.info` names, as `brcmfmac4361b2-pcie.txt` |
| `bcmdhd_clm.blob` | the regulatory data (CLM), downloaded after the firmware | `brcmfmac4361b2-pcie.clm_blob` |
| `/data/.cid.info` | which module this phone has ("murata", "semco" and a revision), written by bcmdhd from the chip's OTP at first boot | (to choose the NVRAM) |
| `/efs/wifi/.mac.info` | the phone's MAC address | (not used yet) |

Not needed: `bcmdhd_mfg.bin_*` (factory test) and `bcmdhd_mon.bin_*` (monitor mode). To list them:
`adb shell su -c 'ls -l /vendor/firmware /vendor/etc/wifi; cat /data/.cid.info /efs/wifi/.mac.info'`.
`userland/build.sh` puts every `fw-wifi/brcmfmac4361*-pcie.*` into the small image's `fw/`, where the kernel finds them.

Sources: the S9's kernel at e5906667068e (`drivers/pci/host/pci-exynos*.c`,
`drivers/net/wireless/broadcom/bcmdhd_101_12/dhd_custom_exynos.c`, `dhd_custom_cis.c`, `include/bcmdevs_legacy.h`,
`dhd_linux.c`, `dhd_pcie.c`, `include/sbchipc.h`), the
exynos9810-common device and vendor trees (`proprietary-files.txt`, `exynos9810-common-vendor.mk`), Silicium's
`starlte.dts`.
