# The Galaxy S9's cameras: what it takes, and the plan

State: stages 1 to 3 written (`drivers/camera/hakios.exynos_camera.c`, `cam_s9=1` to `5`), none yet run on the phone.
Stages 4 and 5 are a plan. Everything below comes from Samsung's BSP (android_kernel_samsung_exynos9810, lineage-24.0, e5906667; the
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
   (two lanes, CSI_MODE_VC_DT, VC0 RAW10 1632 x 1224, CH2 the embedded data), a 4 MB buffer below 4 GB given to all
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
4. **/dev/hakios-camera.** `cam_s9=6` (the kernel's interface as `hakios.camera.c` gives it: open powers up, read
   gives `struct hakios_camera_frame` with format 1 RAW10, `bayer`, `black` (64 in 10 bits, the usual for Samsung's sensors: to be measured), exposure
   lines, line length, gain registers; write takes EXPOSURE, SENSOR, FOCUS). Frames by the CSIS's frame-end interrupt
   and a ring of buffers (the WDMA has 8 frame pointers). `sensor` numbering follows the header: 2 the front, 1 the
   wide. User space needs no change: mediaserverd takes the camera when `/dev/hakios-camera` exists (inject_media.c);
   its colour tuning is looked for at `/redwood/fw/camera-<sensor>.isp` (camera_device.c) and is optional. Risk: low once 3 works. Effort: 1 week.
   To check on the phone: whether the WDMA's RAW10 "normal" (not PACK12) layout is MIPI's (four pixels in five
   bytes); if not, the header gets a second format and camera_isp.c a second unpacker. Step 4's log answers it: the
   bytes written per line (2040 or 2048 for MIPI's layout, 2448 or more for PACK12), and `cam_s9_pack12=1` tries the
   other one.
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

If C1 says the S2MPB02 does not answer, the flashlight's `torch=1` has the same bus: try it. If C2 says the sensor does
not answer, run again with `cam_s9_ipclk=200` (the bus then runs at half speed if the clock is 400 MHz).
If C3 says the SMC returned anything but 0, the domain went off again and nothing in it was touched: stop there and
read the answer (0xffffffff... means Carbon or EL3 does not know the call). If C4 gives no frame end, the lines "the
others' INT_SRC" say whether the generator fed another CSIS's DMA. If C5 gives "frame end" but the patch reads 0 or
1023 everywhere, try `cam_s9_exp=` and `cam_s9_gain=`; if no frame end and the CSIS's SOT or CRC error bits are set,
the settle is the suspect.
