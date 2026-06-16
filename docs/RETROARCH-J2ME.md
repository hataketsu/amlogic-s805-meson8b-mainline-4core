# Retro gaming: RetroArch + J2ME on S805, HW-accelerated on Mali-450

_EN; bản tiếng Việt: [RETROARCH-J2ME.vi.md](RETROARCH-J2ME.vi.md)._

Goal: play retro games (specifically a large **J2ME `.jar`** phone-game library) on the box, rendered
on the **Mali-450 GPU** (not software). This documents how HW render was unlocked on meson8b (M8B), the
J2ME core, the kiosk setup, and the dead-ends.

## TL;DR
- **HW render works** via **RetroArch on the KMS video context + lima** (NOT under X11). Confirmed:
  `[GL]: Vendor: lima, Renderer: Mali450`.
- It required a **kernel patch** adding `XRGB8888` to the meson8b OSD plane formats
  (`patches/meson8b-osd-xrgb8888.patch`) — otherwise RetroArch's KMS `drmModeAddFB` fails
  ("Failed to create FB").
- The same patch **also enables glamor on lima under X** (`glamor X acceleration enabled on Mali450`),
  but the X **desktop** is not worth it on this SoC (cursor/compositor quirks — see Dead-ends).
- **freej2me** libretro core was **cross-compiled for armhf** (it isn't on the libretro buildbot).

## Why software was slow (the problem)
Under X11 on meson8b, GLX/EGL falls back to **llvmpipe** (software) — the meson display has no working
GL accel by default. RetroArch's render thread then pegs one Cortex-A5 core (~100%) + Xorg + 4 llvmpipe
threads ≈ **1.85 cores burned on display alone**, on top of the J2ME emulation. Result: lag.

## The HW-render unlock (kernel patch)
Root cause of the KMS crash: `drivers/gpu/drm/meson/meson_plane.c` `supported_drm_formats_m8[]` omits
`XRGB8888`. S805 = `VPU_COMPATIBLE_M8B` uses that list. RetroArch's KMS/GBM surface is XRGB8888
(32bpp, stride = width×4) → `drmModeAddFB` is rejected → `[KMS]: Failed to create FB` → abort.

Fix (`patches/meson8b-osd-xrgb8888.patch`):
1. `meson_plane.c`: add `DRM_FORMAT_XRGB8888` + `DRM_FORMAT_XBGR8888` to `supported_drm_formats_m8[]`.
   `meson_plane_atomic_update()` already sets `OSD_REPLACE_EN` for X formats.
2. `meson_viu.c`: remove M8B from the alpha-replace exclusion so `meson_viu_init()` writes the `0xff`
   replace value → the X (alpha) byte is forced **opaque**.

`CONFIG_DRM_MESON=y` (built-in) → rebuild the whole kernel:
```
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc) zImage
mkimage -A arm -O linux -T kernel -C none -a 0x01080000 -e 0x01080000 -n linux -d arch/arm/boot/zImage uImage
# deploy uImage to the SD /boot (keep a backup of the working one)
```
The kernel cross-toolchain glibc version is irrelevant (kernel is freestanding).

**Critical gotcha — XRGB scanout is BLACK for an empty framebuffer.** On M8B the alpha-replace may not
fully work, so an *empty/cleared* XRGB scanout (e.g. the Xorg root window, or fbcon switching to XR24)
shows **black**. But **opaque rendered content displays correctly** — RetroArch games render real
opaque pixels via lima, so they show fine. Net: use RetroArch **on KMS**, not an X desktop.

## freej2me J2ME core (cross-compiled for armhf)
The libretro buildbot has no armhf `freej2me_libretro.so`. Built it from
`github.com/TASEmulators/freej2me-plus` `src/libretro/`. It is a thin C shim that **`fork+exec`s `java`
(no JNI)** — needs `openjdk-17-jre-headless` on the target + `freej2me-lr.jar`.

**Must build in a `debian:bookworm` container** — the host (newer distro) toolchain links `GLIBC_2.38`
(`__isoc23_strtol`) which the box's glibc 2.36 lacks:
```
docker run --rm -v $PWD/freej2me-plus:/src debian:bookworm bash -c \
 'apt-get update && apt-get install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf make &&
  cd /src/src/libretro && make platform=unix CC=arm-linux-gnueabihf-gcc CXX=arm-linux-gnueabihf-g++'
```
Deploy: `freej2me_libretro.so` → cores dir, `freej2me_libretro.info` → info dir,
`freej2me-lr.jar` → RetroArch **system** dir. `java` must be on PATH for the RetroArch process.
The core passes `-Dfile.encoding=ISO_8859_1` to the JVM itself (don't fight it).

## Kiosk / boot setup
- HW render needs RetroArch directly on KMS (no X): `retroarch.service` with `User=hataketsu`,
  `PAMName=login`, `TTYPath=/dev/tty1`, `Restart=always`,
  `ExecStart=/usr/bin/dbus-run-session /usr/bin/retroarch ...`. cfg: `video_driver=gl`,
  `video_context_driver=kms`, `video_fullscreen=true`.
- Modules auto-load: `/etc/modules-load.d/gpu.conf` (`pwm-meson`, `lima`) +
  `/etc/modprobe.d/lima-softdep.conf` (`softdep lima pre: pwm-meson`). **pwm-meson MUST load first** or
  lima probe defers forever on the `mali-supply` regulator → no `renderD128`.
- Menu (RGUI) on KMS+lima is light (~37% of one core, vs 95% software). Useful cfg:
  `menu_driver=rgui`, `menu_unified_controls=true`, `input_player1_a=enter` (select),
  `input_player1_b=escape` (back), `input_exit_emulator=nul` (no accidental quit),
  `audio_enable=false` (no HDMI-audio device).
- This box runs `multi-user.target` (console) by default; start the kiosk on demand with
  `systemctl start retroarch`, or `systemctl enable retroarch` to boot straight into it.

## Performance notes
- **In-game CPU** with HW render: the GPU render is offloaded to lima; the load is the freej2me
  **Java emulation** (one core) + the java↔core frame pipe. Light games (e.g. Mario) run fine.
- **Heavy games** (e.g. Ninja School) are **emulation-bound**: freej2me is an interpreter (no JIT for
  the game), so it maxes a single Cortex-A5 core regardless of HW render. The A5 is the ceiling; try
  the freej2me frameskip / lower internal fps core-options.
- No soft reboot on this kernel — `reboot` halts; power-cycle to load a new kernel.

## Dead-ends (don't repeat)
- **RetroArch under X11** = llvmpipe software = laggy. Use KMS.
- **RetroArch KMS with the stock kernel** = "Failed to create FB" (XRGB8888 not in the M8B plane list).
  Needs the patch.
- **XFCE desktop with glamor** displays (HW), but on this SoC the **cursor plane is broken** (cursor
  vanishes/flickers on move) and the **compositor recomposites the whole screen via glamor on every
  cursor-damage** → Xorg spikes to ~137% just moving the mouse. Not worth it — dropped XFCE, boot to
  console / RetroArch-KMS instead.
- **TearFree** is not supported by this modesetting build. PageFlip on/off, SW/HW cursor — none fix the
  meson cursor quirk.
- The **SD card is failing** (heavy writes wedge it → remount-ro → ping-but-no-ssh; power-cycle only).
  The full ~3.4 GB jar library won't fit reliably; ~400 games synced before a wedge. Replace the SD or
  use USB for the library.
