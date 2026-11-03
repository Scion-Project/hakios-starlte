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
- Headphones: the CS47L93's OUT2, written behind `cs47l93_hp=1` and not yet tried (below, "The headphones"). The main
  microphone is iOS's (below, "The microphone in iOS").
- The amplifiers' start costs 31 ms of I2C after iOS's first loud frames; the beginning of a click may be lost.

## The codec: the main microphone, and the headphones' path (3 November)

The headphones, the jack and the microphones go through the audio codec, a Cirrus Logic CS47L93 (Cirrus's Madera
family) on SPI: spi@10470000, USI01 of PERIC0, chip select 0. Two more files in the common repository, built into
this phone's kernel (`configs/starlte.config`) and off until a boot-argument asks:

| Driver | Boot-argument | What it does |
|---|---|---|
| `drivers/core/hakios.exynos_spi.c` | none | an Exynos SPI master, polled: the USI's clocks and mode (2), the pins, the FIFO, the chip select by hand (`sys/hakios.exynos_spi.h`) |
| `drivers/audio/hakios.cs47l93.c` | `cs47l93=N`, N of 6 steps | 1 a look; 2 LDO34 (DCVDD, 1.2 V) checked on, the reset held and let go, the ID read; 3 the jack; 4 MCLK1 (the SoC's CLKOUT0, 26 MHz), FLL1, SYSCLK 98.304 MHz; 5 MICVDD, MICBIAS1/1A, IN3L (the main microphone, digital); 6 AIF1, a slave I2S of 2 x 16 bits at 48 kHz, sending IN3L |

ABOX's side of the capture is `hakios.exynos_abox.c`'s: the console's `abox rec S` makes steps 1-4 (power, clocks,
pins) and then UAIF0 (the codec's link, ABOX the master, 1.536 MHz BCLK) -> NSRC0 -> SPUM (no ASRC) -> SIFM0 -> WDMA1
into 64 KB of abox_rmem, copied out every millisecond for S seconds; then each channel's mean, RMS and peak, and the
PCM goes out on the USB console in a camshot's framing (`SHOT <w> 1 ...`, 48 kHz 16-bit stereo, little-endian).
`codec` on the console says the codec's state; `codec r REG [N]` / `codec w REG VALUE` read and write its registers;
`codec mic` makes steps 1-6 again.

Two things the firmware-less path needed, found on the phone (phone 1, 3 November):

- NSRC0's sample bank in SPUM (`SPUM_SBANK_NSRC0`, 0x17C50328, named in the Galaxy S10's kernel) reads 0 after the
  boot. With it 0, WDMA1 says PROGRESS and writes nothing, and UAIF0's STATUS says ERROR_OF_MIC; given 512 bytes, as
  RDMA0's bank, WDMA1 writes 192000 bytes a second.
