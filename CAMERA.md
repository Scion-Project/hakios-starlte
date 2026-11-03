# The Galaxy S9's cameras: what it takes, and the plan

State: the front camera works (`drivers/camera/hakios.exynos_camera.c`, run on the phone, 3 November): one picture
on the USB console's `camshot` (`cam_s9=6`), auto-exposed to 18 % grey and demosaiced at the full 1632 x 1224; and a
stream for iOS (`cam_s9=7`): 30.0 frames a second into a ring of four frames, `/dev/hakios-camera`, and **the stock
Camera app's preview** through libhakios.media's capture device in mediaserverd (with `cam=5`, the loader's
`/arm-io/isp` node that puts Camera.app on the home screen). Stage 5 (the rear camera) is a plan.
Everything below comes from Samsung's BSP (android_kernel_samsung_exynos9810, lineage-24.0, e5906667; the
device tree exynos9810-starlte_eur_open_26.dts in it), read for facts only (GPL-2.0, never copied).

## The hardware

| | Rear (wide) | Front |
|---|---|---|
| Sensor | Samsung S5K2L3 (12 MP, dual pixel), `fimc-is_sensor_2l3@20`, position 0 | Samsung S5K3H1 (8 MP), `fimc-is_sensor_3h1@6A`, position 1 |
| I2C | 0x10 on hsi2c@10860000 (PERIC1's I2C_CAM0, pins gpc0-0/1) | 0x35 on hsi2c@108F0000 (USI08_I2C of PERIC1, pins gpp5-2/3, function 3), 400 kHz |
| Reset | gpg2-6 (PERIC0) | gpg2-5 (PERIC0) |
| MCLK | CIS_CLK0, pin gpc1-4 function 2 | CIS_CLK1, pin gpc1-5 function 2 |
| MCLK rate | 26 MHz (OSCCLK, `exynos9810_fimc_is_sensor_mclk_on`) | 26 MHz |
| Supplies | S2MPB03 (0x56 on hsi2c@14300000): VDDD_1.0V_CAM, VDDQ_1.1V_CAM, VDDIO_1.8V_CAM, VDDD_RET_1.0V_CAM, VDDA_2.15V_CAM, VDDA_2.95V_CAM; the S2MPB02: VDDAF_COMMON_CAM (3.3 V), the OIS's three | the S2MPB02 (0x59, the flashlight's chip): LDO5 VDDD 1.05 V, LDO6 VDDIO 1.8 V, LDO13 VDDA 2.8 V, LDO16 VDDAF 2.8 V |
| Lens | AK737x AF, OIS (Rumba S4), AK7372 aperture on hsi2c@10870000 | AK737x AF on hsi2c@10900000 |
| MIPI | CSIS0, 4 lanes (D-PHY "m4s4 top") | CSIS1, 2 lanes, 1473 Mbps a lane at 3264x2448 (719 at 1632x1224), D-PHY "m0s4s2" |
| Frames | RAW10, 4032x3024 | RAW10, 3264x2448, 30 fps; 1632x1224 at 30 |

The EUR tree has only the S5K2L3 at the back (CONFIG_CAMERA_CIS_2L3_OBJ; no IMX345 in the starlte defconfig). The
third sensor in the tree, the 5F1 (`fimc-is-secure@10`, MCLK2, reset gpg2-3), is the iris scanner's.

The front camera is the first target: all four of its supplies are on the S2MPB02, which this port already talks to
(the flashlight), its power sequence is short (no OIS, no retention), and it has two lanes.

## Is the ISP's firmware needed?

Not for raw frames. On the Exynos 9810 (fimc-is v6.0.0, `CONFIG_USE_DIRECT_IS_CONTROL`) there is no ISP CPU and no
companion chip: the "firmware" is two closed libraries the Linux driver loads into kernel memory and calls on the AP
itself, `fimc_is_lib.bin` (the DDK: 3AA, ISP, MCSC, DCP; `LIB_ISP_ADDR`, `get_lib_func` in fimc-is-interface-ddk.h)
and `fimc_is_rta_2l3_3h1.bin` (the 3A), with `setfile_3h1.bin`/`setfile_2l3.bin` (tuning). They are bound to Linux's
kernel ABI (a table of OS callbacks), so they would need a Linux-shaped host inside XNU: weeks, and fragile.

