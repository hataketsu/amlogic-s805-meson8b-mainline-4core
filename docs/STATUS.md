# Project status

_EN below; tóm tắt tiếng Việt ở cuối._

## Working ✅
- **Un-bricked** — original signed bootloader restored to eMMC; boots standalone.
- **Debian/Armbian armhf, mainline kernel 6.1.174, from SD card** — persistent.
- **All 4 CPU cores** — `nproc = 4` via the `amlogic,meson8b-smp-tz` enable-method
  (secure-monitor secondary boot). See `RE-secure-monitor.md`.
- **Stability under load** — full TEE-reserved DRAM (`0x04e00000`–`0x0e900000`) carved out.
- **Ethernet** (100M), ssh, zram swap, locale/timezone, base packages.
- **WiFi (RTL8189ES, SDIO)** — ✅ connects to WPA2, DHCP, internet. `sd_a` pinmux + a 1-line
  `meson-mx-sdio` OCR patch + `xtal_32k_out` + the out-of-tree `8189es` driver. WiFi-only on
  the SDIO controller (can't coexist with the SD slot). See `WIFI.md`.
- **HDMI (forced 720p, fbcon)** — ✅ on the **xdarklight 6.20** tree (TranSwitch HDMI + meson8b
  VPU). Forced mode via `video=HDMI-A-1:1280x720@60e`; HPD/EDID auto-detect not yet working.
  See `HDMI.md`.

## Not working / blocked
- **HDMI HPD/EDID auto-detect** — ❌ HPD reads 0 + DDC returns no EDID (likely HDMI +5V supply
  or a meson8b TranSwitch HPD/DDC gap). Forced mode works; auto-detect needs register RE.
- **WiFi + SD card simultaneously** — ❌ one SDIO controller, MMC core = one slot. Needs the
  `meson8-sdhc` driver (for SD on the other controller) or MMC-core multi-slot.
- **Unified kernel** — WiFi/4-core live on 6.1.174, HDMI on the 6.20 xdarklight tree; a single
  build needs porting the SMP-tz patch + the WiFi bits onto 6.20 (in progress).
- **HW video decode/encode (VPU)** — ❌ on mainline. No `amvdec`/`amvenc` driver for meson8b
  upstream (`meson-vdec` is GX/S905+ only). Software 1080p is too heavy for the A5. Porting
  the vendor 3.10 driver is a large effort. See `VIDEO-DECODE.md`.
- **eMMC as Linux storage** — ❌ its controller is `meson8-sdhc`, no mainline driver. eMMC
  only holds the signed bootloader; OS runs from SD.

## Hardware facts
- Amlogic S805 / Meson8b, Cortex-A5 ×4, 1 GB, board `m8b_m201_1G_tee`, secure boot ON.
- Console `ttyAML0`. `PHYS_OFFSET = 0x200000`. TEE-reserved DRAM `0x04f00000`–`0x0e900000`.
- WiFi: SDIO rtl8189etv — power GPIOX_11, 32k GPIOX_10, OOB-IRQ GPIOX_21, ctrl `0xc1108c20`.
- IR: `meson-remote`, AO-IR @ `0xc8100480` (mainline `meson-ir` works + a keymap).

## Suitable use
CLI / server / light Docker (armhf). **Not** an HTPC (no HW video decode on mainline).

---

## Tóm tắt (Tiếng Việt)
- **Chạy được:** hết brick; Debian/Armbian kernel mainline 6.1.174 từ thẻ SD; **đủ 4 nhân**
  (enable-method `amlogic,meson8b-smp-tz`); ổn định khi tải (đã reserve vùng TEE); ethernet, ssh.
- **Chạy được (mới):** **WiFi RTL8189ES** (kết nối WPA2, DHCP, internet — pinmux `sd_a` + vá OCR
  `meson-mx-sdio` + `xtal_32k_out` + driver `8189es`); **HDMI** forced 720p + console fbcon (cây
  xdarklight 6.20, TranSwitch HDMI).
- **Chưa được:** HDMI HPD/EDID auto-detect (giờ forced); thẻ SD + wifi đồng thời (1 controller,
  MMC core 1 slot); kernel hợp nhất (wifi/4-core ở 6.1.174, HDMI ở 6.20); HW video decode/encode.
- **Hợp:** CLI/server/Docker nhẹ + WiFi + HDMI console. Xem phim full HD vẫn cần kernel hãng.
