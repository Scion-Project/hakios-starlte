# Speaker audio on the Galaxy S9

The S9's speakers are two Maxim MAX98512 amplifiers (I2C 0x39, the top one, and 0x3A, the bottom one, on USI07's HSI2C
of PERIC1) fed over I2S by UAIF1 of ABOX, Samsung's audio block. On Android, ABOX's own Cortex-A7 runs Samsung's
firmware (calliope) and programs the DMA; the speakers are protected by Maxim's DSM running on that CPU. Here ABOX's CPU
stays off ("bypass"): the AP programs everything, and the speakers' guard (`hakios.guard.c`) stands in for DSM. It plays:
a tone and iOS's sounds, seen on phone 2 on 3 November (below).

Two drivers in the common repository, both built into the S9's kernel and both off until a boot-argument asks:

| Driver | Boot-argument | What it does |
|---|---|---|
| `drivers/audio/hakios.exynos_abox.c` | `abox=N`, N of 8 steps | the SoC's side: memory -> RDMA0 -> SPUS -> SIFS1 -> UAIF1, I2S master, 48 kHz, 2 x 16 bits |
| `drivers/audio/hakios.max98512.c` | `max98512=N`, N of 3 steps | the amplifiers: 1 a look, 2 set up and muted, 3 handed to ABOX, whose UAIF1 turns them on and off |

The two meet at one hook, `hakios_abox_set_amp()` in `sys/hakios.exynos_abox.h`. iOS reaches the speakers the way it
reaches the POCO's: `/dev/hakios-audio` (`sys/hakios.audio.h`), whose sink ABOX's step 8 becomes
(`hakios_audio_set_sink`), as `hakios.sound.c` does on the POCO. iOS's volume (`HAKIOS_AUDIO_SET_VOLUME`) is taken off
the samples digitally before the guard (on the POCO the amplifiers take it off), and its mute stops the amplifiers.

## What the phone did (3 November, phone 2)

Every run was one image off `native-daily2`'s arguments (`loader_return_after=240` or 420) with the drivers' arguments
added, read from the USB console live and from `/proc/last_kmsg` in TWRP afterwards. The kernel was main at bd0450e, then
the branch of this change.

| Run | Arguments | What it said |
|---|---|---|
| a1 | `abox=6 max98512=2` | AUD domain on already (AUD_STATUS 0x10000f), ABOX's CPU on (ABOX_CPU_CONFIGURATION 1: switched off), SMC 0x82000410 returned 0, IP_INDEX 0x41424f58, VERSION 0x1010100; PLL_AUD 1179648040 Hz, stable after 1 us, every divider as wanted; gpb1 to UAIF1; UAIF1_CTRL1 reads 0x984f000; with SPK_ENABLE "gpb1-0..3 with UAIF1 on: 1856, 192, 0, 0 changes in 4000 reads over 2000 us" (none with it off): 192 changes of LRCLK in 2 ms is 48 kHz. Both MAX98512s: revision 0x41 at 0x39 and 0x3A, set up and muted |
| a2 | `abox=7 max98512=2` | "ABOX's SysMMU translates (CTRL bit 2)": MMU_CTRL 0x4, CFG 0x20000 as the boot leaves it (PT_BASE reads 0: run b1). Step 7 refused |
| b1 | `abox=7 max98512=3`, then `abox tone` on the console | SysMMU switched off (CTRL 0); SYSPOWER_CTRL 1 (STATUS 1); the ring in abox_rmem at 0xFB200000; RDMA0 CTRL0 0x400921 (BURST 8, FORMAT 9, BUF_UPDATE, ENABLE). Into SIFS0 (the mixer): STATUS 0x80000020, PROGRESS on but 32 bytes read and no more. `abox set route 1`, `abox tone 2`, into SIFS1: "194360 bytes a second read", then 192417; "the guard: peaks in 3277, out 3660"; both amplifiers on through it (GLOBAL_SHDN 1, AMP_EN 0x81), no fault flag |
| b2 | `abox=8 max98512=3` | iOS's sounds through `/dev/hakios-audio`: "abox: 8: iOS plays: starting the amplifiers", "from iOS 500224 frames (0 lost), 492032 fed", peaks 3651 to 6669 of 32768, "three seconds of silence: stopping the amplifiers"; RDMA0 at 178964 to 192025 bytes a second over the 5 s windows |
| b3 | `abox=8 max98512=3`, the amplifiers' fast start | "max98512: on: ... (start 2, unmuted only, 31054 us)"; "from iOS 148480 frames (0 lost), 148480 fed, 0 periods short" |