What does not need them: the CSIS. `CONFIG_USE_CSI_DMAOUT_FEATURE=y` (the starlte defconfig) makes each CSIS write its
virtual channels to memory through its own WDMA (fimc-is-hw-csi-v5_1.c, `CSIS_V5_1`: `csi_hw_s_config_dma`,
`csi_hw_s_dma_addr`, `csi_hw_s_output_dma`, `csi_hw_s_dma_common`), all registers the AP programs; Android then feeds
3AA from memory. So: sensor over I2C, MIPI into CSIS1, CSIS1's VC0 WDMA writes RAW10 to memory. That is what the
POCO's driver does with Qualcomm's RDI path, and exactly the frame `/dev/hakios-camera` hands up (`struct
hakios_camera_frame`, format 1: MIPI RAW10). The colour work (debayer, white balance, gamma, scaling) is already done
on the CPU in user space (userland/src/camera_isp.c); with no tuning file it runs without a colour matrix or lens
shading, so the first pictures will be flat but right.

The CSIS DMA common block has its own test pattern generator (`csi_hw_s_dma_common_pattern`: TEST_PATTERN_CTRL,
_RESOL, _ENABLE), which proves the DMA without a sensor, as the POCO's `cam=3` uses the CSID's.

## The register map (from the device tree)

| Block | Address |
|---|---|
| CSIS0 / CSIS1 / CSIS2 / CSIS3 link | 0x16230000 / 0x16240000 / 0x16250000 / 0x16260000 |
| CSIS1's VC0-3 WDMA, its DMA common | 0x162C0000, +0x100, +0x200, +0x300; 0x162C0400 |
| CSIS0's VC0-3 WDMA, its DMA common | 0x162B0000-0x162B0300, 0x162B0400; a second set at 0x16380000 (its `dma_ch` 4) |
| The four CSISs' DMA common (arbitration, SRAM split, the test pattern generator) | 0x162F0000 (fimc_is@16290000's first region, IORESOURCE_CSIS_DMA) |
| Each CSIS's D-PHY registers (the node's second region, `csi->phy_reg`) | 0x16160000 (CSIS0), 0x16180000 (CSIS1), 0x16170000 (CSIS2), 0x16190000 (CSIS3) |
| D-PHY control (reset bits 0-3) | 0x16210500 (SYSREG_ISPPRE); PMU isolation 0x1406070C (CSIS0), 0x14060730 (CSIS1 and 3), 0x14060710 (CSIS2) |
| Power domain ISPPRE | PMU 0x14064048 / status 0x1406404C (its on/off needs an SMC, `need_smc` 0x16210004); its parent is pd-dpu |
| SysMMU in front of 3AA/PDP/CSIS DMA | 0x16310000 (`sysmmu@16310000`, secure base 0x16300000) |
| CSIS gates | GATE_IS_ISPPRE_CSIS0-3: Q-channels of CMU_ISPPRE (0x16200000 +0x3020-0x302C), MUX_CIS_CLK0-3 |
| Interrupts | CSIS0 SPI 328, CSIS1 329; their DMA 334/335 |

## The stages (cam_s9=N, each logged before it is taken)

1. **Written.** `cam_s9=1` looks: the pins, CIS_CLK1, the two buses, the S2MPB02's ID and its four camera LDOs.
   `cam_s9=2`: the front sensor powered up in Android's order, its model ID (0x0000), revision (0x0002), frame count
   and mode read over I2C, powered down. Risk: low (three LDOs to Android's voltages, read back, switched off again;
   one pin each for reset and MCLK; one CMU gate). Effort: done, a run or two to see it.
