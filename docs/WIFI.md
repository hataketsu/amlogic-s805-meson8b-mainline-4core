# WiFi (RTL8189ES / rtl8189etv, SDIO) — WORKING on mainline

_EN; tóm tắt tiếng Việt ở cuối._

**Status: WORKING.** RTL8189ES connects to a WPA2 AP, gets DHCP, full internet — on a
mainline 6.1.174 kernel + the upstream `meson-mx-sdio` driver (one small patch) + the
out-of-tree `8189es` module. As far as we can find, this is the first public RTL8189ES bring-up
on mainline `meson-mx-sdio` / S805.

## The chip & wiring (from the stock device-tree)
- Chip: **Realtek RTL8189ES** (SDIO 802.11n), vendor module `8189es` / `RTL871X`.
- SDIO controller `0xc1108c20` (`meson-mx-sdio`), **port 0 = WiFi**, port 1 = SD card.
- power-enable: **GPIOX_11**; 32.768 kHz LPO: **GPIOX_10**; OOB-IRQ: GPIOX_21.

## The four things that mattered
1. **Pinmux = the key fix.** WiFi is on the controller's **port 0** = `slot@0` (reg=0) = the
   **`sd_a`** pin group (GPIOX_0/1/2/3 data, GPIOX_8 clk, GPIOX_9 cmd) — *not* `sd_b` (which is
   the SD card on the CARD bank). Mux `sd_a` (function `"sd_a"`) in the controller's `pinctrl-0`.
   Without it the card sits on un-muxed GPIO → "Card stuck being busy" / no OCR.
2. **Default OCR.** `meson-mx-sdio` sets no `ocr_avail`; with no vmmc regulator the MMC core
   rejects the card ("no support for card's volts", -22). One-line patch advertises a default
   3.3 V OCR — see `kernel/0002-meson-mx-sdio-default-ocr-for-sdio-wifi.patch`.
3. **32 kHz LPO.** Mux **`xtal_32k_out`** (GPIOX_10) in the same `pinctrl-0` to route the SoC's
   32.768 kHz crystal to the chip. Power via `mmc-pwrseq-simple`, `reset-gpios = GPIOX_11`.
4. **Driver.** Build the out-of-tree `8189es` (jwrdegoede/rtl8189ES_linux) for armhf 6.1.x,
   `insmod 8189es.ko rtw_power_mgnt=0 rtw_ips_mode=0` (disable IPS power-save), needs
   `cfg80211` + `rfkill`. Then `wpa_supplicant` + `udhcpc`.

See `dtb/meson8b-m201-wifi.dts` for the full slot@0 + pinmux + pwrseq.

## dtb fragment
```dts
&sdio_pinctrl_node {          /* the controller's pinctrl-0 target */
    mux { groups = "sd_d0_a","sd_d1_a","sd_d2_a","sd_d3_a","sd_clk_a","sd_cmd_a";
          function = "sd_a"; bias-pull-up; };
    mux { groups = "xtal_32k_out"; function = "xtal"; };
};
wifi_pwrseq: wifi-pwrseq {
    compatible = "mmc-pwrseq-simple";
    reset-gpios = <&gpio GPIOX_11 GPIO_ACTIVE_LOW>;
};
&sdio {                       /* mmc@8c20 */
    slot@0 { compatible = "mmc-slot"; reg = <0>; bus-width = <4>;
             non-removable; cap-sd-highspeed; no-1-8-v;
             keep-power-in-suspend; mmc-pwrseq = <&wifi_pwrseq>; };
};
```

## Caveats
- **`meson-mx-sdio` has no SDIO IRQ** (`.enable_sdio_irq` absent) → interrupts are polled
  (works, a bit slower). Note: declaring `cap-sdio-irq` on the slot makes the 6.1 MMC core
  *reject* the host with -EINVAL ("missing ->enable_sdio_irq() ops") — do NOT set it.
- **SD card + WiFi cannot coexist** on mainline: one SDIO controller, and the MMC core only
  supports one slot per controller (multi-slot was removed before merge; the driver registers
  the first enabled `mmc-slot`). The maintainer's workaround is to put the SD card on the
  *other* controller (`meson8-sdhc`, which has no mainline driver yet). So this is a WiFi-only
  dtb; rootfs runs from RAM/USB/NFS, not the SD slot.

---

## Tóm tắt (Tiếng Việt)
**WiFi RTL8189ES CHẠY** trên mainline 6.1.174: kết nối WPA2, DHCP, vào internet. 4 thứ quyết định:
(1) **pinmux `sd_a`** — wifi ở port 0 = pins `sd_a` (GPIOX_0/1/2/3/8/9), không phải `sd_b` (thẻ SD);
(2) **OCR mặc định** — vá `meson-mx-sdio` 1 dòng (driver không set ocr_avail → "no support for card's volts");
(3) **clock 32k** — mux `xtal_32k_out` (GPIOX_10) + pwrseq reset GPIOX_11;
(4) driver `8189es` out-of-tree `rtw_power_mgnt=0`, rồi wpa_supplicant.
**Hạn chế:** `meson-mx-sdio` không có SDIO-IRQ (poll); **không** chạy đồng thời thẻ SD + wifi (1 controller,
MMC core 1 slot) → đây là dtb wifi-only, rootfs chạy từ RAM/USB. Xem `dtb/meson8b-m201-wifi.dts` +
`kernel/0002-*.patch`.
