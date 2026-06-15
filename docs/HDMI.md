# HDMI on S805 / Meson8b — WORKING (forced mode) on the xdarklight tree

_EN; tóm tắt tiếng Việt ở cuối._

**Status: WORKING** (picture + fbcon console on screen), with caveats. Mainline 6.1 has **no**
meson8b display at all; HDMI needs Martin Blumenstingl's (xdarklight) integration tree, which
carries a meson8b VPU/CVBS/HDMI DRM stack and a dedicated **TranSwitch HDMI** bridge driver
(`drivers/gpu/drm/meson/meson_transwitch_hdmi.c`) — the S805 HDMI-TX is *not* the Synopsys
DW-HDMI used on GX/G12.

## Kernel
- Tree: `github.com/xdarklight/linux`, branch `meson-mx-integration-6.20-20251223`.
- Config: `kernel/hdmi-kernel-6.20.config.gz` (`multi_v7_defconfig` + the enables below).
  `CONFIG_DRM_MESON=y`, `CONFIG_DRM_MESON_TRANSWITCH_HDMI=y`, `CONFIG_PHY_MESON8_HDMI_TX=y`,
  `CONFIG_PHY_MESON_CVBS_DAC=y`, `CONFIG_DRM_FBDEV_EMULATION=y`, `CONFIG_FB=y`,
  `CONFIG_FRAMEBUFFER_CONSOLE=y`, `CONFIG_IKCONFIG_PROC=y`.
- uImage load/entry = `0x01080000`.

## Device tree (`dtb/meson8b-m201-hdmi.dts`, base = meson8b-mxq)
- Keep the TEE secmem reservation (`0x04e00000`–`0x0e900000`).
- **Disable `video-dac@2f4` (the CVBS DAC) AND `nvmem@0` (efuse)**. On this secure box, reading
  the efuse at `0xda000000` is an **external abort** (`Internal error: 8`), and the CVBS-DAC PHY
  hard-requires its `cvbs_trimming` efuse cell → crash that blocks the whole VPU. The CVBS-DAC
  PHY is `devm_phy_optional_get()` in the meson DRM CVBS encoder, so disabling it gives a clean
  **HDMI-only** pipeline and the VPU/DRM probe fine.

## Boot (see `docs/HDMI-BOOT-RECIPE.md` for the exact u-boot steps)
Key bootarg: `video=HDMI-A-1:1280x720@60e` — the `e` forces the connector *enabled*, so a mode
is set and `fb0` is created at boot **without** relying on HPD. Result:
```
[drm] Initialized meson 1.0.0 for d0100000.vpu on minor 0
[drm] forcing HDMI-A-1 connector on
meson-drm ... meson_vclk_setup(... phy: 742500000 ...)   # 720p
meson-drm ... [drm] fb0: mesondrmfb frame buffer device  # console on HDMI
```

## Caveats / not done
- **HPD + DDC/EDID auto-detect do NOT work.** `TX_HDCP_ST_EDID_STATUS` HPD bit reads 0 and DDC
  returns no EDID even with a monitor connected and the controller + PHY powered. Likely the
  HDMI +5 V supply (vendor `amhdmitx/pwr_ctrl` `pwr_5v_on`, a driver-controlled register — not a
  DT GPIO) or a meson8b TranSwitch HPD/DDC gap. Hence the **forced** `video=...@60e` mode rather
  than the monitor's real EDID modes. Fixing it needs register-level RE of the vendor HPD/DDC/5V.
- `maxcpus=1` here — the 4-core secure-monitor SMP (`amlogic,meson8b-smp-tz`,
  `kernel/0001-*.patch`) is for 6.1.174 and not yet ported to this 6.20 tree.
- This is a different kernel from the 6.1.174 WiFi/4-core system; a unified build means porting
  both the SMP-tz patch and the WiFi bits onto 6.20.

---

## Tóm tắt (Tiếng Việt)
**HDMI CHẠY** (có hình + console fbcon trên màn), chế độ **forced**. Mainline 6.1 không có display
meson8b; phải dùng cây **xdarklight** `meson-mx-integration-6.20` (driver mới `meson_transwitch_hdmi.c`
+ VPU/CVBS/PHY meson8b). dtb (base mxq): giữ secmem, **tắt `video-dac` (cvbs-dac) + `nvmem@0` (efuse)**
vì đọc efuse trên box secure bị *external abort*; cvbs-dac phy là optional nên HDMI-only OK. Bootarg
mấu chốt: `video=HDMI-A-1:1280x720@60e` (`e` = ép connector bật → có hình lúc boot, khỏi cần HPD).
**Chưa xong:** HPD/EDID auto-detect (HPD đọc 0 + DDC không ra EDID — chắc do nguồn HDMI +5V hoặc lỗ
hổng HPD/DDC transwitch meson8b → cần RE register); `maxcpus=1` (chưa port SMP-tz 4 core lên 6.20).
Xem `dtb/meson8b-m201-hdmi.dts`, `docs/HDMI-BOOT-RECIPE.md`, `kernel/hdmi-kernel-6.20.config.gz`.
