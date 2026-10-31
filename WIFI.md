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

## Stage 2: the radio (written, not yet run)

Linux's **brcmfmac**, Broadcom's ISC-licensed FullMAC driver, on the scheme the POCO's ath11k uses: compiled unmodified
but for one patch, on FreeBSD's LinuxKPI headers and our `wifi/lx`, and tied into one object the kernel links, which
shows only `lx_prepare()`, `lx_start()`, `lx_stop()` and `lx_transmit()`. What is written, in the common repository:

| Where | What |
|---|---|
| `tools/mk-brcmfmac.sh` | the twin of `mk-ath11k.sh`: brcmfmac, brcmutil and their headers from the same pinned Linux (7.0.14), every file's ISC licence checked, `wifi/lx/brcmfmac/patches/bcm4361.patch` applied; 24 of brcmfmac's files built (`pcie.c`, `chip.c`, `firmware.c`, `core.c`, `msgbuf.c`, `commonring.c`, `flowring.c`, `fwil.c`, `fweh.c`, `feature.c`, `cfg80211.c`, `p2p.c` and the rest; no SDIO, USB or BCDC); `out/brcmfmac.o`. Only `debug.c`'s three debugfs functions are stubs |
| `wifi/lx/brcmfmac/patches/bcm4361.patch` | the BCM4361 in brcmfmac: PCI device 0x441f in its table; chip IDs 0x4361 and 0x4347 (the chip says one or the other: bcmdhd's `dhd_validate_chipid()`); RAM base 0x170000 for both (`CR4_4347_RAM_BASE`); firmware `brcmfmac4361b0-pcie` for revisions 3 and 4 (B0, B1), `brcmfmac4361b2-pcie` from 5 (B2); and the two lines where `brcmfmac=N` stops it (by returning, leaving things as they are: brcmfmac's way of failing would reset the chip) |
| `wifi/lx/brcmfmac/lx_pci.c` | the `struct pci_dev`: configuration space a word at a time through the kernel, the BARs where stage 1 put them, the PCI driver registered and the device probed as Linux's PCI core would, and the interrupt: INTx from `brcmfmac=5` (below), before that (or with `brcmfmac_poll=1`) brcmfmac's handler called by a thread every `brcmfmac_poll_ms` (2) ms; MSI is off on this root complex |
| `wifi/lx/brcmfmac/lx_cfg.c` | cfg80211 for a FullMAC driver: the wiphy, the network device's registration, the callbacks (`cfg80211_scan_done`, `inform_bss_data`, `connect_done`, `disconnected`), which LinuxKPI leaves empty and `lx_prelude.h` sends here; above them the kernel's station boundary (`sys/hakios.sta.h`, what iOS's Wi-Fi settings ask through `WIFI_STA`), on brcmfmac's `cfg80211_ops` (scan, connect, disconnect, add_key); the four-way handshake by `wifi/lx/src/lx_wpa.c`; frames through the network device's `ndo_start_xmit` and `netif_rx`; and `brcmf_dmi_probe()`, brcmfmac's hook for a board's settings: the phone's address, roaming off |
| `wifi/lx/brcmfmac/lx_rsn.h` | an access point's RSN element read, and ours for the association request (host-tested) |
| `wifi/lx/brcmfmac/lx_kpi.c`, `lx_brcmf.c` | what else brcmfmac asks of LinuxKPI (firmware in the background, a net_device as memory, cfg80211's channel arithmetic), and the steps |
| `drivers/wifi/hakios.brcmfmac.c` (`CONFIG_HAKIOS_BRCMFMAC`) | the kernel's side: the log, the options, the files from `fw/`, memory shown to the chip at its physical address; `lx_os_pci_*()` on `sys/hakios.exynos_pcie.h`; INTx (`lx_os_irq_line_*()`: SPI 253 on the GIC, a thread, the root complex's latch cleared); the phone's address (`wifi_mac`, else `fw/mac.info`, parsed by `sys/hakios.macaddr.h`); the network of `fw/network`; the way back to the loader (`hakios_wifi_stop()`, `hakios_wifi_quiesce()`) |
| `drivers/wifi/hakios.exynos_pcie.c` | `wifi_pcie=6`: memory decoding on, the device handed to the driver; ELBI's INTx enables and latch (`hakios_exynos_pcie_intx()`, `_intx_ack()`); INTx off in `hakios_exynos_pcie_quiesce()`, the chip held in reset and unpowered on the way back |
| `drivers/wifi/hakios.lx.c` (`CONFIG_HAKIOS_LX`) | unchanged, now a driver of its own that both radios' drivers require |
| `tools/brcmfmac-test.py` | host checks: the configuration-space arithmetic; the `.mac.info` parser; the RSN elements (WPA2, mixed, transition taken; WPA3, enterprise, MFP required, TKIP only, WEP refused); for both chip IDs and every revision, the firmware name the patched table gives; the RAM base; the device table; the patch's hooks |

DMA comes from `lx_os_radio_memory()` (44 MB in one physical piece, uncached), shown to the chip at its physical address.

### The steps

`wifi_pcie=6 brcmfmac=N`, each line said before it is done; every line of this stage starts with `lx:`, `brcmfmac:` or
brcmfmac's own (`brcmfmac_debug=MASK`, `0x180004` by default: INFO, PCIE, FWCON).

| Step | What | Expected on the phone |
|---|---|---|
| `brcmfmac=1` | the pci_dev, brcmfmac's PCI driver and its probe: BAR0 and BAR1 mapped, bus mastering on, the chip's ID and cores through BAR0's window; the firmware is asked for and never given | `lx: pci: 1:00.0 is 14e4:441f, class 0280xx`; `lx: pci: brcmfmac's probe of 1:00.0`; brcmfmac's line for the chip (4361 or 4347, and its revision: 5 for B2) and its cores (ARM CR4, PCIe2 Gen2 rev, ...); `stops before step 2`; `the probe returns 0` |
| `brcmfmac=2` | ... the files asked for and found | `lx: the driver asks for the file "brcm/brcmfmac4361b2-pcie.bin": there` (and `.txt`, `.clm_blob`; `.txcap_blob` is not there and need not be); `stops before step 3` |
| `brcmfmac=3` | ... the firmware and NVRAM into the chip's RAM through BAR1, its processor started, its shared area read, the rings set up | brcmfmac's `Shared RAM addr: 0x...` and `PCIe protocol version` 5 to 7; the firmware's console (`FWCON`) printing its version; `stops before step 4` |
| `brcmfmac=4` | ... the chip's interrupt (a thread that looks), and `brcmf_attach()`: the first command over the rings, which is the first time the chip reads and writes memory (DMA), the events, cfg80211's wiphy | `Firmware: BCM4361/5 wl0: ... version ...`; `lx: cfg80211: band 0: 14 channels`, `band 1: ...`; `the wiphy is registered`; `lx: brcmfmac's interface to the firmware is up` |
| `brcmfmac=5` | ... the interrupt by INTx instead of the thread: SPI 253 (INTID 285) level-triggered on the GIC, ELBI's `PCIE_IRQ_EN_PULSE` (0x00C) to INTA..INTD, the TOE, LEVEL and SPECIAL sources off (Android's `exynos_pcie_enable_interrupts()`); when it fires the SPI is masked, the latch `PCIE_IRQ_PULSE` (0x000) read and written back, brcmfmac's handlers run, the SPI unmasked. `brcmfmac_poll=1` keeps the thread | `brcmfmac: 5: THE GIC'S DISTRIBUTOR IS WRITTEN ...`; `lx: pci: brcmf_pcie_intr's interrupt handler is called when INTx fires`; then the same as 4 (the first command's answer comes by the interrupt) |
| `brcmfmac=6` | ... the phone's address: `wifi_mac=` if given, else `fw/mac.info`, to brcmfmac at its probe; it sets it in the firmware (`cur_etheraddr`) at step 4. Without either, the firmware's own (NVRAM or OTP) | `brcmfmac: 6: the phone's address, from fw/mac.info: xx:xx:xx:..:..:..`; `lx: the network device wlan0 is registered (xx:xx:xx:..)` with the same first three bytes |
| `brcmfmac=7` | ... the station: roaming off; the interface up (brcmfmac's `ndo_open`: the firmware's "up"), en0 on it (iOS's `wlan`), and the station given to the kernel; iOS's Wi-Fi settings scan through it | `lx: the interface wlan0 is up`; `lx: the station is the kernel's to ask: scans; not joining (brcmfmac=8)`; `lx: a scan for the kernel: ... N access points heard in ... ms` |
| `brcmfmac=8` | ... joining: brcmfmac's `connect` (open system, our RSN element, WPA2-PSK with CCMP, the group's CCMP or TKIP), the handshake by `lx_wpa.c`, both keys given (`add_key`), frames both ways; and the network of `fw/network`, if there is one, asked for as soon as the station is there | `brcmfmac: 8: the station is there ...`; `lx: brcmfmac 8: joining the network ...`; `lx: associated, N ms after brcmfmac's connect`; `lx: the handshake: ... its first; answered`, `... its second, SIGNED WITH THE KEY WE HAVE TOO ...`; `both keys given to the firmware: 0`; `lx: THE NETWORK IS JOINED`; `brcmfmac: 8: THE NETWORK OF FW/NETWORK IS JOINED` |

