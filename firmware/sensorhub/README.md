# The Galaxy S9's sensor-hub firmware (prebuilt, Broadcom's)

NOTICE. The RAM image of the sensor hub inside the S9's Broadcom BCM4775 B0 GNSS chip, which the chip's ROM takes over
SPI at every power-up and then runs: Samsung's sensor-hub application ("bcm_sensorhub_a1"). Kept here, unchanged in its
bytes, so that an image can be built without the phone at hand, as the Wi-Fi and Bluetooth firmware beside it are. It
belongs to its owners and is not licensed by this repository (LICENSE, item 5); its terms are still to verify.

Source: Samsung's GPL kernel for the S9 (Scion-Project/android_kernel_samsung_exynos9810 at e5906667068e),
`drivers/sensorhub/brcm/bbdpl/q_os/bbd_patch_file_star.h`, which the kernel builds in for CONFIG_SENSORS_SSP_STAR and
serves to Android's daemon lhd as `/dev/bbd_patch` (bbd.c). That file is text: header lines and the image as hex in
`<Blob=...>`. Here it is the hex turned back into its bytes, nothing else; its header said:

| key | value |
|---|---|
| FormatVersion | 0x00010003 |
| Crc | 18 (lhd's own check of the text; the chip does not see it) |
| BlobLength | 413864 |
| AsicVersion | 0x004775B0 (the BCM4775 B0) |
| Name, Type | bcm_sensorhub_a1, Application |
| PatchAddress | 0x00800161 (where the chip is told to start it: a Thumb entry, the image's reset vector) |

The image is records `[type u8][length u16 LE][body]`: here 452 writes (type 0xF1, `[u32 address][data]`), 410700 bytes
of a Cortex-M image contiguous from 0x00800000 to 0x0086444c. `drivers/input/hakios.ssp.c` sends each as RPC 0x05 and
then starts it (SENSORS.md); `tools/bcm_shub_test.c` of the kernel reads it through.

`userland/build.sh` with `DEVICE=starlte` puts it into `fw/` of the root image, where the driver finds it at `shub=4`.

| file | sha256 |
|---|---|
| `bcm_sensorhub_a1.bin` | `b1a3e138ab808f2be247ad195d71d6aef2f2d3ecc7bd3e13e141b1443da408d0` |
