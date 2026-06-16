# Chơi game retro: RetroArch + J2ME trên S805, tăng tốc phần cứng Mali-450

_Tiếng Việt; bản English: [RETROARCH-J2ME.md](RETROARCH-J2ME.md)._

Mục tiêu: chơi game retro (cụ thể là kho **game J2ME `.jar`** điện thoại) trên box, render bằng **GPU
Mali-450** (không phải phần mềm). Tài liệu này ghi cách mở khóa HW render trên meson8b (M8B), core J2ME,
cấu hình kiosk, và các ngõ cụt.

## Tóm tắt
- **HW render chạy được** qua **RetroArch trên KMS video context + lima** (KHÔNG phải dưới X11). Xác nhận:
  `[GL]: Vendor: lima, Renderer: Mali450`.
- Cần **vá kernel** thêm `XRGB8888` vào danh sách format của OSD plane meson8b
  (`patches/meson8b-osd-xrgb8888.patch`) — nếu không, `drmModeAddFB` của RetroArch KMS sẽ lỗi
  ("Failed to create FB").
- Bản vá đó **cũng bật glamor trên lima dưới X** (`glamor X acceleration enabled on Mali450`), nhưng
  **desktop X** không đáng dùng trên SoC này (lỗi con trỏ/compositor — xem mục Ngõ cụt).
- Core **freej2me** đã được **cross-compile cho armhf** (libretro buildbot không có sẵn cho armhf).

## Vì sao phần mềm bị chậm (vấn đề)
Dưới X11 trên meson8b, GLX/EGL rớt về **llvmpipe** (phần mềm) — màn hình meson mặc định không có GL
accel. Luồng render của RetroArch ăn trọn một nhân Cortex-A5 (~100%) + Xorg + 4 luồng llvmpipe ≈ **1.85
nhân chỉ để hiển thị**, cộng thêm phần giả lập J2ME. Kết quả: giật/lag.

## Mở khóa HW render (vá kernel)
Nguyên nhân crash KMS: `drivers/gpu/drm/meson/meson_plane.c` mảng `supported_drm_formats_m8[]` thiếu
`XRGB8888`. S805 = `VPU_COMPATIBLE_M8B` dùng mảng này. Surface KMS/GBM của RetroArch là XRGB8888 (32bpp,
stride = rộng×4) → `drmModeAddFB` bị từ chối → `[KMS]: Failed to create FB` → crash.

Cách sửa (`patches/meson8b-osd-xrgb8888.patch`):
1. `meson_plane.c`: thêm `DRM_FORMAT_XRGB8888` + `DRM_FORMAT_XBGR8888` vào `supported_drm_formats_m8[]`.
   `meson_plane_atomic_update()` vốn đã set `OSD_REPLACE_EN` cho format X.
2. `meson_viu.c`: bỏ M8B khỏi điều kiện loại trừ alpha-replace để `meson_viu_init()` ghi giá trị thay
   thế `0xff` → byte X (alpha) bị ép thành **đục (opaque)**.

`CONFIG_DRM_MESON=y` (built-in) → phải build lại cả kernel:
```
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j$(nproc) zImage
mkimage -A arm -O linux -T kernel -C none -a 0x01080000 -e 0x01080000 -n linux -d arch/arm/boot/zImage uImage
# chép uImage vào /boot trên thẻ SD (giữ backup bản đang chạy)
```
Phiên bản glibc của cross-toolchain không quan trọng (kernel độc lập, không link libc).

**Lưu ý quan trọng — scanout XRGB bị ĐEN với framebuffer rỗng.** Trên M8B alpha-replace có thể không
hoạt động hoàn toàn, nên scanout XRGB *rỗng/đã xóa* (vd cửa sổ gốc Xorg, hoặc fbcon chuyển sang XR24) sẽ
hiện **đen**. NHƯNG **nội dung đã render đục thì hiện đúng** — game RetroArch render pixel đục thật qua
lima nên hiện bình thường. Kết luận: dùng RetroArch **trên KMS**, không dùng desktop X.

## Core J2ME freej2me (cross-compile cho armhf)
Buildbot libretro không có `freej2me_libretro.so` cho armhf. Build từ
`github.com/TASEmulators/freej2me-plus` `src/libretro/`. Nó là shim C mỏng **`fork+exec` `java` (không
JNI)** — cần `openjdk-17-jre-headless` trên máy đích + `freej2me-lr.jar`.