2. **Written: the ISPPRE domain and CSIS1 seen, and the test pattern in memory.** `cam_s9=3`: power domain ISPPRE on
   (pmucal's isppre_on: the PMU's configuration [3:0] = 0xF and the status waited for, its parent pd-dpu checked on),
   then the SMC the BSP's exynos-pd makes after it (0x82000410 with 1, 0x16210004: the DTZPC restore, as hakios.mali.c
   does for the G3D); CMU_ISPPRE's bus taken from CMU_TOP and the Q-channels of the four CSISs, the PDP's DMA and the
   SysMMU requested; CSIS1's version, its VC0 WDMA, the DMA common and the SysMMU's MMU_CTRL read. `cam_s9=4`: the
   D-PHY's isolation bypassed (PMU 0x730 bit 0) and its reset released (0x16210500 bit 2), CSIS1 reset and set up
   (two lanes, CSI_MODE_VC_DT, VC0 RAW10 1632 x 1224, CH2 the embedded data), a 4 MB buffer below 4 GB (at 0xD8000000,
   outside XNU's RAM: the memory table in README.md) given to all
   eight of VC0's frame pointers, the DMA common as csi_hw_s_dma_common leaves it, and the test pattern generator on
   for one frame (with the pattern on, Android does not enable the link); the frame end waited for (2 s), the WDMA
   and the pattern off, the buffer's checksum and first bytes logged. Only with the SysMMU seen off (its state after
   the domain's power-on): the DMA's address is then the buffer's physical one. On the way down: the domain off with
   pmucal_lpm_init's MEMORY_ISPPRE_OPTION and the DTZPC save first, if this run switched it on.
   Risk: medium (the SMC; which CSIS DMA the generator feeds: the other three's interrupt sources are logged too).
3. **Written: a frame of the sensor's.** `cam_s9=5`: the sensor kept powered after step 2, setfile A's mode table for
   1632 x 1224 (the device tree's `setfile = "default"` is A: fimc-is-cis-3h1-setA.h, 86 16-bit writes, data written
   as given), 0x3092 = 0, an exposure (0x0202, `cam_s9_exp`) and gain (0x0204, `cam_s9_gain`); the D-PHY's timing
   (settle 36 at 720 Mb/s from fimc-is-hw-settle-10nm-lpp.h, the table the 9810's chain includes; HS_MODE_SEL below
   1.5 Gb/s, no skew calibration), the link on (csi_hw_enable), streaming on; two frame ends of the WDMA waited for
   (1.5 s), the WDMA off, streaming off; the CSIS's error bits, frame counter and PHY state, the checksum, and the mean
   of a 64 x 64 patch in the middle read as MIPI RAW10. Risk: medium (the settle; whether the mode table needs a
   global init the BSP does not show). The header of the driver has every register.
   **Written: camshot.** `cam_s9=6` makes steps 1 to 5 at the start and then keeps the camera's thread for the USB
   console (`usb_gadget=5`): `camshot [N]` powers the sensor up, takes one frame as step 5 does, powers everything down
   again, debayers the frame on the processor (each 2 x 2 cell of GRBG one pixel, 816 x 612, every Nth for N > 1; the
   black level off, a grey-world balance, the green's mean to 18 %, a gamma of 2) and sends it the way `shot` sends the
   panel; `camshot N tp` does the same with the test pattern (steps 3 and 4). A capture that fails answers
   "usb: camshot failed: ..." with CSIS1's interrupt sources, frame counter and PHY state and the WDMA's control,
   status and error code. On the host: `tools/usb-shot.py --cam -o cam.png`. The frame's buffer and the picture are
   physical memory at 0xD8000000 (8 MB), mapped once through IOKit (the WDMA's addresses are 32 bits and XNU has no
   memory below 4 GB on this phone). `cam_s9_bayer=0-3` and `cam_s9_stride=` correct the debayer's guesses.
4. **Done: the exposure, the stream and /dev/hakios-camera** (hackios-xnu-kernel, s9/cam-next).
   *Exposure.* The meter: the green of every 16th 2 x 2 cell of the frame's middle half (about 1900 cells), the black
   level (64) off; the aim 18 % of the range above it (172 of 959). The 3H1's registers (fimc-is-cis-3h1.c, facts
   only): 0x0202 the coarse integration time in lines (2 to the frame's 1266 less 4: 33.2 ms at most at 30 frames a
   second), 0x0204 the analog gain (0x20 = 1x; the sensor gives its range at 0x0084/0x0086: 0x20 to 0x200, 16x),
   0x020E the digital gain (0x100 = 1x; capped at 4x, `cam_s9_dgain`), written under the grouped parameter hold
   (0x0104). A change written after frame N's end shows in frame N + 3 (seen): the meter reads every third frame.
   A camshot converges in 4 to 15 frames (`cam_s9_ae_frames`); the stream steps half-way every third frame.
   In the dark room of the first runs it ends at 33 ms, 16x and 2.7-4x digital, the green at the aim.
   *Ring.* The WDMA's eight frame pointers on four 4 MB slots at 0xD8000000 (32 MB to 0xD9FFFFFF, mapped through
   IOMemoryDescriptor::withPhysicalAddress, never ml_io_map; UFS's own-mode memory starts at 0xDA000000). Seen: the
   active frame pointer (ACT_CTRL [4:2]) read at a frame's end is the slot that frame went to.
   *camshot.* A bilinear demosaic of the whole frame (N: every Nth pixel), grey-world white balance with each gain kept
   within 1/4x and 4x of the green's (the room's warm light makes the raw red 2.8x the green), a saturation of 140 %
   about the luminance (the GPL setfile A is register writes only: no colour matrix there; `setfile_3h1.bin`, the
   ISP's tuning, is a vendor binary and not used), a gamma of about 1/2.2. 110-150 ms on the processor.
   *Stream* (`cam_s9=7`): 30.0-30.1 frames a second over five minutes, no FIFO error, none lost but the two a camshot
   takes; the thread polls the WDMA every millisecond (no interrupt wired yet). `/dev/hakios-camera` speaks the POCO's
   protocol (bsd/sys/hakios.camera.h): format 1 MIPI RAW10 (packed in read() from the WDMA's 16 bits a pixel), GRBG,
   black 64, the frame's number, time, exposure and gain; EXPOSURE taken while the reader keeps asking (the kernel's
   auto-exposure back two seconds after), SENSOR taken (one camera: the frames carry the number asked for, so the back
   and the front stream both get them), FOCUS ignored (no motor driven). camera_test reads it at 15 frames a second
   (its read and unpack take 50-60 ms; the kernel's 30 are there). mediaserverd's capture device lists a Back Camera
   and a Front Camera to AVFoundation, and Camera.app's preview runs from these frames (screenshot, run cn3-7).
   Not yet: the CSIS's frame-end interrupt, powering the camera only while the device is open, a colour tuning file
   for the 3H1 (`/redwood/fw/camera-<sensor>.isp`; the device loads the POCO's s5khm2sd tuning for "the Back Camera"
   now), a sensor number of its own for the S9's front camera in camera_device.c.
5. **The rear camera.** The same with the S2MPB03 (a new PMIC on hsi2c@14300000, its own read-only stage first),
   CSIS0 on four lanes, the AF motor (AK737x) for focus. OIS and the aperture left alone. Effort: 1-2 weeks.

The ISP's own pipeline (3AA/MCSC with the DDK and RTA libraries) is not on this plan: the CPU and the GPU do the
colour work, as on the POCO.

## Blobs

None are needed through stage 5: the sensor's tables are register lists in the BSP's headers (facts), not firmware.
Should the DDK ever be tried, `fimc_is_lib.bin`, `fimc_is_rta_2l3_3h1.bin` and the setfiles come from the owner's own
phone (`/vendor/firmware/`), never into this repository.

## First runs

| Run | Arguments | What to look for |
|---|---|---|
| C1 | `cam_s9=1` | "S2MPB02 ID 0x..", the four LDOs ("off, voltage code .."), "CIS_CLK1: mux .., divider .., gate ..", the pins |
| C2 | `cam_s9=2` | "VDDA_2.8V_VT (LDO13) on (0xd8)" and the other two, "THE SENSOR ANSWERS: model ID 0x...." then "powered down ... off as found" |
| C3 | `cam_s9=3` | "DPU status 0x..f", "the domain is on", "SMC 0x82000410 returned 0", "CSIS1: version 0x...", "the SysMMU: MMU_CTRL 0x0", then "the ISPPRE domain off again ... returned 0" and "status 0" |
| C4 | `cam_s9=4` | "the buffer: 4194304 bytes at 0x...", "CSIS1 set up", "THE FRAME ENDED", "N bytes changed, the last at L (L/1224 a line)", "THE PATTERN REACHED MEMORY" |
| C5 | `cam_s9=5` | after C4's lines: "read back: output 1632 x 1224, frame 1266 lines ...", "the sensor's frame count 0x.." (not 0xff), "frame end 1 ... 2", the CSIS's error bits 0, "THE PATCH ...: mean M" (64 or so with the lens covered, more in light), "A FRAME OF THE SENSOR'S IS IN MEMORY" |
| C6 | `cam_s9=6 usb_gadget=5` | after C5's lines, "6: CAMSHOT READY"; then on the host `tools/usb-shot.py --cam -o cam.png`: "usb: camshot: asked of the camera", the camera's lines ("THE SENSOR ANSWERS", "frame end 1 ... 2"), "camshot: RAW10 GRBG at a stride of 2040 (or 2048)", "usb: camshot: the front camera, 816x612 RGB", "usb: camshot 1 sent", and cam.png; `--tp` the same with the test pattern |
| C7 | `cam_s9=7 cam=5 usb_gadget=5` | "7: THE STREAM", "the ring: frame end 1, frame pointer 0 ... slot 0 by the fill", every ten seconds "the stream: frame N ..., 30.0 frames a second ..., 0 with the WDMA's FIFO error"; mediaserverd's "hakios: camera: the device made: two streams"; camera_avtest's two video devices; Camera.app's preview (tap its icon) and "hakios: camera: PrimaryScaler: the first picture given"; `tools/usb-shot.py --cam` takes the stream's newest frame |

If C1 says the S2MPB02 does not answer, the flashlight's `torch=1` has the same bus: try it. If C2 says the sensor does
not answer, run again with `cam_s9_ipclk=200` (the bus then runs at half speed if the clock is 400 MHz).
If C3 says the SMC returned anything but 0, the domain went off again and nothing in it was touched: stop there and
read the answer (0xffffffff... means Carbon or EL3 does not know the call). If C4 gives no frame end, the lines "the
others' INT_SRC" say whether the generator fed another CSIS's DMA. If C5 gives "frame end" but the patch reads 0 or
1023 everywhere, try `cam_s9_exp=` and `cam_s9_gain=`; if no frame end and the CSIS's SOT or CRC error bits are set,
the settle is the suspect. If C6's picture has the right shapes and the wrong colours, try `cam_s9_bayer=` 0, 2 or 3;
if it is sheared, `cam_s9_stride=` (the "bytes written" over 1224); a "camshot failed" line names the registers to read.

## The iris camera

`drivers/camera/hakios.exynos_iris.c` (`iris_s9=N`, CONFIG_HAKIOS_EXYNOS_IRIS; off unless asked). The sensor answers with `iris_s9_smc=1`; no frame has reached memory yet.
Its head has every register and number and where each comes from (the BSP's fimc-is-device-module-5f1.c,
leds-s2mpb02.c, the device tree; GPL, read for facts only).

| | The iris camera |
|---|---|
| Sensor | Samsung S5K5F1, infrared, 2400 x 2400 RAW8 at 30 fps, `fimc-is-secure@10`, position 3 |
| I2C | 0x10 on hsi2c@108D0000 (USI07_I2C of PERIC1, pins gpp4-6/7, function 3), 400 kHz |
| Reset, enable | gpg2-3; `gpio_iris_en` gpg0-7, high while powered |
| MCLK | CIS_CLK2 (CMU_TOP 0x1020/0x181C/0x2020/0x300C), 26 MHz from OSCCLK, out on gpc1-6 function 2 |
| Supplies | the S2MPS18 through ACPM: LDO39 VDDD 1.05 V, LDO40 VDDA 2.8 V, LDO41 VDDIO 1.8 V |
| MIPI | CSIS3 (0x16260000), two lanes at 2041 Mb/s (deskew on, settle 10), VC0's WDMA at 0x162E0000 in packet mode |
| IR LED | the S2MPB02's FLED2 in its infrared mode, strobed by the sensor once a frame |

The IR LED, and eye safety. The driver never lights the LED itself and never uses FLED2's torch mode. Before each
capture it sets the seven LED registers to the only values Samsung's GPL kernel holds (FLED_CTRL2 0x38, CUR2 0xAF,
IRON1 0x19, IRON2 0x0B, IRD1 0x00, IRD2 0x2E, and TIME2's IR max timer on) and reads each back; if one does not read
back, the sensor is not started. The per-shot current and pulse values of Samsung's iris HAL are not open and are not
used. The sensor streams only inside one capture: at most `iris_s9_ms` (600 ms unless said, at most 2 s), stopped on
every way out (a failed step, the run's end, a panic). Captures are at least 2 s apart, and a run makes at most 40.

The iris camera shares the S2MPB02's bus and the ISPPRE domain with the front camera and the flashlight, and the I2C
helper is one driver per bus: `iris_s9=N` runs only without `cam_s9=` and `torch=` (the S9's default `cam_s9=7` must be
taken out with `cam_s9=`). Running both is the next step: one owner of the S2MPB02 and of ISPPRE.

| Run | Arguments | What to look for |
|---|---|---|
| I1 | `cam_s9= iris_s9=1` | CIS_CLK2's registers, the pins, the three LDOs through ACPM ("VDDD_1.05V_IRIS (LDO39): 0x.."), "S2MPB02 ID ..; FLED CTRL1 .. CTRL2 .. CUR2 .. TIME2 .. IRON1 .. IRON2 .. IRD1 .. IRD2 .." |
| I2 | `cam_s9= iris_s9=2` | the LDOs "on (0xec)", "(0xe8)", "(0xdc)"; "the sensor: model ID 5f1., version 0xa1"; the OTP's "test 1 1 1"; "powered down ... off as found" |
| I3 | `cam_s9= iris_s9=3` | after I2's, the FLED registers again: CTRL2 0x38, CUR2 0xaf, TIME2 bit 0, IRON1 0x19, IRON2 0xb, IRD1 0, IRD2 0x2e |
| I4 | `cam_s9= iris_s9=4` | "read back: output 2400 x 2400, frame 5079 lines of 2616 clocks"; "CSIS3 version 0x..."; "STREAM ON"; "streamed N ms; a whole frame"; "the frame: about 5760000 of 5760000 bytes changed"; the middle patch's mean (an eye or a hand at 25-35 cm: well above black) |
| I5 | `cam_s9= iris_s9=5 usb_gadget=5` | after I4's, "5: ready for the USB console's irshot"; on the host `tools/usb-shot.py --iris -o iris.png`: a grey 1200 x 1200 infrared picture |

What the phone has shown (3 November, phone 1, one kernel, Wi-Fi's arguments taken out for the line's length):

| Run | Arguments | Seen |
|---|---|---|
| control | `cam_s9= iris_s9=2` | the LDOs on as expected; "the sensor does not answer at 0x10" |
| PREPARE | `cam_s9= iris_s9=2 iris_s9_smc=1` | PREPARE returns 0; model ID 0x5061 (not the "5f1." the table above expected), version 0xa1, OTP test 1 1 1; UNPREPARE returns 0 |
| frame | `cam_s9= iris_s9=4 iris_s9_smc=1` | "streamed 164 ms; a whole frame", CSIS3 FRM_CNT 6, ERR_CODE 0, and 0 of 5760000 bytes changed: the buffer still holds its 0xA5 |
| bright | `iris_s9=5 iris_s9_smc=1 iris_s9_exp=2000 iris_s9_gain=0x100` | CSIS3 FRM_CNT 23, "NO FRAME END seen", 0 bytes changed, so no irshot |

So PREPARE is what lets the sensor answer, and the secure world is reached through Carbon. The pins' registers read the
same before and after it, so their read-back is no test of anything. Why nothing lands in memory is not known: the
secure path taking the frame is the first guess, unproved. Not run: `iris_s9_smc=2` and `3`. Next: PREPARE, power up,
UNPREPARE, then stream, to see whether the sensor stays up and the path is left in the normal world. No run has shown a
picture, and whether the IR LED pulsed was not observed.

The fingerprint's bus (`fp_s9=N`, the same file). Reading SPI1 (spi@10450000) is a synchronous external abort with its
clock gates open, and so is the mode word at SYSREG_PERIC0; the kernel panics and the phone returns to TWRP. So they
are not the normal world's. The sensor itself was never reached.

If I2 says the sensor does not answer, the LDOs' read-back and `look_pins` say which part of the power-up is missing.
If I4 has no frame end, the CSIS's INT_SRC0 says whether the link saw start-of-transmission (SOT) or CRC errors (the
settle, the deskew) or nothing at all (the lanes, the D-PHY's reset bit 3); `iris_s9_ispdiv=1` halves the bus clock.

### Towards Face ID

iOS 16.5's Face ID (the image is an iPhone X's) runs `biometrickitd` with `/usr/lib/libBKDM2.dylib`, which drives
`ApplePearlSEPDriver` (the Secure Enclave's biometric service) and `AppleH10CamIn`'s Pearl streams (the dot projector, the
flood illuminator and the IR camera, read by the SEP). This port has no SEP: its keystore stand-in
(`MiniAppleKeyStore.cpp`) answers "no passcode, unlocked" and has no passcode at all. The plan, in order:
1. this driver: an infrared frame of an eye, and a stream to user space (`/dev/hakios-iris`, not written yet);
2. a passcode in the keystore stand-in (set, change, lock, unlock against a salted verifier kept in /private/var), and
   the credential coreauthd asks for when Face ID is enrolled;
3. a process of our own serving `com.apple.pearld` (BiometricKit's XPC protocol: enrol, match, identities, state) with
   an on-device iris matcher (open-iris, MIT; its segmentation model MIT/Apache-2.0), and a keystore call that unlocks
   on a match.
What stays fake: with no SEP there is no hardware key, so the passcode and Face ID gate the screen, not the data; any
root process could unlock; the templates are a root-only file; there is no anti-spoofing beyond the IR picture itself.

## Stock iOS's camera, and how ours is presented to it

Research from public sources (Apple's open-source XNU and IOKit headers, The Apple Wiki, Asahi Linux's documentation
and apple-isp driver for the M1's ISP, the class and symbol names visible in iOS 16.5's shared cache), plus what this
port's own runs show.

**What iOS 16.5 runs.** The capture stack is CoreMedia's CMCapture (FigCapture): a server inside mediaserverd on iOS
16 (cameracaptured, a daemon of its own, arrives with iOS 17), which AVFoundation's AVCaptureSession and Camera.app
reach over XPC (FigCaptureSourceRemote, FigCaptureSessionRemote). In the server, BWFigCaptureDeviceVendor asks a
platform plug-in for its capture device: on the iPhone X it is H10ISP.mediacapture
(/System/Library/MediaCapture/), which makes a FigCaptureDevice with one FigCaptureStream per camera, each a
CoreMedia "derived object" (a property table plus Start/Stop/AddAttachmentsToSampleBuffer). Under the plug-in is the
kernel: AppleH10CamIn (the ISP's driver, an IOService on /arm-io/isp) and its user client, opened with
IOServiceOpen; the ISP is an RTKit coprocessor running Apple's camera firmware, which the kernel loads and talks to
through mailboxes and shared-memory command queues (Asahi's apple-isp documents the same family on the M1: firmware
commands to power the sensor, set a channel's format, start a stream, hand over buffer pools). Frames come back as
IOSurfaces from pools the plug-in registers, with per-frame metadata (exposure, gains, AF, face detection, the 3A's
statistics) the firmware writes, and notifications on an IODataQueue/mach port. MobileGestalt reads
IODeviceTree:/arm-io/isp and the camera nodes to decide that there is a camera at all (SpringBoard shows Camera.app by
it); CoreMedia's colour conversions look for AppleM2ScalerCSCDriver (the M2 scaler) and fall back to software when it
is missing ("IOServiceMatchingfailed for: AppleM2ScalerCSCDriver" in every run: harmless).

**What Camera.app asked for, on this phone (run cn3-7).** Through libhakios.media's device: the vendor's device, one
stream at a time (the back one first: SENSOR 1, then the front), MultipleOutputSupportEnabled, the outputs
PrimaryScaler and StillImage (IntermediateTap, Raw, StillImageIntermediateTap, StillImageQuadra, StillImageRaw, Depth,
PointCloud asked for and not there), format 0, Minimum/MaximumFrameRate 15/30, AEMaxGain 24576, ColorSpace 0,
RegionOfInterestForCameraControls, Chroma/TemporalNoiseReduction, FaceDetection and HighCurrentTorch; the first
picture given to PrimaryScaler at 1504x1128 420f, AddAttachmentsToSampleBuffer for the metadata. No IOKit camera
service was opened: H10ISP.mediacapture is never asked, the vendor is ours.

**Two ways to present our camera.**
1. *A kernel-side AppleH10CamIn*: an IOService on /arm-io/isp with Apple's user client, so H10ISP.mediacapture runs
   unchanged. It means emulating the ISP firmware's command protocol (well over a hundred commands, private and
   per-firmware-version), its buffer-pool and metadata formats, the 3A the firmware runs (exposure, white balance,
   focus statistics in Apple's layout), the sensor calibration it reads from the camera module's NVM, and the
   checks H10ISP makes of the hardware (sensor IDs, the module's serials). Nothing of it is documented; Asahi's work
   covers the M1's firmware interface partly, not the A11's, and not the user client above it. Effort: 4-8 months
   of reverse engineering for one camera, fragile against every iOS update. Not recommended.
2. *A user-space capture device* (what this port does, plug-and-play from the kernel's side): the kernel gives raw
   frames on /dev/hakios-camera; libhakios.media, already loaded into mediaserverd for the POCO, replaces the
   vendor's device with its own (camera_device.c: the same derived-object tables, the iPhone X's format names from
   CMCapture's AVCaptureSession.plist so presets resolve) and makes pixel buffers on the CPU (camera_isp.c). Nothing
   of iOS's own binaries changes on disk; the hook is the vendor's create function. On the S9 the kernel side was the
   only missing part, and with it Camera.app's preview runs. Remaining effort: 1-2 weeks: a tuning file for the 3H1
   (a colour matrix measured against a chart, lens shading), the S9's own sensor number in camera_device.c (front
   only, no back camera until stage 5), the stills at full size, the preview's frame rate (the read-and-unpack path
   is 50-60 ms a frame: an mmap of the ring or NV12 made in the kernel would halve it), power only while open.