What it took, beyond what the driver had: the SysMMU switched off (the boot leaves it translating); a ring below 4 GB,
which the kernel cannot give (its RAM starts at 0x880000000), so abox_rmem's first 256 KB (the loader already keeps the
region out of UEFI and XNU); SYSPOWER_CTRL 1 and the ACLK and BCLK_UAIF1 Q-channels held on; RDMA0 CTRL0's FORMAT
[12:8], BUF_UPDATE and SBANK_LIMIT as calliope sets them (the Galaxy Tab Active3's firmware-less A-Box work read them out
of calliope's accessors); and SIFS1 rather than the mixer. Which of the CTRL0 fields were needed was not separated: the
first stream that moved had all of them (and with them, the mixer's way still stalls).

## How to hear it (for the owner)

1. An image with `abox=8 max98512=3` added to the daily arguments: `~/s9/out/s9audio-daily.img` on the MacBook is
   `native-daily2`'s arguments with them (`loader_return_after=0`, it stays up).
2. Once iOS is up, lock and unlock the phone or type on the keyboard: the lock sound and the clicks come from the
   speakers, at the receiver's level (15 dB under Android's speaker) times iOS's volume. The volume buttons change it
   (`abox: 8: iOS's volume: ...` in the log).
3. A tone without iOS: an image with `abox=7 max98512=3` plays 1 kHz at -20 dBFS for 3 s at boot; on the USB console
   (`usb_gadget=5`) `abox tone 3` plays it again. Keep the phone at arm's length the first time.
4. Which speaker is which: the top one (0x39, the earpiece) plays I2S's left channel, the bottom one the right. A tone
   in one channel only is not built in; `abox set` cannot do it yet.

## The USB console

`abox` says the AUD domain, the clocks, the route, UAIF1, RDMA0 and the SysMMU, then both amplifiers' INT_RAW1-3,
INT_STATE1-3, GLOBAL_SHDN, AMP_EN, SPK_GAIN, AMP_VOL, the measurement ADC's three channels, BROWNOUT_STATUS and the
boost's output reading. `abox tone S` makes steps 1-7 again (not while `abox=8` serves iOS); `abox set NAME VALUE` changes
`route`, `rdma_ctrl0`, `rdma_ctrl1`, `vol`, `bclk_on`, `sbank`, `burst`, `mmu_off`, `syspower`, `rdma_fmt`, `ring_pa` or
`secs` for the next tone; `abox r BLOCK OFF [N]` and `abox w BLOCK OFF VALUE` read and write registers (written: `abox`,
`mmu` and `gpio` only).

## What is left

- Listening. The amplifiers' registers do not show the tone at this level (the boost's output reads 0 throughout,
  the ADC's channels do not move), so the proof is ABOX's DMA rate and the guard's peaks. The measured proof would be the
  amplifiers' current and voltage sense (MEAS_EN, sent back on UAIF1's data in) captured by a WDMA.
- The mixer's way (SIFS0): RDMA0 stalls after 32 bytes; its sample bank (SBANK_MIXP) reads 0. Not needed for one stream.
- Headphones and the microphones: the CS47L93 (Cirrus "madera") on `spi@10470000`, chip select 0, at up to 25 MHz,
  reset on gpg1-0, the bus on gpp0-4..6 (SPI2, function 2) with its chip select gpp0-7; AVDD/DBVDD1/CPVDD1 from the PMIC's
  LDO33 (vdd_pmic_codec_1p8, always on) and CPVDD2/DCVDD from LDO34 (vdd_codec_1p2, 1.2 V, off until the codec's driver
  asks: a PMIC write); its AIF1 and AIF3 to ABOX's UAIFs. Needs an SPI driver for the 9810 (none here yet), the
  supplies, the reset, then the codec's ID; its FLL and its DSP firmware after that. Upstream Linux's madera driver
  supports the CS47L93; the Tab Active3 work has the WDMA side of capture.
- The amplifiers' start costs 31 ms of I2C after iOS's first loud frames; the beginning of a click may be lost.

## Sources

The S9's kernel (`sound/soc/samsung/abox/`: abox.c, abox.h, abox_rdma.c, abox_if.c; `sound/soc/codecs/max98512.c`,
`max98512.h`; the device tree `exynos9810-starlte_eur_open_26.dts`), the Galaxy Tab Active3's firmware-less A-Box work
(github.com/exynos-linux/samsung-gtactive3wifi: docs/re/abox.md and patch 0106, RDMA CTRL0's fields, SYSPOWER_CTRL) and
the Galaxy S10's
(github.com/ivanmeler/android_kernel_samsung_beyondlte: `abox_soc.h`, `abox_cmpnt_v20.c`, `abox_rdma.c`, `Kconfig`),
both GPL-2.0, read for facts only. Nothing of them is copied; the drivers' heads name the functions each fact comes from.
