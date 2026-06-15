# Project status

_EN below; tóm tắt tiếng Việt ở cuối._

## Working ✅
- **Un-bricked** — original signed bootloader restored to eMMC; boots standalone.
- **Debian/Armbian armhf, mainline kernel 6.1.174, from SD card** — persistent.
- **All 4 CPU cores** — `nproc = 4` via the `amlogic,meson8b-smp-tz` enable-method
  (secure-monitor secondary boot). See `RE-secure-monitor.md`.
- **Stability under load** — full TEE-reserved DRAM (`0x04e00000`–`0x0e900000`) carved out.
- **Ethernet** (100M), ssh, zram swap, locale/timezone, base packages.

## Not working / blocked
- **WiFi (rtl8189etv, SDIO)** — ❌ on mainline. Shares the single SDIO controller
  (`0xc1108c20`) with the SD card; `meson-mx-sdio` binds only one slot, and the SD-card
  rootfs holds it. Needs storage moved off SD (USB/eMMC) to free the controller, plus the
  out-of-tree `rtl8189es` driver + a 32kHz clock (GPIOX_10). See `WIFI.md`.
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
- **Chưa được:** WiFi rtl8189etv (SDIO dùng chung controller với thẻ SD, mainline 1 slot →
  xung đột); giải mã/mã hoá video phần cứng (chưa có driver VPU meson8b mainline); eMMC làm ổ
  Linux (chưa có driver `meson8-sdhc`).
- **Hợp:** CLI/server/Docker nhẹ. **Không hợp** xem phim full HD (không có HW decode mainline).
