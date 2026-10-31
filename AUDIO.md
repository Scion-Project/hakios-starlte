# Speaker audio on the Galaxy S9

The S9's speakers are two Maxim MAX98512 amplifiers (I2C 0x39, the top one, and 0x3A, the bottom one, on USI07's HSI2C
of PERIC1) fed over I2S by UAIF1 of ABOX, Samsung's audio block. On Android, ABOX's own Cortex-A7 runs Samsung's
firmware (calliope) and programs the DMA; the speakers are protected by Maxim's DSM running on that CPU. Here ABOX's CPU
stays off ("bypass"): the AP programs everything, and the speakers' guard (`hakios.guard.c`) stands in for DSM.

Two drivers in the common repository, both built into the S9's kernel and both off until a boot-argument asks:

| Driver | Boot-argument | What it does |
|---|---|---|
| `drivers/audio/hakios.exynos_abox.c` | `abox=N`, N of 8 steps | the SoC's side: memory -> RDMA0 -> SPUS -> SIFS0 (the mixer) -> UAIF1, I2S master, 48 kHz, 2 x 16 bits |
| `drivers/audio/hakios.max98512.c` | `max98512=N`, N of 3 steps | the amplifiers: 1 a look, 2 set up and muted, 3 handed to ABOX, whose UAIF1 turns them on and off |

The two meet at one hook, `hakios_abox_set_amp()` in `sys/hakios.exynos_abox.h`. iOS reaches the speakers the way it
reaches the POCO's: `/dev/hakios-audio` (`sys/hakios.audio.h`), whose sink ABOX's step 8 becomes
(`hakios_audio_set_sink`), as `hakios.sound.c` does on the POCO. iOS's volume (`HAKIOS_AUDIO_SET_VOLUME`) is taken off
the samples digitally before the guard (on the POCO the amplifiers take it off), and its mute stops the amplifiers.

## Can ABOX's DMA run without its firmware?

Android's source cannot answer it, because Android never tries. With the firmware not loaded, `abox_enable()` turns the
clocks on, puts back the registers the AP owns and sets the pins, then `abox_download_firmware()` returns `-EAGAIN` and
ABOX's CPU is never started; every message a stream then sends (`PCM_SET_BUFFER`, `PCM_PLTDAI_HW_PARAMS`, `_TRIGGER`)
is dropped by `abox_can_calliope_ipc()` ("Invalid calliope state"). UAIF1 and the routing are still written by the AP
directly, but nothing writes RDMA0, and `abox_rdma_pointer()` reads STATUS's PROGRESS as 0: the stream stalls.

What the source does say:

