# The Galaxy S9's cameras: what it takes, and the plan

State: stage 1 written (`drivers/camera/hakios.exynos_camera.c`, `cam_s9=N`), not yet run on the phone. Stages 2-5
are a plan. Everything below comes from Samsung's BSP (android_kernel_samsung_exynos9810, lineage-24.0, e5906667; the
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
| (a second block per CSIS, 64 KB) | 0x16160000 (CSIS0), 0x16180000 (CSIS1): to be identified in fimc-is-device-csi_v4.c's probe |
| D-PHY control (reset bits 0-3) | 0x16210500; PMU isolation 0x1406070C (CSIS0), 0x14060730 (CSIS1 and 3), 0x14060710 (CSIS2) |
| Power domain ISPPRE | PMU 0x14064048 (its on/off needs an SMC, `need_smc` 0x16210004) |
| SysMMU in front of 3AA/PDP/CSIS DMA | 0x16310000 (`sysmmu@16310000`, secure base 0x162F0000) |
| CSIS gates | GATE_IS_ISPPRE_CSIS0-3 (CMU_ISPPRE), MUX_CIS_CLK0-3 |
| Interrupts | CSIS0 SPI 328, CSIS1 329; their DMA 334/335 |

## The stages (cam_s9=N, each logged before it is taken)

1. **Written.** `cam_s9=1` looks: the pins, CIS_CLK1, the two buses, the S2MPB02's ID and its four camera LDOs.
   `cam_s9=2`: the front sensor powered up in Android's order, its model ID (0x0000), revision (0x0002), frame count
   and mode read over I2C, powered down. Risk: low (three LDOs to Android's voltages, read back, switched off again;
   one pin each for reset and MCLK; one CMU gate). Effort: done, a run or two to see it.
2. **The ISPPRE domain and CSIS1 seen.** `cam_s9=3`: power domain ISPPRE on (through the PMU and the SMC the BSP's
   exynos-pd makes), CMU_ISPPRE's CSIS1 gates, CSIS1's version register and its DMA common read. Then the DMA's own
   test pattern into a buffer below 4 GB (the WDMA takes 32-bit addresses; the SysMMU left off, so the address is
   physical, or the SysMMU given a flat table if it is found on), the buffer handed to the loader like the POCO's.
   Risk: medium (the SMC; a DMA into the wrong place: the buffer is ours and its address checked before it is written;
   the SysMMU's state is the unknown). Effort: 3-5 days.
3. **The sensor's frames.** `cam_s9=4`: the D-PHY (isolation released in the PMU, reset in 0x16210500, settle and lane
   setup from csi_hw_s_phy_config/csi_hw_s_lane), CSIS1 on two lanes at 719 Mbps, the sensor's mode table for
   1632x1224 (from fimc-is-cis-3h1-setB.h's sensor init and mode tables: register/value lists, data, written as
   given), streaming on (0x0100 = 1), one RAW10 frame by VC0's WDMA, the sensor back to standby. Risk: medium (the
   PHY's settle for the 10 nm process, fimc-is-hw-settle-10nm-lpe.h; the tables are long). Effort: 1-2 weeks.
4. **/dev/hakios-camera.** `cam_s9=5` (the kernel's interface as `hakios.camera.c` gives it: open powers up, read
   gives `struct hakios_camera_frame` with format 1 RAW10, `bayer`, `black` (64 in 10 bits, the usual for Samsung's sensors: to be measured), exposure
   lines, line length, gain registers; write takes EXPOSURE, SENSOR, FOCUS). Frames by the CSIS's frame-end interrupt
   and a ring of buffers (the WDMA has 8 frame pointers). `sensor` numbering follows the header: 2 the front, 1 the
   wide. User space needs no change: mediaserverd takes the camera when `/dev/hakios-camera` exists (inject_media.c);
   its colour tuning is looked for at `/redwood/fw/camera-<sensor>.isp` (camera_device.c) and is optional. Risk: low once 3 works. Effort: 1 week.
   To check on the phone: whether the WDMA's RAW10 "normal" (not PACK12) layout is MIPI's (four pixels in five
   bytes); if not, the header gets a second format and camera_isp.c a second unpacker.
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

If C1 says the S2MPB02 does not answer, the flashlight's `torch=1` has the same bus: try it. If C2 says the sensor does
not answer, run again with `cam_s9_ipclk=200` (the bus then runs at half speed if the clock is 400 MHz).