### Who does the handshake

brcmfmac can leave the four-way handshake to the firmware (`BRCMF_FEAT_FWSUP`, the `sup_wpa` iovar) when cfg80211's
connect parameters carry the key (`crypto.psk`). Samsung's bcmdhd for the BCM4361 is built without
`BCMSUP_4WAY_HANDSHAKE` (`bcmdhd_101_12/Makefile`: no chip's flags set it), so `dhd_linux.c` never sets `sup_wpa` and
`wl_cfg80211.c` never offers `NL80211_FEATURE_FW_4WAY_HANDSHAKE`: on the S9, Android's wpa_supplicant does it on the
host, and whether Samsung's firmware has a supplicant at all (`idsup` among its capabilities) is not known. So the
handshake is the kernel's own `lx_wpa.c`, the code that joins networks on the POCO, and brcmfmac is given no key:
it sets `WPA2_AUTH_PSK` with the host's supplicant, as for wpa_supplicant. Message 4 leaves before the pairwise key is
set (brcmfmac waits for it: `brcmf_netdev_wait_pend8021x()`).

### The way back to the loader

Where a run ends in order (`loader_return_after`, the host's `xl stop`, too hot, the battery low: `hakios_wifi_stop()`,
on a thread): if brcmfmac got as far as its interface, `lx_stop()` takes it down (the station taken back, the network
left, the interface down, brcmfmac's removal: the interrupt let go, the chip reset through its watchdog: `lx: brcmfmac
is down again`); then `hakios_exynos_pcie_quiesce()`, the same that `loader_return()` calls on every way back: the root
complex's INTx enables cleared, PERST# low, WLAN_REG_ON low, `exynos_pcie: at the run's end: PERST# low, WLAN_REG_ON low
(reads 0)`. The endpoint's configuration space is not touched (its link may be down by then); PERST# is its reset, which
stops its DMA. After a panic (one processor left, no locks) `hakios_wifi_quiesce()` only masks SPI 253, and
`loader_return()`'s `hakios_exynos_pcie_quiesce()` does the rest.

### The first runs

One image a run, read from pstore afterwards (README.md, "On the phone"). Stage 1 first, as above, up to
`wifi_pcie=5`; then:

```sh
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6                 # hand-over only: "not started (brcmfmac=N)"
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=1      # the chip's ID through BAR0
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=2      # needs fw-wifi/ (below)
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=3      # the firmware up
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=4      # its interface: the first DMA
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=5      # INTx in place of the thread
devices/starlte/mkimage.sh -s 60 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=6      # the phone's address (fw-wifi/mac.info)
devices/starlte/mkimage.sh -s 120 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=7     # the station: scan from iOS's Settings
devices/starlte/mkimage.sh -s 120 cpus=2 bootcpu=2 wifi_pcie=6 brcmfmac=8     # joining (fw-wifi/network, or from Settings)
```

If 5 fails (`Timeout on response` where 4 had none, or no interrupt counted when the driver lets INTx go), add
`brcmfmac_poll=1` to 6 to 8 and go on: the rest does not depend on it.

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
- 5: the first command timing out only with INTx: the chip's INTA does not reach the GIC. The driver's line when it
  lets INTx go counts what arrived and how often the latch held more than INTA; next to look at are ELBI's
  `PCIE_IRQ_PULSE` bits and whether the endpoint's command bit 10 (INTx disable) is set.
- 7: `the interface does not come up`: brcmfmac's `brcmf_cfg80211_up()` (the firmware's "up", power save, the
  regulatory domain); its own lines say which command failed. No access point heard: the CLM blob (`.clm_blob`) and the
  country.
- 8: `associated` and then `the handshake did not finish`: no EAPOL frame came up (`0 messages`) means the firmware
  passes them elsewhere; `NOT GOOD: the MIC ...` means a wrong passphrase. `the association is refused` with a status
  code: our RSN element against the access point's (`lx_rsn.h`).

### What remains

- Roaming (off), power saving, WPA3 and enterprise networks, protected management frames, more than one network.
- The PCIe SysMMU, if step 4 shows the chip cannot reach memory without it.

### The files from the phone

Pulled from the user's own phone, never committed. LineageOS has them in `/vendor/firmware/`; Samsung's Android in
`/vendor/etc/wifi/`. Look in both:

| The phone's file | What | In `fw-wifi/` as |
|---|---|---|
| `bcmdhd_sta.bin_b2` (`_b0`) | the station firmware of the chip's revision (the S9's is expected to be B2: its Bluetooth patch is `bcm4361B2_*.hcd`) | `brcmfmac4361b2-pcie.bin` (`brcmfmac4361b0-pcie.bin`) |
| `nvram.txt_r02a_b2`, `nvram.txt_r02b_b2`, `nvram.txt_murata_r041_b2` ... | the board's NVRAM; bcmdhd chooses one by the module `/data/.cid.info` names | the one `.cid.info` names, as `brcmfmac4361b2-pcie.txt` |
| `bcmdhd_clm.blob` | the regulatory data (CLM), downloaded after the firmware | `brcmfmac4361b2-pcie.clm_blob` |
| `/data/.cid.info` | which module this phone has ("murata", "semco" and a revision), written by bcmdhd from the chip's OTP at first boot | (to choose the NVRAM) |
| `/efs/wifi/.mac.info` | the phone's MAC address (`00:12:34:...` if Samsung's driver made one up) | `mac.info` (`brcmfmac=6`; left out with `SHARE=1`) |

Not needed: `bcmdhd_mfg.bin_*` (factory test) and `bcmdhd_mon.bin_*` (monitor mode). To list them:
`adb shell su -c 'ls -l /vendor/firmware /vendor/etc/wifi; cat /data/.cid.info /efs/wifi/.mac.info'`.
`userland/build.sh` puts every `fw-wifi/brcmfmac4361*-pcie.*` into the small image's `fw/`, where the kernel finds them,
with `fw-wifi/mac.info` and `fw-wifi/network` (the network to join at `brcmfmac=8`: its name on the first line, its
passphrase on the second; both left out with `SHARE=1`).

Sources: the S9's kernel at e5906667068e (`drivers/pci/host/pci-exynos*.c` and `pci-exynos.h`: ELBI's interrupt
registers, `exynos_pcie_enable_interrupts()`, `exynos_pcie_irq_handler()`;
`drivers/net/wireless/broadcom/bcmdhd_101_12/dhd_custom_exynos.c`, `dhd_custom_cis.c` (`.mac.info`),
`include/bcmdevs_legacy.h`, `dhd_linux.c` and `wl_cfg80211.c` (`sup_wpa`, `idsup`), `Makefile` (the BCM4361's flags),
`dhd_pcie.c`, `include/sbchipc.h`), the
exynos9810-common device and vendor trees (`proprietary-files.txt`, `exynos9810-common-vendor.mk`), Silicium's
`starlte.dts`.
