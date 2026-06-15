# Unified build — 4 cores + WiFi + HDMI on one kernel

_EN; tóm tắt tiếng Việt ở cuối._

**Everything works together** on a single xdarklight `meson-mx-integration-6.20` kernel:
4 CPU cores (secure-monitor SMP), RTL8189ES WiFi (WPA2 + DHCP + internet), and HDMI
(forced 720p + fbcon console). Verified live: `nproc=4`, `wlan0=192.168.1.x` with 0% ping
loss, `card0-HDMI-A-1` + `fb0=mesondrmfb`.

## Recipe
- **Kernel**: `xdarklight/linux` `meson-mx-integration-6.20-20251223`, config
  `kernel/unified-6.20.config.gz`. Two patches:
  - SMP-tz: add the `amlogic,meson8b-smp-tz` enable-method to
    `arch/arm/mach-meson/platsmp.c` — see `kernel/0001-*.patch` (written for 6.1.174; the same
    functions graft onto 6.20) and `kernel/0003-platsmp-smp-tz-for-6.20.md`. The tree's own
    `amlogic,meson8-trustzone-firmware-smp` returns **-38 (ENOSYS)** on this VNPT monitor, so the
    custom direct-power-on method is required.
  - WiFi OCR: `kernel/0002-meson-mx-sdio-default-ocr-for-sdio-wifi.patch`.
  - Configs: DRM_MESON + TRANSWITCH_HDMI + PHY_MESON8_HDMI_TX + PHY_MESON_CVBS_DAC + FB/fbcon
    + CFG80211=m + RFKILL=m + MMC_MESON_MX_SDIO=y. uImage load/entry `0x01080000`.
- **Device tree**: `dtb/meson8b-m201-unified.dts` (base meson8b-mxq):
  - secmem reservation `0x04e00000`–`0x0e900000`;
  - cpus `enable-method = "amlogic,meson8b-smp-tz"`;
  - disable `video-dac@2f4` + `nvmem@0` (efuse external-abort on the secure box → HDMI-only);
  - SDIO `mmc@8c20` = WiFi `slot@0` (sd_a pins; SD slot removed) + `sd_a`/`xtal_32k_out` pinmux
    + `wifi-pwrseq` (reset GPIOX_11).
- **bootargs**: `... panic=12 video=HDMI-A-1:1280x720@60e`.
- **initramfs**: busybox + the 6.20 `cfg80211`/`rfkill`/`8189es` modules + `wpa_supplicant`;
  auto-connects the AP. (`meson_wdt` + `meson-mx-sdio` are built-in.)

## Caveats
- Rootfs is the **RAM initramfs** — the single SDIO controller is given to WiFi, so the SD card
  slot is unused. A daily SD-rootfs + WiFi build needs the `meson8-sdhc` driver (SD on the other
  controller) or MMC-core multi-slot.
- HDMI is **forced** (HPD/EDID auto-detect not working — see `HDMI.md`).
- One non-fatal kernel Exception during WiFi bring-up (~15 s); WiFi is unaffected (0% loss).

---

## Tóm tắt (Tiếng Việt)
**Tất cả chạy chung trên 1 kernel** xdarklight `meson-mx-integration-6.20`: **4 nhân** (SMP secure
monitor), **WiFi RTL8189ES** (WPA2 + DHCP + internet), **HDMI** (forced 720p + console fbcon). Kiểm
chứng: `nproc=4`, `wlan0` có IP + ping 0% loss, `fb0=mesondrmfb`. 2 patch: SMP-tz thêm enable-method
`amlogic,meson8b-smp-tz` vào `platsmp.c` (method `meson8-trustzone-firmware-smp` của cây trả -38 trên
monitor VNPT này) + OCR `meson-mx-sdio`. dtb `meson8b-m201-unified.dts`: secmem; cpus dùng smp-tz; tắt
video-dac+efuse; SDIO slot@0 = wifi (pins sd_a) + xtal_32k + pwrseq. bootargs `video=...@60e`.
**Hạn chế:** rootfs chạy RAM (SDIO nhường cho wifi, không dùng khe SD); HDMI forced; 1 Exception
non-fatal lúc boot (wifi không ảnh hưởng). Xem `kernel/unified-6.20.config.gz`,
`kernel/0003-platsmp-smp-tz-for-6.20.md`.
