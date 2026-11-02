# The Galaxy S9's Bluetooth patch (prebuilt, Broadcom's)

NOTICE. Broadcom's RAM patches for the Bluetooth half of the Galaxy S9's BCM4361 module, one per module maker, as
Samsung ships them. Kept here, unchanged, by the owner's decision (2 Nov 2026) so that an image can be built without the
phone at hand. They belong to their owners and are not licensed by this repository (LICENSE, item 5); their terms are
still to verify.

Source: the LineageOS 24 vendor image for starlte, `/vendor/firmware/` (the same files, by SHA-1, as
`proprietary-files.txt` of LineageOS's `device_samsung_exynos9810-common` lists, and as the user's own phone's VENDOR
partition has).

`userland/build.sh` with `DEVICE=starlte` puts them into `fw/` of the root image, where
`drivers/bluetooth/hakios.bcm4361_bt.c` finds them at `bt=6`; without them there it reads the same file from the phone's
own VENDOR partition at run time (`ufs=2`). Which of the two is the phone's: `bt_module=`, else what Wi-Fi read from the
chip's OTP in the same run (BLUETOOTH.md).

| file | what it is | sha256 |
|---|---|---|
| `bcm4361B2_murata.hcd` | Murata's module: "BCM4361B2 Crown 1QW ANT1 [Version: 0110.0230]" | `5cb874624c8697e16e21b097ffbdf0c8e34ef3a57a5b220d617622e9b4c7eb96` |
| `bcm4361B2_semco.hcd` | SEMCO's module: "BCM4361B2 Crown E32A ANT1 [Version: 0110.0232]" | `11f8161603ad77228b3f6f7c85427d09bc0f0c19518687181e8717590bf426ea` |