**Phải build trong container `debian:bookworm`** — toolchain trên host (distro mới hơn) link `GLIBC_2.38`
(`__isoc23_strtol`) mà glibc 2.36 của box không có:
```
docker run --rm -v $PWD/freej2me-plus:/src debian:bookworm bash -c \
 'apt-get update && apt-get install -y gcc-arm-linux-gnueabihf g++-arm-linux-gnueabihf make &&
  cd /src/src/libretro && make platform=unix CC=arm-linux-gnueabihf-gcc CXX=arm-linux-gnueabihf-g++'
```
Triển khai: `freej2me_libretro.so` → thư mục cores, `freej2me_libretro.info` → thư mục info,
`freej2me-lr.jar` → thư mục **system** của RetroArch. `java` phải có trong PATH của tiến trình RetroArch.
Core tự truyền `-Dfile.encoding=ISO_8859_1` cho JVM (đừng cố sửa khác).

## Cấu hình kiosk / boot
- HW render cần RetroArch chạy thẳng trên KMS (không X): `retroarch.service` với `User=hataketsu`,
  `PAMName=login`, `TTYPath=/dev/tty1`, `Restart=always`,
  `ExecStart=/usr/bin/dbus-run-session /usr/bin/retroarch ...`. cfg: `video_driver=gl`,
  `video_context_driver=kms`, `video_fullscreen=true`.
- Tự nạp module: `/etc/modules-load.d/gpu.conf` (`pwm-meson`, `lima`) +
  `/etc/modprobe.d/lima-softdep.conf` (`softdep lima pre: pwm-meson`). **pwm-meson PHẢI nạp trước** nếu
  không lima sẽ defer mãi ở regulator `mali-supply` → không có `renderD128`.
- Menu (RGUI) trên KMS+lima nhẹ (~37% một nhân, so với 95% phần mềm). cfg hữu ích:
  `menu_driver=rgui`, `menu_unified_controls=true`, `input_player1_a=enter` (chọn),
  `input_player1_b=escape` (lùi), `input_exit_emulator=nul` (không thoát nhầm),
  `audio_enable=false` (không có thiết bị âm thanh HDMI).
- Box này mặc định chạy `multi-user.target` (console); chạy kiosk khi cần bằng
  `systemctl start retroarch`, hoặc `systemctl enable retroarch` để boot thẳng vào.

## Ghi chú hiệu năng
- **CPU khi chơi** với HW render: render GPU đẩy sang lima; tải còn lại là **giả lập Java freej2me**
  (một nhân) + đường ống truyền frame java↔core. Game nhẹ (vd Mario) chạy mượt.
- **Game nặng** (vd Ninja School) bị **nghẽn ở giả lập**: freej2me là trình thông dịch (không JIT cho
  game) nên ăn trọn một nhân Cortex-A5 dù có HW render. A5 là trần; thử core-option frameskip / giảm
  fps nội bộ của freej2me.
- Kernel này không reboot mềm được — `reboot` bị treo; phải rút điện để nạp kernel mới.

## Ngõ cụt (đừng lặp lại)
- **RetroArch dưới X11** = llvmpipe phần mềm = lag. Dùng KMS.
- **RetroArch KMS với kernel gốc** = "Failed to create FB" (M8B không có XRGB8888 trong plane). Cần vá.
- **Desktop XFCE với glamor** hiện được (HW), nhưng trên SoC này **plane con trỏ bị lỗi** (con trỏ biến
  mất/nhấp nháy khi di) và **compositor recomposite cả màn hình qua glamor mỗi lần con trỏ damage** →
  Xorg vọt ~137% chỉ vì di chuột. Không đáng — bỏ XFCE, boot console / RetroArch-KMS.
- **TearFree** không được modesetting bản này hỗ trợ. PageFlip bật/tắt, con trỏ SW/HW — không cái nào
  sửa được lỗi con trỏ meson.
- **Thẻ SD đang hỏng** (ghi nặng làm treo → remount-ro → ping được mà không ssh được; chỉ rút điện được).
  Kho ~3.4 GB jar không chứa nổi ổn định; ~400 game chép được trước khi treo. Thay SD hoặc dùng USB.
