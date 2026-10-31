# The GPU on the Galaxy S9: OpenGL ES and Metal

The S9's GPU is a Mali-G72 MP18 (Bifrost, architecture 6, GPU_ID 0x6221). The kernel repository brings it up in nine
steps (`drivers/gpu/hakios.mali.c`, `mali=1` to `mali=9`; [README.md](README.md#the-gpu)) and at the ninth starts
HakiosMali (`drivers/gpu/hakios.mali.cpp`), the IOKit service programs draw through. This file is the rest of the way:
what draws on the Mali, how it reaches the kernel, what was checked without the phone, and the runs that bring it up.
Nothing here has run on the phone.

## How a program reaches the Mali

```
 CoreAnimation (OpenGL ES)          a Metal program (metal_drv_test; later CoreImage, RenderBox)
   |  userland/src/eagl.c             |  userland/src/hakiosmetal_air.m (libhakiosmetal.dylib)
   v                                  v
 libOSMesa.8.dylib                  libhakiosair.dylib       (tools/mesa/air: Apple's AIR -> NIR)
   |  Mesa 25.0.7's panfrost (Gallium), Bifrost compiler; tools/mesa/panfrost-darwin.patch
   v
 tools/mesa/hakios-drm: libdrm's calls as IOKit calls (drmOpenWithType("panfrost") opens HakiosMali)
   v
 HakiosMali (hakios.mali.cpp): Linux panfrost's interface, version 1.2
   v
 hakios.mali.c: address space 0, its page tables, a queue of job chains, slots 0 and 1
```

The interface is Linux panfrost's DRM interface, not kbase's: Mesa's panfrost speaks it, and every request is an
`IOConnectCallStructMethod` with the request's number (the low byte of the ioctl) as the selector and the same structure
in and out. Checked side by side, `tools/mesa/hakios-drm/hakios.drm.c` against `hakios.mali.cpp` and Mesa 25.0.7's
`src/panfrost/lib/kmod/panfrost_kmod.c`, `src/gallium/drivers/panfrost/pan_jm.c`, `pan_bo.c`, `pan_fence.c` and
`include/drm-uapi/panfrost_drm.h`:

| Request | Mesa sends | HakiosMali | Agrees |
|---|---|---|---|
| 0x44 GET_PARAM | 16 bytes; as required, params 0, 1, 2 (product, revision, shader cores), 10-12 (tiler, memory, MMU features), 13-15 (thread features, max threads, workgroup size), 18-21 (texture features), 39 (TLS alloc), 40 (AFBC) | every one, from the registers Linux reads (0-37 and 38 too); 39 never below MAX_THREADS; 40 answered 0, so no AFBC | yes. 41-42 (timestamps) are asked only of 1.3, and the service says 1.2 |
| 0x42 CREATE_BO | 24 bytes: size, flags (NOEXEC unless code; HEAP for the tiler heap, 128 MB), back handle and offset | wired, zeroed, write-combined memory, every 4 KB page in the GPU's tables, the address back; the size is not changed (Mesa keeps what it asked) | yes, with flags now used: code is kept off 16 MB lines. HEAP is made whole (128 MB wired), not grown on faults |
| 0x43 MMAP_BO | 16 bytes, back an offset | handle << 12; the shim maps client memory of type handle instead of mmap() | yes (pan_kmod.h's patch maps the whole buffer, the only mapping panfrost asks for) |
| 0x45 GET_BO_OFFSET | 16 bytes, for an imported buffer | the buffer's GPU address | yes |
| 0x7e (ours) | an IOSurface's ID where Linux has a dmabuf descriptor (drmPrimeFDToHandle) | the surface's pages from the page after its header, as a buffer | yes, both 40 bytes, same field order |
| 0x40 SUBMIT | 40 bytes: jc, in_syncs, counts, out_sync, bo_handles, requirements (FS for fragment) | queued; job number back in jc; the shim puts the chain back and the number in out_sync's sync object | yes; fragment to slot 0, the rest to slot 1, one at a time in order |
| 0x41 WAIT_BO | 16 bytes, an absolute deadline | waits for the last job naming the buffer, for a length of time (the shim converts) | yes; failure is ETIMEDOUT, as panfrost_kmod_bo_wait asserts |
| 0x48 MADVISE | 12 bytes | retained = 1 (nothing is ever purged) | yes |
| 0x09 GEM_CLOSE | 8 bytes | waits for its last job, then out of the tables, address space 0 updated | yes |
| sync objects | drmSyncobjCreate/Wait/Reset/Export/ImportSyncFile | none in the kernel: the shim keeps a job number per sync object, jobs end in order | yes for the JM paths pan_jm.c and pan_fence.c use; FDToHandle and timelines are refused (panvk and CSF only) |

**GPU addresses.** Mesa's panfrost assumes Linux's range, 32 MB to 4 GB (`panfrost_kmod.c`: "the address space is
limited to 32-bit") and leans on it: on Bifrost a blend shader's address is given in 32 bits, the upper half taken from
the fragment shader's (`pan_cmdstream.c`), and workgroup storage must not cross 4 GB (`pan_desc.c`). Code must not cross
a 16 MB line (Linux `panfrost_gem.c`; Mesa's `midgard_compile.c` counts on it). The driver taken from the Infinix Hot
20 gave out 32 GB of addresses, never one twice, starting at 16 MB, and ignored the flags: the first buffers past 4 GB
(after 4 GB of buffers made in one boot) would have sent blend shaders to the wrong address. It now gives
addresses between 32 MB and 4 GB, takes them back when a buffer is freed (after the MMU has been updated), and keeps
code off 16 MB lines (`drivers/gpu/hakios.mali_va.h`, checked by `tools/mali-va-test.sh`: 100 000 buffers and 440 GB of
allocations in a session with Mesa's 128 MB tiler heap held throughout, nothing refused, nothing past 4 GB, no code
across 16 MB, no overlap).

**Page tables.** AArch64 stage-1 tables with 4 KB pages; on the G72, whose MMU has 48 bits, four levels from level 0
with INA_BITS = 55 - 48, as both kbase and panfrost walk it (PR 113). Every address given is below 4 GB, so level 0
has one entry and level 1 four; the tables are untouched by this change.

**Coherency.** None (COHERENCY_ENABLE = 31): buffers are write-combined, IOSurfaces' cache lines are cleaned before a
job that names them and invalidated after it is waited for.

## Metal: which route

Three were looked at, from the source:

1. **metal2vulkan over Mesa's panvk** (the tree's `METAL=vk`, `tools/metal/mk-metal2vulkan.sh`). The runtime's floor
   is a Vulkan 1.2 device with timeline semaphores. Mesa 25.0.7, the pinned Mesa, builds panvk for v6 but refuses a
   v6 GPU unless `PAN_I_WANT_A_BROKEN_VULKAN_DRIVER` is set ("panvk is not well-tested on v6") and then says Vulkan 1.0
   for anything below v10 (`panvk_physical_device.c`). Mesa's main branch (31 October 2026) says 1.3 for v6 and v7, with
   timeline semaphores, still behind the same variable. So **panvk does not meet the floor at the pin**; it would need a
   newer Mesa built separately, and panvk itself on iOS needs from the shim what freedreno and panfrost never asked:
   device enumeration (drmGetDevices2), drmSyncobjSignal, sync objects as file descriptors. Not this route, not now.
2. **hakios-metal** (Scion-Project/hakios-metal): Metal's command model on the Adreno as PM4 packets (copies and fills
   by the command processor), with no shaders. On the Mali every packet would be rewritten as job descriptors, and the
   result would still run no shader. Not this route.
3. **Metal through Mesa's Gallium** (`userland/src/hakiosmetal_air.m` with `libhakiosair.dylib`, `tools/mesa/air`): the
   Metal object graph over Gallium, Apple's shaders through the AIR frontend into NIR. Only the opening of the GPU was
   the Adreno's; the rest is Gallium and NIR, and panfrost takes NIR and has compute and render on Bifrost (it is the
   OpenGL ES 3.1 driver the window server uses). **This is the route**: it shares everything below the AIR frontend
   with the OpenGL ES path that is brought up first, and it is the only one that runs shaders.

What was done for it: `libhakiosair` opens HakiosMali through panfrost when there is no HakiosGPU
(`tools/mesa/air/air_metal.c`), and is built after every Gallium driver (`tools/mesa/air-metal.patch`, now
`src/gallium/targets/hakiosair`) so that it carries panfrost as well as freedreno. The driver names the Mali when it is
one (`hakiosmetal_air.m`). What is not known: how much of Apple's shader corpus panfrost's Bifrost compiler takes (the
Adreno's ir3 needed `tools/mesa/air-ir3.patch` and three ir3 fixes), and whether compute on a G72 through this path gives
the numbers metal_drv_test expects.

## The runs

Each run is one flash (`devices/starlte/mkimage.sh -s SECS cpus=2 bootcpu=2 ...`); the log is read in TWRP afterwards
([README.md](README.md#on-the-phone)). Before them, the README's run 16 (`mali=1` to `mali=9`, one step a run); these are its runs 23 to 25.

| Run | Image and arguments | Look for | If not |
|---|---|---|---|
| G1 | `GL=1 NO_AIR=1 REST=1 ALONE=1` (rc.jobs, the default, runs mali_test); `-s 180 cpus=2 bootcpu=2 mali=9 gl=0` | "mali: 9: HakiosMali started", "HakiosMali: the GPU is there for programs to draw with", "mali_test: 1: HakiosMali open", the parameters (GPU_PROD_ID = 0x6221), "mali_test: 3: buffer 1, ... (between 32 MB and 4 GB, as panfrost expects)", "mali_test: 4: job N: wait 0, WAIT_BO 0 ... the word 0xc0ffee01 -- THE GPU WROTE IT", "mali_test: 5: buffer given back: 0" | "would not open": the service is not there (kern.hakios.mali below 9). "not written" with "a job on slot 1 did not finish": the fault and its buffer follow in the log; again with `mali_fastmap=0` (the walk through the GPU's caches, every buffer an UPDATE) |
| G2 | the same image; `-s 180 cpus=2 bootcpu=2 mali=9` (CoreAnimation takes OpenGL ES through panfrost by itself when HakiosMali is there) | "HakiosMali: a client opened the GPU" (backboardd), its first requests "request 0x44, 16 bytes", 0x42, 0x45, 0x7e, 0x40; every minute "mali: step 9 of 9; ... 1 clients, N buffers, M job chains (0 failed), ...; K MB of the GPU's 4 GB of addresses in use", with M growing; the lock screen on the panel | `gl=0` gives back the software renderer (the screen as before). Job failures: the fault lines name the buffer ("an IOSurface WxH" or "a panfrost BO"); `mali_flush=0` only to measure. A hang: `mali_mhz` stays at 260 |
| G3 | `GL=1 NO_AIR=1 REST=1 ALONE=1 RC_JOBS=rc.jobs.gltest`; `-s 180 cpus=2 bootcpu=2 mali=9` | "mali: gl_test drew on THE MALI; NN% of the picture inside the triangle (26% by geometry)" | "drew on the processor": Mesa fell back to softpipe (HakiosMali not opened, or OSMESA_SOFTWARE set) |
| M1 | `GL=1 REST=1 ALONE=1 RC_JOBS=rc.jobs.malimetal` (with the AIR library: no NO_AIR); `-s 240 cpus=2 bootcpu=2 mali=9` | mali_test as G1; "hakiosmetal[metal_drv_test N]: the compiler library Mali-G72 ..."; "drvtest: compute image_calcminmax0 compiled: ..."; "drvtest: dispatched image_calcminmax0: status 4" (completed); then "drvtest: draw: the pixel at (0, 0) of attachment 2 is" the same four numbers as "softpipe computed" | "no GPU here": HakiosMali was not opened by the library (G1 first). "compiled" missing with a reason: the Bifrost compiler refused the shader, which is the next work (as air-ir3.patch was for ir3). A dispatch that does not complete: the kernel's fault lines, as G1 |

If the image with the AIR library does not fit the 64 MB the loader takes, the same root goes on UFS
([README.md](README.md#storage-ios-from-the-phones-flash): `ufs=2 root_apfs=ufs_NAME`).

## What is checked, and how

- The kernel builds with the driver in (`make starlte_defconfig && make kernel`) and without it.
- `tools/mali-va-test.sh`: the address allocator, under the address and undefined-behaviour sanitizers.
- Mesa 25.0.7 cross-built for iOS with `DRIVERS=softpipe,freedreno,panfrost` and `AIR=1` by `tools/mk-mesa.sh`: every
  patch applies, libOSMesa and libhakiosair link with panfrost in them.
- The interface table above, by reading both sides.

Not checked: anything on the GPU. The S9+ mainline port has run Linux panfrost on the same SoC from S-Boot's state;
this driver's own code has run only on the Infinix Hot 20's G52, with the address scheme replaced here.
