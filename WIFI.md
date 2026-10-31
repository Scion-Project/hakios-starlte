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

## Stage 2: the radio (the plan)

### How the existing Wi-Fi stack would take it

The POCO's Wi-Fi works through a Linux driver compiled unmodified: Linux's ath11k on FreeBSD's LinuxKPI headers and our
`wifi/lx` layer (`tools/mk-ath11k.sh`), tied into one object the kernel links, which shows only `lx_start()`. Underneath
are `drivers/wifi/hakios.lx.c` (memory, time, threads, the one lock) and `wifi/lx/src/lx_bus.c` (the radio's bus, standing
in for ath11k's `ahb.c`). Above is `lx_80211.c` (the stand-in for mac80211 and cfg80211, with a station that scans and
joins one WPA2 network, `lx_wpa.c` doing the four-way handshake), then `WIFI_STA` (`hakios.sta.c`,
`hakios.apple80211.c`, `hakios.wlan.cpp`): the Apple80211 surface iOS's wifid talks to, which already works over
"whichever link is below".

For the S9 the same scheme takes Linux's **brcmfmac**, Broadcom's ISC-licensed FullMAC driver, from the same pinned Linux:

1. `tools/mk-brcmfmac.sh`, the twin of `mk-ath11k.sh`: brcmfmac's `pcie.c`, `msgbuf.c`, `commonring.c`, `flowring.c`,
   `core.c`, `bus`/`proto` glue, `chip.c`, `firmware.c`, `fwil.c`, `fweh.c`, `feature.c`, `cfg80211.c` on the same
   LinuxKPI and `wifi/lx`. No SDIO, USB or BCDC.
2. The bus: a `struct pci_dev` in `wifi/lx` backed by `hakios.exynos_pcie.c` through a small header
   (`sys/hakios.exynos_pcie.h`, to be written): configuration reads and writes of 1:00.0 through the iATU, the two BARs
   mapped (`ml_io_map` of the addresses step 5 placed them at), `pci_set_master` (the command register's bits 1 and 2),
   and the interrupt. MSI is off on this root complex (`use-msi = "false"`), so it is INTx: SPI 253 (GIC INTID 285),
   level, raised through ELBI's `PCIE_IRQ_PULSE` (INTA is bit 0, enabled in `PCIE_IRQ_EN_PULSE`, cleared by writing it
   back). Or, first, a thread that polls, as `lx_bus.c` did for ath11k before its interrupts.
3. DMA: brcmfmac's rings and buffers come from `dma_alloc_coherent`, which `lx_os_radio_memory()` already gives
   (contiguous, mapped uncached). **Open question:** Android puts the PCIe SysMMU (0x11420000) in front of the
   controller (`use-sysmmu`) and turns on I/O coherency (SYSREG_FSYS1 +0x700 bits [9:8]). With the SysMMU never enabled,
   does the controller's master see physical addresses? That is the first thing stage 2 checks, with one shared ring
   written by the chip.
4. Above: brcmfmac is FullMAC and registers with **cfg80211**, not mac80211. `lx_80211.c` holds the cfg80211 side the
   POCO did not need: `wiphy_register`, the scan through `cfg80211_ops.scan` and `cfg80211_inform_bss`/`scan_done`,
   joining through `.connect`. The four-way handshake is either the firmware's (brcmfmac's firmware supplicant,
   `BRCMF_FEAT_FWSUP`, if Samsung's firmware has "sup") or `lx_wpa.c` on the EAPOL frames, as now. brcmfmac's
   interface is Ethernet already, which is what `hakios.net.c` carries.
5. The chip: Linux's brcmfmac knows no BCM4361 (chip 0x4361, PCI device 0x441f; it is of the 4347 family). It needs a
   line in `pcie.c`'s ID table and a firmware name for each chip revision (B0, B2: the revision comes from the chip's
   chipcommon, which brcmfmac reads through BAR0). That is a patch in `wifi/lx/patches`, as for ath11k. Samsung's
   firmware is built for bcmdhd, which speaks the same PCIe "msgbuf" protocol and shared-memory layout as brcmfmac;
   whether it starts under brcmfmac without bcmdhd's own iovars is not known until it is tried.

### The files from the phone

Pulled from the user's own phone, never committed (as `fw-wifi/` on the POCO: `userland/build.sh` puts them into the
small image and the driver finds them with `hakios_image_file("fw", name)`). LineageOS has them in `/vendor/firmware/`;
Samsung's Android in `/vendor/etc/wifi/`. Look in both:

| File | What |
|---|---|
| `bcmdhd_sta.bin_b0`, `bcmdhd_sta.bin_b2` | the station firmware, one per chip revision (the S9's is expected to be B2: its Bluetooth patch is `bcm4361B2_*.hcd`) |
| `bcmdhd_clm.blob` | the regulatory data (CLM), downloaded after the firmware |
| `nvram.txt_r02a_b2`, `nvram.txt_r02b_b2`, `nvram.txt_murata_r041_b2` | the board's NVRAM; bcmdhd chooses one by the module (vendor and revision) |
| `/data/.cid.info` | which module this phone has ("murata", "semco" and a revision), written by bcmdhd from the chip's OTP at first boot |
| `/efs/wifi/.mac.info` | the phone's MAC address |

Not needed: `bcmdhd_mfg.bin_*` (factory test) and `bcmdhd_mon.bin_*` (monitor mode). To list them:
`adb shell su -c 'ls -l /vendor/firmware /vendor/etc/wifi; cat /data/.cid.info /efs/wifi/.mac.info'`.

Sources: the S9's kernel at e5906667068e (`drivers/pci/host/pci-exynos*.c`,
`drivers/net/wireless/broadcom/bcmdhd_101_12/dhd_custom_exynos.c`, `dhd_custom_cis.c`, `include/bcmdevs_legacy.h`), the
exynos9810-common device and vendor trees (`proprietary-files.txt`, `exynos9810-common-vendor.mk`), Silicium's
`starlte.dts`.