- AIF1's four pins are the codec's GPIO5-8, plain GPIOs after its reset (`0x2001`); ABOX then records zeroes. Given
  their alternate function (FN 0, bus hold: the device tree's `cs47l93-gpio-defaults`) the codec's samples come.

### The runs (phone 1, 2ab4dd7d2a037ece)

| Image | Arguments | What it showed |
|---|---|---|
| c1 | `cs47l93=2` | `ID 6371 (a CS47L92/93), revision 0001`; `booted (IRQ1_RAW_STATUS_1 0080) within 5097 us`; the SPI: 0 errors. LDO33 reads `ec` and LDO34 `e8` (on, 1.2 V) as the boot leaves them; the reset pin is an output, low |
| c2 | `abox=1 cs47l93=6` | FLL1 from MCLK1 locks in about 1 ms (N 22, THETA 1114, LAMBDA 1625, fractional, the fast oscillator); SYSTEM_CLOCK_1 `0444`. Step 5 stopped at IN_VU reading 0 (fixed); `abox rec`: WDMA1 waits, ERROR_OF_MIC (the sample bank, above); then zeroes (the pins, above) |
| c4 | `abox=1 max98512=3 cs47l93=6` | the six steps; `abox rec 3`: 192480 bytes a second, UAIF0 STATUS 0, the PCM on the Mac whole (`END` after it) |

It was night: no sound was played and nobody spoke, so the microphone was shown without any:

- The noise floor varies and is not a constant: at IN3L's +8 dB (the default) RMS 1.5 of 32768 (-86.6 dBFS), samples
  from -8 to 7, 15 values; at +31.5 dB RMS 22-24, peaks 114-127 (23.5 dB more gain, 15 times the RMS: the input's own
  noise, scaled by its gain); at 0 dB RMS under 1.
- IN3L muted (ADC_DIGITAL_VOLUME_3L's mute): 47995 of 48000 samples exactly 0.
- The codec's tone generator (0x20 TONE1_ENA) into AIF1TX2, no output driver on (OUTPUT_ENABLES_1 reads 0): the right
  channel came back as a clean 1 kHz sine at full scale (2002 zero crossings a second, peak 32751), the left (IN3L) at
  its noise floor: the codec -> AIF1 -> UAIF0 -> WDMA1 -> memory -> USB path is exact.

Not done then: the headphones and the recording reaching iOS (both below), the jack's microphone and impedance
detection, the other microphones (IN4L, the headset's IN1BL).

## The microphone in iOS (3 November, phone 1)

`abox_mic=1` with `abox=8 cs47l93=6`: iOS's input is the codec's main microphone. Nothing new in user space: the
audio server's plug-in (`userland/src/audio_plugin.c`, HakiosAudio.driver) has had a device "Codec" since the POCO's
microphone, one 48 kHz 16-bit channel read from `/dev/hakios-mic`, of which iOS's virtual audio device makes the
built-in microphone. What is new is the kernel's side:

- `/dev/hakios-mic` moved from `hakios.mic.c` (the POCO's, through its DSP) into `hakios.audio.c`, the same for every
  phone: a ring of 341 ms, read 40 ms behind the microphone, open only while iOS's input runs
  (`hakios_audio_input_create/_wanted/_put`).
- ABOX's step 8 makes it (with `abox_mic=1`) and, whenever it is open, starts the capture "abox rec" proved: UAIF0 ->
  NSRC0 -> SIFM0 -> WDMA1 into the 64 KB ring at abox_rmem +1 MB, followed every 2 ms by the same loop that feeds
  RDMA0; the left slot (AIF1TX1: IN3L) goes into `/dev/hakios-mic`. When iOS closes it, WDMA1 and UAIF0's microphone
  side stop, and a line says how long, how loud (RMS, peak) and how many samples were exactly 0.

What iOS saw (`mic_rms`: AVAudioSession in the record category, which has no output, then an AudioQueue of 48 kHz mono
16-bit for 3 s; built on the MacBook with the iOS SDK, `-target arm64-apple-ios16.5`, signed ad hoc with
`com.apple.private.tcc.allow` kTCCServiceMicrophone, and in the ramdisk of that test only). The image: the daily
arguments with `abox=8 cs47l93=6 abox_mic=1` and NO `max98512` (no amplifier switched on: night, nothing to be heard):

| Run | What | iOS (mic_rms) | The kernel (what WDMA1 brought) |
|---|---|---|---|
| A | the room, silent | `MicrophoneBuiltIn "iPhone Microphone"` the route's one input; 144000 samples, RMS 94.8 (-50.8 dBFS), peak 696 | 3.13 s, RMS 3, peak 25; 0 frames skipped, 0 reads short |
| B | the room | RMS 57.9 (-55.0 dBFS), peak 308, 3027 of 144000 samples 0 | 3.11 s, RMS 1, peak 10 |
| C | the same program unsigned | the permission to record `deny` (TCC): no samples | (the device was opened: 6 s heard) |
| D | the codec's tone generator into AIF1TX1 (`codec w 0x0700 0x0004`, `codec w 0x0020 0x0001`; no output on) | a clean tone: zero crossings 987 Hz, peak 29992, RMS 5902 (iOS's input processing brings a full-scale tone down: 12808 in the first 0.1 s, 2811 by the ninth) | RMS 23170, peak 32751, 0 samples 0: a full-scale sine |

Twice more on the same night (images mic-t2 and mic-t3: the same, with `cs47l93_hp=1 cs47l93_hp_vol=0` added, mic-t3
with the plug-in rebuilt from this branch): the room 3.11-3.13 s at RMS 1 in the kernel, RMS 57-61 in iOS; the tone
again a 987 Hz tone in iOS. With `cs47l93_hp=1`, at power-up: `Cirrus's register patch written (38 16-bit, 28 32-bit
registers), 2 not read back as written` (0x180B and 0x190B, IRQ masks, read 0; every 32-bit write of the write sequencer
read back exact: the 32-bit register access works); `the headphones: the jack watched (nothing plugged in now)`;
OUTPUT_ENABLES_1 read 0 throughout (OUT2 never on). The rebuilt plug-in: `the speaker has a jack (empty)`, and the
microphone through it as before.

The noise floor reaches iOS some 30 dB up (its input chain's gain): quiet, but never zeros, and the codec's own
tone comes through as a tone. Voice Memos and dictation use the same input (an app has its own microphone
entitlement; a program of ours needs one, run C).

## The headphones (`cs47l93_hp=1`: written, NOT tried yet)

The code is in, off by default; nothing of it runs without `cs47l93_hp=1`. With it, the codec's driver
(`hakios.cs47l93.c`, THE HEADPHONES in its head) does what Cirrus's driver does on Android:

- at power-up (step 2), Cirrus's register patch for the chip (`cs47l92_reva_16_patch` and the write sequencer's
  `cs47l92_reva_32_patch`), each register read back;
- after step 6, the jack read every 100 ms (`MICD_CLAMP_RISE` 0: plugged in), a change taken after three equal reads;
- plugged in: first ABOX (`hakios_abox_headphones(true)`: the amplifiers stopped and kept off, UAIF0's speaker side
  routed from the SIF UAIF1 takes, SIFS1, and switched on: iOS's samples into AIF1RX1/2, which step 6 mixes into
  OUT2L/R at 0 dB), then OUT2: its digital volume (`cs47l93_hp_vol`, default 0x68, -12 dB) set muted,
  OUT2L_ENA/OUT2R_ENA, 6 ms an output, unmuted;
- pulled out: OUT2 muted and off (1 ms an output), then the sound is the speakers' again;
- each change to `/dev/hakios-audio` (`HAKIOS_AUDIO_GET_ROUTE`); the plug-in polls it and tells the HAL that the
  speaker device's `kAudioDevicePropertyJackIsConnected` changed.

Not done: the headphones' impedance (HPDET), the headset's microphone and buttons, the output clamp around the jack's
insertion (a click is possible). One INFERRED register fact: that SIFS1 may feed UAIF0 and UAIF1 at once.

### The test, for the owner (daytime)

1. An image with the daily arguments and `abox=8 max98512=3 cs47l93=6 abox_mic=1 cs47l93_hp=1` (and `usb_gadget=5`,
   in the daily ones, for the console): `~/s9/out/s9mic-hp.img` on the MacBook is that, `loader_return_after=0`, with
   the plug-in of this branch in its ramdisk (`~/s9/out/s9mic-daily.img`: the same without `cs47l93_hp=1`, the old
   plug-in; the speakers and the microphone). Headphones NOT on your ears for the first plug-in.
2. Boot with nothing in the jack; play music quietly from the speakers. The log says
   `cs47l93: the headphones: the jack watched (nothing plugged in now)` and, once the patch was written,
   `cs47l93: Cirrus's register patch written (38 16-bit, 28 32-bit registers), N not read back as written`.
3. Plug the headphones in. Within half a second: `cs47l93: the jack: something plugged in`, `abox: headphones: iOS's
   sound to UAIF0 ...`, `abox: 8: the headphones have the sound: stopping the amplifiers`, `cs47l93: the headphones:
   OUT2 on (OUTPUT_STATUS_1 ...)`, `hakios: audio: the jack: plugged in; the kernel sends the sound to the
   headphones`. The speakers stop; the music is in the headphones (at -12 dB, under iOS's volume).
4. Pull them out: `OUT2 muted and off`, `the sound is the speakers' again`; the speakers come back with the next sound.
5. If the headphones stay silent, on the USB console: `codec r 0x400 2` (0x400's bits 3 and 2 set, 0x401 their status),
   `codec r 0x419 1` and `codec r 0x41d 1` (bit 8, the mute, clear), `abox r abox 0x40 1` (ROUTE_CTRL0: [3:0] the same
   as [7:4]), `abox r abox 0x500 1` (UAIF0 CTRL0: bit 0, SPK_ENABLE, set). Louder or quieter: `cs47l93_hp_vol=0x70`
   (-8 dB) or `0x50` (-24 dB); never above 0x80 (0 dB).
6. iOS's side: whether Control Center's output and the volume HUD say "Headphones" after the jack goes in (the plug-in
   only says the speaker's jack is connected; whether the virtual audio device makes a headphones route of that is
   what this shows). Either way the sound goes where the kernel sends it.

## Sources

The S9's kernel (`sound/soc/samsung/abox/`: abox.c, abox.h, abox_rdma.c, abox_if.c; `sound/soc/codecs/max98512.c`,
`madera.c`, `cs47l92.c`; `drivers/mfd/madera-core.c`, `madera-spi.c`, `cs47l92-tables.c`; `drivers/extcon/extcon-madera.c`;
`drivers/pinctrl/cirrus/`; `drivers/spi/spi-s3c64xx.c`; `drivers/soc/samsung/usi_v2.c`; `sound/soc/samsung/star_madera.c`;
`max98512.h`; the device tree `exynos9810-starlte_eur_open_26.dts`) and the Galaxy S10's
(github.com/ivanmeler/android_kernel_samsung_beyondlte: `abox_soc.h`, `abox_cmpnt_v20.c`, `abox_rdma.c`, `Kconfig`),
both GPL-2.0, read for facts only; the Galaxy Tab Active3's firmware-less ABOX work (github.com/exynos-linux/
samsung-gtactive3wifi, docs/re/abox.md and patch 0106: RDMA CTRL0's fields, SYSPOWER_CTRL, the WDMAs' registers and the
capture's route), read for facts;
and the phone's own `/vendor/etc/mixer_paths.xml` (the S9's routes: UAIF0 the codec's, IN3L the main microphone,
HPOUT2 the headphones). Nothing of them is copied; the drivers' heads name the functions each fact comes from.
