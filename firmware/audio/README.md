# The Galaxy S9's audio firmware (prebuilt, Samsung's)

Samsung's own binaries, kept here by the project's choice so that an image can be built without the phone at hand.
`userland/build.sh` with `DEVICE=starlte` puts every file of `firmware/` into `fw/` of the root image, where the kernel's
drivers find them (`hakios_image_file("fw", name)`).

Taken unchanged from ExyHyperBrick's LineageOS vendor trees, branch `lineage-24.0`, `proprietary/vendor/firmware/`
(the phone's `/vendor/firmware`): `proprietary_vendor_samsung_starlte` and, for `dsm.bin` and the codec's
`cs47l92-dsp1-trace.wmfw`, `proprietary_vendor_samsung_exynos9810-common`. A phone's own copies can be checked against
the sums below (`adb shell sha256sum /vendor/firmware/<name>`).

| file | what it is (the S9 kernel's names) | sha256 |
|---|---|---|
| `calliope_sram.bin` | ABOX's CPU, its SRAM image (32-bit ARM; abox.c, the "calliope" firmware) | `15e443768304746d65df5b337932e169ab6d72a83ac40e823dd29764f5381cf2` |
| `calliope_dram.bin` | ABOX's CPU, its DRAM image (at IOVA 0x80000000 through ABOX's SysMMU) | `6fb029b854badc9d661b0cb6c633fb4575f3bb307ca35a03488fd21fcad2e6dd` |
| `calliope_iva.bin` | ABOX's CPU, its IVA image | `2455175a0f90f19b507b16ee4865b878a47ca88adfef28540f28130a502f9b6f` |
| `dsm.bin` | Maxim's DSM, speaker protection for the MAX98512s, run on ABOX (device tree: ABOX ext firmware) | `b8f136e6503a2aa83537180945070368e8f8bc0a321868ded91eaaa1c461587c` |
| `dsm_tune.bin` | DSM's tuning for the S9's speakers (ext firmware) | `00b1303efa33218f25669494b120806bb1c8a801cbc191ab2e8447f12ab3760c` |
| `AP_AUDIO_SLSI.bin` | ABOX ext firmware named in the S9's device tree (Samsung's audio solutions) | `a97d70d6acb16fafd3cde660875780307ba272fc72063de988b65375b4617246` |
| `APBargeIn_AUDIO_SLSI.bin` | ABOX ext firmware named in the S9's device tree (Samsung's audio solutions) | `473497d57873e2565859e1c3052f5065be1f902e319a7e6454174d8a5deab93c` |
| `APDV_AUDIO_SLSI.bin` | ABOX ext firmware named in the S9's device tree (Samsung's audio solutions) | `26ea8d338cf8f71f6708f218a9707a7a4ec353c81b57290e2a4e55f9c942d1a1` |
| `APBiBF_AUDIO_SLSI.bin` | ABOX ext firmware named in the S9's device tree (Samsung's audio solutions) | `a2fdac1aaaa2f6aafc99a99fd1410ada8ee9156564589c5d640e9fa528ddc9a8` |
| `SoundBoosterParam.bin` | ABOX ext firmware named in the S9's device tree (Samsung's audio solutions) | `e2a0aae2c8849b9e97293d211c0d18dba6b26582bf09cbe21984831f7ea92384` |
| `cs47l92-dsp1-trace.wmfw` | the CS47L93 codec's DSP1 (madera); not needed for playback | `a2a45b4c255e6f71d7187e001a6439797537377c6d75222ebb9040a2c651fad0` |
