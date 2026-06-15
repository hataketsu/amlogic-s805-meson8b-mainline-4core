# WiFi (rtl8189etv, SDIO) — findings & why it's blocked on mainline

_EN; tóm tắt tiếng Việt ở cuối._

## The chip & wiring (from the stock device-tree)
- Chip: **Realtek rtl8189etv** — SDIO 802.11n. (Stock dt node `wifi`, compatible
  `amlogic,aml_broadcm_wifi` — the Amlogic generic wifi-power framework; bus is SDIO.)
- **power-enable**: GPIOX_11 (`wifi_power/power_gpio`)
- **32.768 kHz clock**: GPIOX_10 (`wifi/clock_32k_pin`)
- **out-of-band IRQ**: GPIOX_21 (`wifi/interrupt_pin`)
- **SDIO controller**: `0xc1108c20` (vendor `amlogic,aml_sdio`, port 0 = wifi, port 1 = SD).

## The blocker
The WiFi and the SD-card slot are **two ports of the same single SDIO controller**
(`0xc1108c20`). The vendor 3.10 driver time-multiplexes them. The mainline
`meson-mx-sdio` driver binds **exactly one slot** (`of_get_compatible_child` → first
`mmc-slot`), and the **SD-card rootfs holds it**. Adding a second `slot@0` (wifi) is silently
ignored — only `c1108c20.mmc:slot@1` registers. So **WiFi cannot coexist with an
SD-card rootfs** on this hardware under mainline.

## Paths to enable WiFi
1. **Move rootfs off the SD card** (USB stick, or eMMC once `meson8-sdhc` is ported), so the
   SDIO controller is free for the WiFi slot. u-boot still loads kernel/dtb/initrd from the SD
   FAT (it muxes SD itself), then the kernel gives the controller to WiFi.
2. Then add the WiFi slot + an `mmc-pwrseq-simple` (reset-gpios = GPIOX_11) + a **32kHz clock**
   on GPIOX_10 (the fiddly part — meson8b can mux a clock out, or some boards use a crystal).
3. Build the **out-of-tree `rtl8189es`/`rtl8189fs` driver** for armhf 6.1.x (e.g.
   github `jethome-ru/rtl8189ES_linux`), `insmod`, then `wpa_supplicant`.

## dtb fragment (for when the controller is free)
```dts
wifi_pwrseq: wifi-pwrseq {
    compatible = "mmc-pwrseq-simple";
    reset-gpios = <&gpio GPIOX_11 GPIO_ACTIVE_LOW>;
    /* clocks = <&wifi_32k>;  // 32.768 kHz on GPIOX_10 */
};
&sdio_controller {            /* mmc@8c20 */
    slot@0 {
        compatible = "mmc-slot";
        reg = <0>;
        bus-width = <4>;
        non-removable;
        cap-sdio-irq;
        keep-power-in-suspend;
        mmc-pwrseq = <&wifi_pwrseq>;
    };
};
```

## Status: not pursued (eth-only kept)
Ethernet works; WiFi requires giving up the SD-card slot + USB rootfs + out-of-tree driver +
the 32k clock. Documented for anyone who wants to take it on.

---

## Tóm tắt (Tiếng Việt)
WiFi rtl8189etv (SDIO) dùng **chung controller `0xc1108c20`** với khe thẻ SD. Mainline
`meson-mx-sdio` chỉ bind **một slot**, và rootfs trên thẻ SD đang giữ nó → **WiFi không
chạy song song với rootfs trên SD**. Muốn bật WiFi: chuyển rootfs sang USB/eMMC để giải
phóng controller, thêm slot wifi + `mmc-pwrseq` (GPIOX_11) + clock 32k (GPIOX_10), rồi build
driver `rtl8189es` out-of-tree cho armhf 6.1. Hiện giữ chạy ethernet.
