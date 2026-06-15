# HDMI on AMS805 (meson8b/S805) — working recipe (forced-mode)

Kernel: xdarklight/linux `meson-mx-integration-6.20-20251223`, config `hdmi-kernel-6.20.config`
(multi_v7 + DRM_MESON + DRM_MESON_TRANSWITCH_HDMI + PHY_MESON8_HDMI_TX + PHY_MESON_CVBS_DAC + FB/fbcon).
Source dts: `m201-hdmi.dts` (base meson8b-mxq). Build: zImage @ load/entry 0x01080000.

## dtb fixes (vs stock mxq)
- keep secmem reservation 0x4e00000+0x9b00000
- `video-dac@2f4` (cvbs-dac)  -> status="disabled"   # efuse read = external abort on secure box
- `nvmem@0` (efuse)           -> status="disabled"   # avoid the abort entirely
  (cvbs-dac PHY is optional in meson DRM => HDMI-only works)

## u-boot boot (SD files: /boot/{uImage-hdmi,uInitrd-hdmi,dtb-hdmi})
    mmc rescan 0
    fatload mmc 0 0x11000000 uimage-hdmi
    fatload mmc 0 0x13000000 uinitrd-hdmi
    fatload mmc 0 0x10000000 dtb-hdmi
    setenv initrd_high 0xffffffff
    setenv fdt_high 0xffffffff
    setenv bootargs earlycon=meson,mmio32,0xc81004c0 console=ttyAML0,115200n8 maxcpus=1 panic=8 video=HDMI-A-1:1280x720@60e
    bootm 0x11000000 0x13000000 0x10000000
NOTE: load each fatload as a separate step (12MB uimage is slow; chained cmds collide).

## Result
`[drm] forcing HDMI-A-1 connector on` -> meson_vclk_setup 720p -> `fb0: mesondrmfb` -> console on HDMI at boot.
`video=...@60e` (e=force-enabled) = picture without HPD. HPD/EDID auto-detect NOT working (see memory hdmi-working).

## Known limits
- maxcpus=1 (SMP-tz not ported to 6.20 yet)
- HPD/DDC dead -> forced mode only (no monitor auto-detect / real EDID modes)
- separate kernel from the 6.1.174 wifi/4-core system

## UPDATE: 1080p60 + 4 cores + console-on-HDMI (no WiFi)

Stable config (WiFi omitted — 1080p scanout + WiFi SDIO DMA contend on DDR and hang):
- kernel `uImage-uni` (SMP-tz + OCR + DRM, from the unified 6.20 build)
- dtb `dtb/meson8b-m201-hdmi-4core.dts` = HDMI dtb (cvbs/efuse off) + cpus
  `enable-method = "amlogic,meson8b-smp-tz"` (4 cores), NO wifi slot
- bootargs:
    console=tty0 console=ttyAML0,115200n8 panic=12 video=HDMI-A-1:1920x1080@60e
  - `console=tty0` => kernel log + console render on the HDMI framebuffer
  - `video=HDMI-A-1:1920x1080@60e` => force 1080p60 (CVT 172.8 MHz; HPD/EDID still N/A)
- Result: `Brought up 4 CPUs`, `Console: switching to colour frame buffer device 240x67`,
  `fb0: mesondrmfb` (1920x1080). Stable; text + boot log visible on the TV.

WiFi + 1080p together hangs (DDR bandwidth). WiFi works at 720p, or HDMI-only at 1080p.
