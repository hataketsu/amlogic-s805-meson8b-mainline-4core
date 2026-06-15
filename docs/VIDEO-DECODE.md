# HW video decode/encode (VPU) on meson8b — status & port materials

_EN; tóm tắt tiếng Việt ở cuối._

## Status
**No hardware video decode/encode on mainline** for S805/Meson8b:
- Mainline `meson-vdec` (V4L2 stateful decoder) supports **GXBB/S905+ only**, not meson8b.
- The vendor stack is the 3.10 `amvdec`/`amports` (decoder) + `amvenc_avc` (H.264 encoder),
  closed userspace `libamcodec` — none upstream.
- Software 1080p H.264/H.265 is **too heavy** for 4× Cortex-A5 @1.5 GHz. GPU `lima`
  (Mali-450) is 3D only, not video.

So this box on mainline = CLI/server. Full-HD HW playback ⇒ stock Android / vendor 3.10
kernel (CoreELEC-style), not mainline.

## What porting would require (large effort)
Three separate pieces, only the firmware is "easy":

1. **VPU firmware microcode (.bin)** — loaded into the decoder/encoder. Lives on the Android
   partitions (`/system/.../firmware/video/*` or embedded). Extractable from a partition dump
   / `binwalk`. Legally re-distributable as firmware. **Necessary but not sufficient.**
2. **Kernel driver** — the real work. Vendor 3.10 `drivers/amlogic/amports`, `amvdec_*`,
   `amvenc_avc` (GPL, in `codesnake/linux-amlogic-old`). Porting 3.10 → 6.x means rewriting
   against modern V4L2 stateful/stateless, DRM, clk, power-domain, reserved-CMA APIs — months
   of kernel work. This is why no one has done meson8b (board too old, too few people).
3. **Userspace** — `libamcodec`/`libvcodec` are closed `.so` calling 3.10 ioctls; useless on
   mainline. A mainline port must expose standard **V4L2 M2M** so `ffmpeg`/GStreamer work.

## Materials to dump from the box (for a porting attempt)
From **stock Android** (the VPU dt + firmware aren't on the mainline system):

```sh
# VPU/codec device-tree nodes (regs / clocks / irqs / firmware paths)
for d in vdec amvenc_avc vpu mesonstream mesonvout ppmgr deinterlace ion_dev dvfs; do
  for f in $(find /proc/device-tree/$d -type f 2>/dev/null); do echo "== $f =="; od -A x -t x1 "$f"; done
done | busybox nc <PC> 9000

# VPU firmware microcode blobs
find /system /vendor /lib/firmware -iname '*.bin' 2>/dev/null | grep -iE 'video|vdec|hevc|h264|h265|ucode|vpu|enc'
# common locations: /system/etc/firmware/video_ucode.bin, /vendor/lib/firmware/video/*
```

Plus, on the PC, the **driver source**:
```
git clone https://github.com/codesnake/linux-amlogic-old
# arch/arm/mach-meson8b + drivers/amlogic/amports, amvdec_*, amlogic/efuse, common/firmware
```

## Realistic verdict
- Firmware blobs: dumpable. ✅
- Driver port 3.10 → mainline 6.x: enormous, single-dev-impractical. ❌
- For actual full-HD playback: use the **vendor 3.10 kernel / Android**, not mainline.

---

## Tóm tắt (Tiếng Việt)
**Mainline không có HW video decode/encode cho meson8b/S805** (`meson-vdec` chỉ cho S905+).
Stack của hãng là `amvdec`/`amvenc` 3.10 + `libamcodec` đóng. Phần mềm giải 1080p quá nặng cho
Cortex-A5. Muốn port: (1) trích firmware microcode `.bin` từ partition Android (dễ); (2) viết
lại driver 3.10 → 6.x theo V4L2/DRM hiện đại (khối lượng khổng lồ — đây là nút thắt); (3) lộ ra
V4L2 M2M cho ffmpeg. Thực tế: muốn xem full HD thì dùng **kernel 3.10/Android của hãng**, không
phải mainline. Repo này ghi rõ cách dump firmware + nguồn driver (codesnake/linux-amlogic-old).
