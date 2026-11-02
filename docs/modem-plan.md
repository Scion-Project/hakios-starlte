# The S9's modem under HakiOS: research and plan

Status: **research only, nothing written or run.** November 2026. No phone was used to write this.

The Galaxy S9 (SM-G960F) has a Samsung Shannon CP inside the Exynos 9810 itself (Samsung's driver calls it
`ss360ap`; FirmWire's model of the same chip family is `S360AP`). It shares DRAM with the AP and talks to it
through a mailbox and rings in that shared memory. That is very different from the POCO's Qualcomm MPSS.

**The goal (owner's decision, 2026-11-02):** stock iOS 16.5 user space. CommCenter, Phone, Messages and cellular
data must work with **no iOS user-space changes**. Everything goes in the kernel, so moving to a new iOS
version stays easy. This plan is built around that goal. It also says where the goal is uncertain and what
we can ship before the goal is reached.

Sources, read for facts only. No code from them goes into our repositories:

| Short name | What | Revision read |
|---|---|---|
| GPL | `Scion-Project/android_kernel_samsung_exynos9810` (GPL-2.0) | `lineage-24.0` @ `e590666` |
| DTS | GPL `arch/arm64/boot/dts/exynos/exynos9810-starlte_eur_open_26.dts` | same |
| KERN | `Scion-Project/hackios-xnu-kernel` | `6be3ace` |
| lsi | Replicant `libsamsung-ipc` (GPL-2.0-or-later, see `samsung-ipc/ipc.c` header, `COPYING`) | `81a412c` (2023-09-20) |
| FW | FirmWire (BSD-3-Clause), the Shannon emulator | `main` |
| BT | seemoo-lab BaseTrace (GPL-3.0): iPhone QMI tooling, `libqmi-ios-ext` | `main` |

## Hard safety rules (they apply to every milestone)

1. **Nothing writes EFS, SEC_EFS, CPEFS, nv_data or anything that holds the IMEI.** This is already enforced
   for storage: `drivers/storage/hakios.ufs.c:1770` (KERN) lists EFS, SEC_EFS, CPEFS, RADIO and the boot
   chain as partitions that are never written, and the UFS driver is read-only by default. The modem work adds
   no write path. The CP's NV image is uploaded into CP RAM from a **read-only** copy. Every NV or file
   write the CP asks for over RFS is accepted into a kernel RAM overlay and is **discarded** at power-off (see
   section 2). There is no `rfs_persist` option, and none will be added.
2. **The modem firmware is not redistributed.** `modem.bin` is read at run time from the phone's own RADIO
   partition through `/dev/ufs_RADIO`, which is read-only. It is never put into an image, a release or git.
   The same goes for `nv_data.bin`: it is per-device and holds the IMEI. It never enters git, CI artifacts or
   logs. Logs print only its size and a hash.
3. No IMEI, IMSI, ICCID or phone number appears unredacted in a log. The kernel masks them to their last 4
   digits.

---

## 1. How the CP boots on the 9810

### 1.1 The pieces in Samsung's kernel

| Piece | File (GPL) | Role |
|---|---|---|
| modem_if core | `drivers/misc/modem_v1/modem_main.c`, `modem_io_device.c` | Builds the `iodevs` (char devices and `rmnetN` netdevs) from the DT. The ioctl switch is at `modem_io_device.c:672-765` (`IOCTL_MODEM_ON/RESET/BOOT_ON/BOOT_OFF/STATUS/XMIT_BOOT/DL_START/FW_UPDATE`) |
| Modem control | `drivers/misc/modem_v1/modem_ctrl_ss310ap.c` | CP power and reset, the mailbox status bits, IRQs |
| Link device | `drivers/misc/modem_v1/link_device_shmem.c` (3936 lines) plus `link_device_memory_sbd.c` | Boot image copy, secure-boot SMC, command handshake, SIPC5 over SBD rings |
| Shared memory | `drivers/misc/mcu_ipc/shm_ipc.c` | The reserved region, the CP memory map read from the TOC |
| Mailbox | `drivers/misc/mcu_ipc/mcu_ipc.c`, `regs-mcu_ipc.h` | AP<->CP interrupts and 32-bit shared registers |
| PMU CAL | `drivers/soc/samsung/cal-if/pmucal_cp.c`, `exynos9810/pmucal_cp_exynos9810.h` | CP power, reset and status sequences |

### 1.2 Device tree facts (DTS)

- **Reserved memory** (`DTS:29-32`): `modem_if { compatible = "exynos,modem_if"; reg = <0 0xF0000000 0x9200000>; }`
  covers 146 MB at **0xF0000000**. `cp_ram_logging` is at 0xF91F_0000 (32 MB, `DTS:34-37`). `shm_ipc.c:461-471`
  takes the region with `RESERVEDMEM_OF_DECLARE(modem_if, ...)`.
- **shmem node** (`DTS:12616-12625`): `cp_size` 0x7900000 (121 MB, CP code and data), `vss_size` 7 MB (the
  voice DSP), `ipc_offset` 0x8000000 with `ipc_size` 5 MB, and `zmb_offset` 0x8500000 with `zmb_size` 11 MB.
  At probe, `shm_ipc.c:570-640` reads a memory map from the image already in the region, at offset
  **0x200 (TOC) + 0xA0**. That map is a "MEMn" table with `IPC`, `VSS`, `VPA`, `ZMC` and `LOG` entries, and
  when it is valid it overrides the DT values.
- **Mailbox** (`DTS:13167-13176`): `mcu_ipc@14170000`, compatible `samsung,exynos-shd-ipc-mailbox`, 0x180
  bytes, SPI 69. The register map is `regs-mcu_ipc.h:18-32`: INTGR0/INTCR0/INTMR0/INTSR0 at 0x08-0x18,
  INTGR1.. at 0x1C-0x2C, and the shared registers ISSR0.. from 0x80.
- **Modem pdata** (`DTS:12250-12330`): `mif,name = "ss360ap"`, `ipc_version = 50` (SIPC 5),
  `link_name = "shmem"`, `link_attrs = 1993` = 0x7C9. Decoded with `modem_v1.h:247-262`, those bits are
  SBD_IPC, DPRAM_MAGIC, MEM_BOOT, MEM_DUMP, BOOT_ALIGNED, DUMP_ALIGNED and XMIT_BTDLR.
  - Mailbox registers: ap2cp_msg 0, cp2ap_msg 1, ap2cp_united_status 2, cp2ap_united_status 3.
  - Interrupt numbers: int_ap2cp_msg 0, wakeup 1, status 2, active 3; irq_cp2ap_msg 0, status 2, active 3,
    wakelock 8, ratmode 9.
  - Status bit fields: `sbi_cp_status` mask 0xF at bit 1, `sbi_lte_active` at bit 5, `sbi_cp_wakelock` at
    bit 6, and so on.
  - Interrupts: SPI 74 (CP watchdog) and SPI 440 (CP fail).
- **21 iodevs**, listed after the pdata in DTS. The table below shows the name, SIPC channel and format.

| iodev | ch | format | Use |
|---|---|---|---|
| `umts_ipc0`, `umts_ipc1` | 235, 236 | FMT | Samsung IPC control messages (the RIL's channel) |
| `umts_rfs0` | 245 | RFS | Remote file system: **the CP's NV and file access on the AP** |
| `rmnet0..7` | 10..17 | RAW, io_type NET | Data sessions, raw IP |
| `multipdp`, `multipdp_hiprio` | 0 | MULTI_RAW | The demux for the PDP channels |
| `umts_boot0` | 215 | BOOT | The bootloader channel (cbd) |
| `umts_ramdump0` | 225 | DUMP | Crash dumps |
| `umts_csd` | 1 | RAW | Circuit-switched data / video call |
| `umts_router` | 25 | RAW | "Data Router" (AT routing to USB in factory and DUN modes; unverified) |
| `umts_dm0` | 28 | RAW | Diagnostics |
| `umts_cass`, `smd4`, `umts_ciq0` | 35, 33, 26 | RAW | Misc and Carrier-IQ |

Channel numbers come from `modem_v1.h:128-210`: PDP_0 = 10, BOOT_0 = 215, DUMP_0 = 225, FMT_0 = 235,
RFS_0 = 245. None of the iodevs is a plain AT channel. Control goes over Samsung IPC on ch 235.

### 1.3 The modem.bin layout (TOC)

RADIO holds `modem.bin`. Its first 512 bytes are a TOC of 32-byte entries:
`char name[12]; u32 offset; u32 loadaddr; u32 size; u32 crc; u32 entryid;`. The same layout is in
lsi `partitions/toc/toc.h:25-35` and FW `vendor/shannon/TOCFile.py:83-87`. The entries are `TOC`, `BOOT`,
`MAIN`, `VSS` and `NV`, and often `OFFSET` too. The NV entry gives the place and size for `nv_data.bin` in
CP memory. The data itself does not come from RADIO: cbd reads it from `/efs/nv_data.bin`. A chunk is copied to
`region + (entry.loadaddr - BOOT.loadaddr)`, as in lsi `herolte.c` `upload_chunk()`, with
`m_offset = loadaddr - boot.loadaddr`. In the kernel, `shmem_xmit_boot()` (`link_device_shmem.c:2170-2224`)
copies the user buffer to `boot_base + m_offset` after checking the bounds.

### 1.4 The boot sequence, and who does what

The sequence below comes from the GPL driver and from lsi's `herolte_boot()` (Galaxy S7, Exynos 8890, the
same `modem_v1` driver family). lsi took its order from cbd traces: see `herolte.c:193-400` and Tony
Garnock-Jones, "How to boot the Samsung Galaxy S7 modem with plain Linux kernel interfaces only" (2020).

| # | Step | Side | Where |
|---|---|---|---|
| 0 | EL3 sets up the CP's AP_BAAW (its window onto DRAM) and CP_INIT at cold boot | **EL3 monitor (Samsung's)** | comment `modem_ctrl_ss310ap.c:296-299` |
| 1 | Open `umts_boot0`; `IOCTL_MODEM_RESET` | cbd -> kernel | `modem_ctrl_ss310ap.c:399-445` |
| 2 | `IOCTL_SECURITY_REQ` mode 2 (re-init) | cbd -> kernel -> **SMC 0x82000700** | `link_device_shmem.c:2261-2307`, `shm_ipc.c:280-325`, `pmu-cp.h:114` |
| 3 | Read the TOC from RADIO; `IOCTL_MODEM_XMIT_BOOT` for BOOT, MAIN and NV in 62 KB chunks | cbd -> kernel memcpy | `link_device_shmem.c:2170-2224` |
| 4 | `IOCTL_SECURITY_REQ` mode 0 (size_boot, size_main). The kernel runs `cal_cp_init()` once (on the 9810), then SMC 0x82000700 with `mode |= phys_base`. **EL3 verifies the signature** and locks the CP image | kernel + EL3 | `link_device_shmem.c:2290-2303`; SSS clock via SMC 0x82001011 (`modem_v1.h:31`) |
| 5 | `IOCTL_MODEM_ON`: clear the mailbox, set `pda_active`, then on the 9810 write **AP2CP_CFG (0x14820000) bit 0** ("CP_CPU will work") | kernel | `modem_ctrl_ss310ap.c:265-341` |
| 6 | `IOCTL_MODEM_BOOT_ON`: wait for `cp_status` != 0 in mailbox register 3 (up to about 1-2 s) | kernel | `modem_ctrl_ss310ap.c:447-478` |
| 7 | `IOCTL_MODEM_DL_START`, then the boot-channel handshake 0x900d -> 0xa00d, 0x9f00 -> 0xaf00 | cbd <-> CP bootloader | lsi `herolte.c:300-360` (the 8890 numbers; confirm them on the 9810) |
| 8 | CP -> `CMD_INIT_START` (0x1). The AP builds the SBD link descriptor in shmem and answers `CMD_PIF_INIT_DONE` (0xD) | kernel | `link_device_shmem.c:439-482`, `link_device_memory.h:137-149` |
| 9 | CP -> `CMD_PHONE_START` (0x8). The AP answers `CMD_INIT_END` (0x2) **only when the FMT and RFS iodevs are both open** (`rild_ready`) | kernel, gated on user space | `link_device_shmem.c:410-430, 559-645` |
| 10 | `IOCTL_MODEM_BOOT_OFF` waits for that completion (`init_cmpl`). The state is now ONLINE | kernel | `modem_ctrl_ss310ap.c:480-508` |
| 11 | rild opens `umts_ipc0`. RFS requests start right away | RIL / RFS server | |

PMU detail: `cal_cp_init()` runs the `cp_init[]` sequence (`pmucal_cp_exynos9810.h:2-8`). It sets CP_CTRL_NS
bit 1 and CP_CTRL_S bit 3, then waits for RESET_SEQUENCER_STATUS (PMU 0x14060504) == 5. CP_CTRL_S and
CP_CTRL_NS are **secure registers**, written through SMC 0x82000700 READ_CTRL/WRITE_CTRL
(`pmucal_cp.c:217-290`). Reset assert and release are plain PMU writes at 0x14061320-0x14061338
(`pmucal_cp_exynos9810.h:12-23`). Magic words are in `link_device_memory.h:535-538`: IPC 0xAA, BOOT
0x424F4F54, DUMP 0x44554D50, CRASH 0xDEADDEAD.

**What cbd does that the kernel does not:** it reads the TOC and the partitions, reads `nv_data.bin` (and
**writes and repairs** it, with its `.md5` and backup, which is the EFS danger), runs the order of ioctls,
does the bootloader handshake, restarts the CP after a crash and collects dumps. Everything else is
kernel-side. On HakiOS **all of cbd moves into the kernel driver**, because the goal forbids user-space changes,
and the kernel does none of cbd's NV writing.

### 1.5 Two facts specific to HakiOS that block M0

1. **Memory conflict.** The S9's UEFI reserves **0xF0000000 + 64 MB for the XNU payload**
   (`uefi/files/.../MemoryMapLib.c:18-20`, README "This port's change to the platform"). That is the start of
   `modem_if`. EL3 programs the CP's BAAW for this physical window at cold boot, so the CP region cannot
   move. **The payload must move first** (for example to a free block below 0xF0000000) and the whole
   0xF0000000-0xF91FFFFF range must be kept out of XNU's memory, uncached.
2. **SMCs pass through Carbon.** Carbon Hypervisor owns EL2. Samsung SiP SMCs already reach EL3 through it:
   `drivers/gpu/hakios.mali.c:121,238` and `drivers/audio/hakios.exynos_abox.c:16` use SMC 0x82000410. Nobody
   has tried 0x82000700 (CP secure boot, CP_CTRL) or 0x82001011 (SSS clock) yet. If Carbon filters them, it
   needs a pass-through rule.

### 1.6 How hard is a minimal XNU driver up to the handshake?

Small and well defined, much smaller than the POCO's MPSS (which needed TZ PIL, SMP2P, GLINK and QRTR):

- An ioremap of 0xF0000000 (146 MB), uncached.
- A mailbox driver: one MMIO block plus GIC SPI 69, for about 16 interrupts and 16 shared registers. About
  200 lines.
- The PMU and SMC sequences above, plus AP2CP_CFG. About 150 lines.
- A TOC reader on `/dev/ufs_RADIO` (read-only), the chunk copy and two SMCs. About 250 lines.
- The boot handshake and the `INIT_START -> PIF_INIT_DONE -> PHONE_START -> INIT_END` command handshake,
  including writing the SBD link descriptor (`link_device_memory_sbd.c`, `init_sbd_link`). The SBD layout is the
  largest piece. About 600-900 lines.

**Estimate:** about 1.5-2.5k lines and 2-4 weeks with the phone on USB. The main risk is that EL3 refuses the
SMC or the signature check from our EL1 under Carbon. The ioctl sequence itself is well known.

---

## 2. Channels: SIPC5, SBD rings, RFS

- **Framing** (`include/sipc5.h:32-61`): byte 0 is the config byte. Its top 5 bits are 0b11111 (the start mark)
  and its low 3 bits are flags: PADDING, EXT_LEN, CTL. Byte 1 is the channel ID and bytes 2-3 are the length
  (LE). An optional control byte or a 2-byte extended length follows, giving 4, 5 or 6 bytes of header. With
  `LINK_ATTR_IPC_ALIGNED` frames are padded to 4 bytes.
- **Transport:** on the 9810 every channel runs over **SBD ring buffers**, because SBD_IPC is set. The AP writes
  a link descriptor in the IPC region. It holds one `sbd_rb_channel` per channel and one `sbd_rb_desc` pair
  (UL/DL) per channel (`include/sbd.h:150-170`). Each ring has a length, rp and wp pointers, and arrays of
  offsets and sizes into the buffer pool (`mif,buff_offset` 5 MB, `buff_size` 9 MB). Doorbells use the mailbox
  `int_ap2cp_msg` / `irq_cp2ap_msg` with the mask bits from `link_device_memory.h:120-150`. The legacy
  `shmem_4mb_phys_map` (`link_device_memory.h:80-118`) still supplies the magic and access words.
- **Samsung IPC on FMT (ch 235):** a header is `u16 length; u8 mseq; u8 aseq; u8 group; u8 index; u8 type`,
  followed by the data. The message groups (PWR, CALL, SMS, SEC, NET, MISC, SVC, SS, GPRS, SAT, CFG, IMEI, GEN,
  RFS) are documented as code in lsi `include/*.h`, and `ipc_strings.c` names them. Those values are mostly from
  the Galaxy S2/S3 (XMM6260/6262) era. The 9810's Shannon firmware speaks a newer dialect, so expect new
  commands and changed TLVs. A fork (`manoedinata/libsamsung-ipc`) claims LTE additions for newer Shannon chips.
  **Every message we use has to be confirmed against a capture from the phone (M1).**
- **RFS (ch 245), the EFS danger.** The CP has no flash of its own. It keeps NV items and some files on the
  AP's `/efs` and reaches them through RFS requests: NV_READ_ITEM 0x4201 and NV_WRITE_ITEM 0x4202 in lsi
  `include/rfs.h:29-30`, and on newer firmware file-level open/read/write/close on `/efs` paths. On Android the
  daemon serving it writes `/efs/nv_data.bin` and its md5 and backup.
  - **How we serve it:** the kernel holds `nv_data.bin` (and any other file the CP asks for) as a **RAM
    image**. It is loaded read-only at boot from one of two sources, A or B below. Reads come from the RAM
    image. Writes **update the RAM image only** and are answered "OK", so the CP sees a consistent store for
    the session. Every write is logged by item or offset and length (never the contents of IMEI items). Nothing
    is ever flushed. Opening a file for create or write on any path outside the RAM set is answered with an
    error. This is the same design as the POCO's RMTFS (KERN `docs/cellular.md` "What works": "writes stay in
    kernel memory for the session").
  - **Where the read-only copy comes from:**
    - (A) For M0-M1: the user's own backup of `/efs/nv_data.bin`, packed by `mkimage.sh` into the boot image's
      RAM disk. It is a local file that is never committed and never cached by CI, the `.gitignore`d
      `local/nv_data.bin`.
    - (B) Later: a small **read-only** ext4 reader in the kernel over `/dev/ufs_EFS`. The UFS driver already
      refuses writes to EFS.
  - Gating: `INIT_END` is sent only when FMT and RFS are "open" (`rild_ready`, `link_device_shmem.c:410`). Our
    driver opens both itself once its RFS server and its IPC client are ready.

---

## 3. What stock CommCenter expects from the kernel

### 3.1 The identity

The loader presents **iPhone10,3** (iPhone X, Qualcomm MDM9655 variant). KERN uses the
`20F66__iPhone10,3_6` cache (`docs/air.md:1567`). On this hardware class:

- CommCenter talks **QMI** (QMux framing) to the baseband. Intel iPhones use ARI. Public sources: seemoo-lab,
  "Catch You Cause I Can" (RAID 2024): "iPhones with Qualcomm basebands use QMI". Kröll et al., "ARIstoteles"
  (ESORICS 2021): "Depending on the underlying chip, Qualcomm or Intel, CommCenter loads shared libraries for
  parsing QMI or ARI".
- The transport is **PCIe**. BaseTrace hooks `libPCITransport.dylib` `pci::transport::th::writeAsync` to see
  outgoing QMI (`qmi-inject/agent/send.ts:57-64`). It hooks `libATCommandStudioDynamic.dylib`
  `QMux::State::handleReadData` for incoming QMI (`qmi-inject/agent/receive.ts:6-12`). The Qualcomm-side router
  is `libmav_ipc_router_dynamic.dylib` (`mav_router::device::pci_shim`). "MAV" is Apple's name for the Qualcomm
  path.
- Apple adds **private QMI services** next to the standard ones. BaseTrace's `libqmi-ios-ext/` defines
  `qmi-service-{bsp,vinyl,mavims,elqm,awd,sft,p2p,ms,mfse,coex,apps,audio,vs,...}.json` beside apple
  variants of DMS, NAS, UIM, WDS, WMS and WDA. CommCenter will use at least BSP (baseband state and power)
  and probably others before it will even show "No SIM".

### 3.2 What our own runs already showed

KERN `userland/mkjobs.py:69-86` (20 recorded crashes of stock CommCenter on HakiOS): it dies right after
**"Unable to communicate with AppleBaseband driver" (com.apple.driver.AppleBasebandPCI)** (SIGABRT), or right
after **"Could not find AppleIPAppender service"** (matched by name; user client **ApplePDPHelperInterface**:
PDP contexts, traffic-class flows, dedicated bearers) (SIGSEGV). With no `baseband` node in the DT, launchd
picks `com.apple.CommCenter-noncellular`.

So a stock-compatible kernel must at least provide:

1. A `baseband` node in the device tree we give XNU, so the cellular CommCenter plist is chosen.
2. An IOService that CommCenter (via `libPCITransport` / the ABM baseband manager) accepts as
   **AppleBasebandPCI**, with the user client's selectors for power state, reset, boot stages,
   firmware-update (BBU) status and the QMI pipes. **These selectors are not documented anywhere public.**
3. **AppleIPAppender** with an **ApplePDPHelperInterface** user client that creates and binds PDP contexts to
   the `pdp_ipN` interfaces.
4. `pdp_ip0..N` ifnets, the names iOS's network stack and configd treat as cellular
   (`IFT_CELLULAR` / `IFNET_SUBFAMILY_CELLULAR` exist in open-source XNU `bsd/net/if_types.h`, `bsd/net/if_var.h`).
5. A **QMI server** answering the standard and Apple-private services, with CommCenter's boot-time
   expectations: firmware version, IMEI from DMS, card status from UIM, and BSP state transitions.
6. Probably also the baseband **boot and update** flow that `abm-helper`/`bbupdaterd` and CommCenter's ABM
   expect (on the real hardware: SAHARA/firehose firmware load over PCIe, fusing and nonce checks). The kernel
   would have to present "baseband already booted, firmware current".

### 3.3 Does the POCO port already provide an Apple-compatible interface?

**No.** `drivers/modem/hakios.cell.c:1-18` says so directly: "Darwin's own cellular interface (pdp_ip0) is
made by its baseband stack, which is not here". The POCO exposes data as `en1`, an Ethernet-looking interface
on which the kernel answers ARP and DHCP so that configd routes through it, and puts the signal bars in the
status bar through a SpringBoard injection (`userland/src/inject_sb.c`), which is a user-space change. Its
QMI code (`hakios.qmi.c`, `hakios.nas.c`, and WDS/WDA/DPM in `hakios.mpss.c`) is a QMI **client** talking
**to** a Qualcomm modem over QRTR.

What carries over to the S9:

- The QMI TLV encoder and decoder and the service and message IDs from `hakios.qmi.c`, refactored into a
  shared `qmi_tlv` module that both a client (POCO) and a server (the emulation) use.
- `hakios.cell.c` (en1, ARP and DHCP in the kernel) as the **interim data path** on the S9, unchanged. It needs
  no iOS changes.
- The RMTFS read-only RAM overlay design, applied to RFS.
- The future Apple-facing layer (section 3.4) is shared too: once a kernel QMI server exists on the S9, the
  POCO can put **the same Apple-facing layer** over its real QMI modem and just pass messages through, which is
  easier there than translating them. Build the Apple-facing layer once, as `drivers/modem/hakios.bb.c`, with
  two back ends.

### 3.4 Architecture for the stock path

```
CommCenter / abm / Phone / Messages  (stock, unmodified)
      |  IOKit: AppleBasebandPCI user client (power, boot state, QMI pipes)
      |  IOKit: AppleIPAppender / ApplePDPHelperInterface (PDP contexts)
      v
hakios.bb.c        Apple-facing layer: the IOService names and classes, the selectors, the QMux pipes,
                   pdp_ipN ifnets (IFT_CELLULAR)
      |
hakios.qmisrv.c    QMI server: CTL client IDs, per-service state machines, indications
      |  translation tables (QMI message <-> Samsung IPC message)
hakios.sipc.c      Samsung IPC client on FMT ch 235: seq numbers, request/response matching, unsolicited
      |
hakios.shannon.c   CP boot (section 1), SBD rings, mailbox, RFS RAM server (section 2), rmnet <-> pdp_ip
      v
Shannon CP  (modem.bin from RADIO, read-only; NV from a read-only copy, writes kept in RAM only)
```

Data plane: `rmnetN` SBD rings (raw IP, ch 10-17) feed `pdp_ipN` directly, with no QMAP and no Ethernet
emulation. Until `hakios.bb.c` exists, the same rings feed `en1` through `hakios.cell.c`.

### 3.5 The minimal QMI subset for each milestone (estimates)

The counts are request/response pairs plus indications CommCenter is expected to need. Names follow libqmi
and BaseTrace.

| Stage | Services | Messages (about) | Translation needed |
|---|---|---|---|
| Boot and idle (CommCenter stays up, shows "No Service" or the carrier name) | CTL (allocate/release CID, version info, sync); DMS (caps, IMEI/MEID, revision, serial, operating mode get/set, power state); UIM (card status, read transparent EF ICCID/IMSI/AD/SPN, get slots); NAS (serving system, system info, signal info, register-indications, network time, PLMN name); **BSP (Apple)** and whatever else BaseTrace logs from a real iPhone X at boot | 50-70 + 15 indications | DMS/UIM/NAS map to Samsung MISC/SEC/NET/PWR messages; BSP is answered by the kernel itself |
| Data | WDS (start/stop network, get runtime settings, packet service status ind, get/modify profile); WDA (data format: answer raw IP); DSD (system status) | +20 | GPRS define PDP / activate / IP configuration in Samsung IPC; ApplePDPHelperInterface |
| SMS | WMS (raw send, event report ind, raw read, delete, set routes, get/set SMSC, list messages, indication register, memory status) | +15 | Samsung SMS group (send msg, incoming msg, deliver report, SVC center address); PDUs are 3GPP on both sides, so this is simple |
| Voice (CS) | VOICE (dial, answer, end, all call status ind, burst/continuous DTMF, get/set supplementary service, call waiting/forwarding, USSD) plus Apple "audio"/"vs" services | +30 | Samsung CALL/SS group; **plus the audio path**, section 4 |

Sizing: the boot-and-idle stage is about 5-8k lines (QMI server and translation). Data adds about 2k, SMS about
1.5k, voice about 3k plus audio. The `hakios.bb.c` Apple-facing layer cannot be sized before its selectors are
known.

---

## 4. Verdicts

**Data, the interim path (en1, no iOS change):** realistic. It is the POCO's proven approach: configd treats
en1 as Ethernet, and Safari and apps get data. There are no bars, and iOS sees no "cellular" interface (it does
not count cellular data use, and it ignores the "cellular data" switch).

**Data with stock CommCenter (pdp_ip0):** possible, but it is the expensive part. All the cost is in the
undocumented Apple layer (`AppleBasebandPCI` selectors, ABM boot states, BSP and other private QMI services,
`ApplePDPHelperInterface`). None of that is in public sources. It has to be found by observation:
- run stock CommCenter against logging stub services and record every `IOServiceOpen`, external-method
  selector, struct size and QMI message it sends;
- compare with BaseTrace's public dissectors and published captures from real iPhones.

This is iterative reverse engineering of an interface Apple can change in any iOS release. That weakens the
"easy to move to a new iOS" argument: the Apple-facing layer is version-coupled, even though the CP and SIPC
layers are not. The Apple binaries must not be redistributed or copied into our repos. Observing their behaviour
on our own device is the only method that fits the rules. Honest estimate: **2-4 months**, with a **real
chance of a hard stop** (for example, if CommCenter demands a signed or nonce-checked baseband state we cannot
fake).

**SMS through stock Messages:** follows from the line above. Once CommCenter accepts the baseband, WMS
translation is the easiest service (PDUs pass through unchanged). Medium-high risk, inherited entirely from the
CommCenter layer.

**Voice through the stock Phone app:** low probability. Signalling is translatable (VOICE <-> Samsung CALL).
The audio is the problem:
- On the 9810, call audio runs CP (VSS, the 7 MB voice DSP image in the TOC) <-> ABOX, with **calliope (ABOX's
  DSP firmware) running the call path**.
- Our ABOX driver deliberately keeps calliope off and runs in bypass (`AUDIO.md:5, 25-46`;
  `drivers/audio/hakios.exynos_abox.c:16`), and even that bypass path is not yet confirmed on the phone.
- On the iOS side, iPhone call audio goes through private baseband-audio plumbing in CommCenter and
  mediaserverd/AudioToolbox, with no public documentation.
- VoLTE would add IMS on top. Many networks now need it, since 2G and 3G are being switched off.

Treat voice as research after M3, not a commitment.

**An emulation layer in general:** the QMI-to-SIPC translation is ordinary engineering, because both protocols
are documented or observable. The uncertain part is purely Apple's kernel and user boundary. An alternative
("our own small daemon plus an app") would be much cheaper, but it is ruled out by the owner's decision, and
this plan does not use it.

---

## 5. Milestones

Effort assumes one engineer with the phone on USB (CDC-ACM console, `README.md` "log and console") and runs
of the kind used for Wi-Fi.

### M0: CP boot handshake

Steps:
1. Move the XNU payload out of 0xF0000000 (in the UEFI's `MemoryMapLib.c` and the loader's window choice).
2. Map `modem_if` uncached and keep it out of XNU's memory.
3. Add the mailbox driver.
4. Run the boot sequence (section 1.4), with SMCs through Carbon.
5. Copy BOOT and MAIN from `/dev/ufs_RADIO` and NV from the RAM copy.
6. Reach `CMD_PHONE_START`. Answer `INIT_END` with the RFS RAM server running (a stub first).

Done when the console shows "CP ONLINE" with `cp_status` != 0 and no CP crash for 10 minutes.

**Effort:** 3-5 weeks. **Risk:** medium. Unknowns: whether EL3 accepts SMC 0x82000700 from our EL1 through
Carbon; whether the S-Boot cold boot left the BAAW/CP_INIT intact; the 9810's exact boot0 handshake values.

**Needed from the phone:**
- A rooted Android (stock or Lineage) to capture the **read-only** facts:
  - `dmesg` from boot, with the `mif`/`shmem`/`cbd` lines and the "CP memory map" print (`shm_ipc.c:582-610`);
  - `logcat -b radio`;
  - `/sys/firmware/fdt`;
  - `ls -l /dev/block/by-name`.
- The user's own `/efs/nv_data.bin` (copied **off** the phone with `cat`, a read operation) and a full **EFS
  backup** (README step 2) before the first run.
- Nothing is written to the phone except the boot image.

### M1: IPC channel, SIM and IMSI query (read-only)

Steps:
1. Add the SBD rings and SIPC5 framing.
2. Add the Samsung IPC client on ch 235 and the full RFS RAM server, with the write log.
3. Query, read-only: PWR phone state, MISC ME version and serial, SEC SIM status, SEC RSIM access (READ BINARY
   of EF_IMSI and EF_ICCID), NET registration status and signal.
4. Expose the results as `sysctl kern.hakios.cell.*`, masked.

Done when the SIM status, the masked IMSI and RSSI show up and the RFS write log shows the CP's writes landing
in RAM only.

**Effort:** 3-4 weeks. **Risk:** medium, because the message dialect differs from lsi's. **Needed:** one
Android capture of `umts_ipc0`/`umts_rfs0` traffic (for example with the GPL kernel's `modem_pktlog`, or by
interposing on rild), and a SIM card.

### M1.5: the CommCenter probe (parallel to M2, decides the stock path)

Steps:
1. Add the `baseband` DT node.
2. Add stub `AppleBasebandPCI` and `AppleIPAppender` services whose user clients **log every call and refuse
   nothing they don't understand**. Grow them until CommCenter stops crashing.
3. Record the selector map and the first QMI frames CommCenter sends.

Done when there is a written interface note (selectors, struct sizes, the QMI bring-up sequence) and a go/no-go
on the stock path.

**Effort:** 3-6 weeks. **Risk:** high: this is where the stock goal can fail. **Needed:** only HakiOS on the
phone (no SIM needed).

### M2: data via rmnet

The interim step (no iOS change): Samsung IPC GPRS define and activate the PDP context on the SIM's APN, read
the IP configuration, and feed rmnet0's SBD rings into `en1` through `hakios.cell.c`. configd routes through it.

**Effort:** 2-3 weeks after M1. **Risk:** medium (the packet-attach and LTE default-bearer dialect).

The stock step (if M1.5 says go): `pdp_ip0` (IFT_CELLULAR), a QMI server for the boot-and-idle and data
subsets, and ApplePDPHelperInterface.

**Effort:** 6-10 weeks more. **Risk:** high.

**Needed:** a SIM with data.

### M3: SMS

WMS <-> Samsung SMS translation, delivery reports, SMSC from the SIM. Inbound SMS go to CommCenter, so this
needs the stock step of M2.

**Effort:** 2-3 weeks. **Risk:** medium (inherits M1.5).

### M4: voice

VOICE <-> Samsung CALL/SS signalling (2-3 weeks); the CP-ABOX call audio with calliope (unknown, probably more
than 2 months); the iOS baseband-audio interface (unknown).

**Risk:** very high. **Needed:** a network with 2G/3G CS voice, or IMS (VoLTE) support, which is a separate
large project.

## 6. Recommended first step

Two things that need no new code and can start now:

1. **The payload move.** Change the UEFI MemoryMapLib and the loader window so that 0xF0000000-0xF91FFFFF is
   free and untouched. This unblocks everything and is testable without the modem.
2. **One rooted-Android capture session**, read-only:
   - `dmesg` (the CP memory map and cbd's ioctl order);
   - `logcat -b radio`;
   - the FDT;
   - a `umts_ipc0`/`umts_rfs0` packet log;
   - the TOC entries of RADIO (names, offsets, sizes only: `dd bs=512 count=1 | xxd`);
   - the user's private copy of `nv_data.bin` and an EFS backup.

After that, M0 in `drivers/modem/hakios.shannon.c` behind `CONFIG_HAKIOS_SHANNON` (off by default) and
`shannon=N` step arguments, matching the `modem_step=` style of the POCO.

## 7. Prior art outside Samsung's kernel

- **libsamsung-ipc** (Replicant, **GPL-2.0-or-later**): the reference for SIPC message groups, the TOC, the
  `herolte` (Galaxy S7 / Exynos 8890, `modem_v1` family) boot and the RFS NV commands. The kernel still has to
  be Samsung's: it uses Samsung's char devices and ioctls. Packaged in postmarketOS (`libsamsung-ipc`). No
  device file for the 9810. Read for facts only; GPL code is not copied into our APSL kernel.
- **Tony Garnock-Jones (2020)**, "How to boot the Samsung Galaxy S7 modem with plain Linux kernel interfaces
  only": the cbd sequence reconstructed, and the source of lsi's herolte support.
- **FirmWire** (BSD-3-Clause): emulates Shannon firmware (`S360AP` class, `soc/__init__.py:70-84`). Useful for
  TOC parsing and the CP's memory map. It does not boot real silicon.
- **Mainline Linux / postmarketOS:** Exynos modem support exists only for old XMM626x-over-HSIC devices
  (Galaxy S2/S3, Note 2). There is **no known boot of an integrated Shannon CP (8890 onward) without
  Samsung's downstream kernel**. Booting it from XNU would be a first, which is why M0 is rated
  medium-risk rather than low.
- **seemoo-lab BaseTrace** (GPL-3.0) and **ARIstoteles**: the public description of the iPhone side (QMI over
  PCIe for Qualcomm iPhones, Apple's private QMI services). Read for facts only.