- The AP owns UAIF1 (CTRL0/CTRL1: format, master mode, SPK_ENABLE), SPUS_CTRL0/1/2/3 (the chain, the SIFS selection, the
  mixer's format and flush), ROUTE_CTRL0-2, QCHANNEL_DISABLE and the SIFS counts: all written through its regmap
  (`abox_if.c`, `abox.c` DAPM muxes, `abox_restore_register()`). Bypass writes the same registers the same way.
- RDMA0's registers sit on the AP's bus as plain registers: the AP reads STATUS and CTRL0 directly, and writes RDMA3's
  VOL_FACTOR (0x17C51318) through the same regmap.
- What calliope gives RDMA0 that the AP must give instead: BUF_STR/END/OFFSET, STR_POINT, CTRL0/CTRL1 (no field named
  in the 9810's source but ENABLE), SPUS's sample bank for RDMA0 (0x17C50220, reset 0; the 9810's AP never touches it),
  the buffer through ABOX's SysMMU at IOVA 0x91000000, and ABOX's GIC for its interrupts.
- Samsung's next ABOX driver (the Galaxy S10's kernel, whose header covers the 9810's ABOX version 0x10100) names two of
  the missing pieces, and there the AP sets them itself: the sample bank's SIZE [29:20] (512 bytes for periods over
  10 ms) and RDMA CTRL0's BURST_LEN [22:19] (8). Bypass sets both when they read 0 (`abox_sbank=`, `abox_burst=`).

What stays unknown until the phone runs: which bits of RDMA0's CTRL0/CTRL1 carry the format, what BUF_END and BUF_OFFSET
mean exactly, VOL_FACTOR's unity, and whether the RDMA's register block accepts the AP's writes (a TrustZone
partition could refuse them). Step 7 measures what it can (STATUS's movement, the bytes read per second, a position
outside the ring) and has boot-arguments to try the alternatives without a rebuild. Should RDMA0 not move at all, the
fallback is a firmware mode (calliope booted once, its RDMA0 registers read back), which needs ABOX's SysMMU given page
tables.

## The first runs

One image per run, each read from pstore in TWRP afterwards (README.md, "On the phone"). Build with the arguments
explicitly, and with `cpus=2 bootcpu=2` among them: `mkimage.sh` given any arguments uses those alone, in place of the
configuration's. Every line of the drivers starts with `abox:` or
`max98512:`. 32 KB of pstore holds about 300 of these lines: if a run's start is cut off, run it again with fewer
other drivers on.

| Run | Arguments | What to look for |
|---|---|---|
| 1 | `abox=1` | `abox: 1: the AUD domain is off` (or ON already); `ACPM's AUD DVFS domain (9): at N kHz` |
| 2 | `abox=2` | `the AUD domain is on after N us`; `SMC 0x82000410 returned 0`; `ABOX IP_INDEX (0x17c50000) = 0x41424f58`; `ABOX's CPU is off and stays so (bypass)`; at the end `the AUD domain is off` |
| 3 | `abox=3` | `PLL_AUD stable after N us`; `PLL_AUD 1179648xxx Hz; so ACLK 589824xxx, its APB 196608xxx, AUDIF 73728xxx, UAIF1's BCLK 1536000` |
| 4 | `abox=4` | `gpb1 CON (0x17c60020): ... reads 0x....2222` |
| 5 | `abox=5` | `UAIF1_CTRL1 (0x17c50514): 0 -> wrote 0x984f000, reads 0x984f000`; `gpb1-0..3 with UAIF1 on:` changes on at least one pin (with UAIF1 off: none) |
| 6 | `abox=6` | `SPUS's sample banks (0x17c50220 on): RDMA0-7 ...` and `RDMA0's bank: N bytes at ...`; then `about to give RDMA0 a sample bank of 512 bytes` and `SPUS_SBANK_RDMA0 (SIZE)` written and read back (`RDMA0's sample bank left as it reads` when the bank was not 0 already) |
| 7 | `max98512=1`, then `max98512=2` | `max98512: top (0x39): MAX98512, revision 0x..` and the same for 0x3A; then both chips' registers after the set-up, shut down |
| 8 | `abox=7` (no amplifiers: nothing is heard) | `RDMA0 STATUS each ms:` values that change; `N bytes a second read (192000 is 48 kHz 16-bit stereo)` near 192000; `RDMA0 stopped after N us` |
| 9 | `abox=7 max98512=3` | `max98512: on: 48000 Hz, 2 x 16 bits, I2S ...`; a 1 kHz tone from both speakers for 3 s (quiet: -20 dBFS at the receiver's level) |
| 10 | `abox=8 max98512=3`, the full iOS image | `hakios-audio: sound goes to ABOX: RDMA0 -> UAIF1 -> the speakers`; `abox: 8: iOS plays: starting the amplifiers` on the first sound; `iOS's volume: ...` when the slider moves |

If run 8's STATUS does not move, one run each, in this order, keeps the rest the same:

1. `abox=7 abox_sbank=0 abox_burst=0`: RDMA0's sample bank and burst length left as they read (did ours get in the way?)
2. `abox=7 abox_route=1`: UAIF1 from SIFS1, the mixer out of the path (its own sample bank, at 0x17C50260, reads 0 too)
3. `abox=7 abox_bclk_on=1`: UAIF1's BCLK never gated by ABOX
4. `abox=7 abox_rdma_ctrl0=0x4 abox_rdma_ctrl1=...`: format bits, guided by what runs 6 and 8 printed of RDMA0's registers

A position outside the ring (`is outside the ring`) or a rate of 96000 or 384000 bytes a second says the format or the
meaning of BUF_END differs from the guess; the line says which. Run 9 is the first with sound: keep the phone at arm's
length and the volume as it is (the amplifiers start at Android's receiver level, 15 dB under its speaker).

## Sources

The S9's kernel (`sound/soc/samsung/abox/`: abox.c, abox.h, abox_rdma.c, abox_if.c; `sound/soc/codecs/max98512.c`,
`max98512.h`; the device tree `exynos9810-starlte_eur_open_26.dts`) and the Galaxy S10's
(github.com/ivanmeler/android_kernel_samsung_beyondlte: `abox_soc.h`, `abox_cmpnt_v20.c`, `abox_rdma.c`, `Kconfig`),
both GPL-2.0, read for facts only. Nothing of them is copied; the drivers' heads name the functions each fact comes from.
