# SMP-tz on the xdarklight 6.20 tree

The 6.20 `meson-mx-integration` tree already has a TrustZone SMP method
(`amlogic,meson8-trustzone-firmware-smp`, `arch/arm/mach-meson/tz_firmware.c`),
but on this VNPT m201 monitor its `set_cpu_boot_addr` SMC returns **-38 (ENOSYS)**
— "Failed to set aux core boot address for CPUx using TrustZone secure firmware".

So the **same custom enable-method** from `kernel/0001-meson8b-smp-tz-secure-monitor.patch`
must be added to the 6.20 `arch/arm/mach-meson/platsmp.c`: the `meson_tz_smc()` helper,
`meson8b_tz_smp_boot_secondary()` (direct AO/SCU/HHI power-on + bounded poll + mailbox SMC),
`meson8b_tz_smp_prepare_cpus()`, the `meson8b_tz_smp_ops`, and:

    CPU_METHOD_OF_DECLARE(meson8b_smp_tz, "amlogic,meson8b-smp-tz", &meson8b_tz_smp_ops);

Plus the WiFi OCR patch `kernel/0002-*.patch` on `drivers/mmc/host/meson-mx-sdio.c`.
Result: `nproc=4` + WiFi + HDMI on one kernel. See `dtb/meson8b-m201-unified.dts`.
