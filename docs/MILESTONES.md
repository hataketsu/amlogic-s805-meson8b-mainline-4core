# Milestones

1. **Identified BootROM USB recovery mode** (`1b8e:c003`) and confirmed the SoC is
   secure-boot (encrypted BL2, `CHECK:FFFFBF00`).
2. **Booted from SD** using the original *signed* bootloader (from a TWRP backup) via the
   BootROM SD fallback — first sign of life.
3. **Un-bricked the eMMC** by restoring the signed bootloader → standalone boot.
4. **Mainline kernel running** (6.1.x) on the hardware — UART console, DRAM, clocks.
5. **Persistent Debian/Armbian from SD** — ext4 rootfs, ethernet, ssh.
6. **Root-caused & fixed the load instability** — carved the full TEE-reserved DRAM gap out
   of the device tree (derived from stock `/proc/iomem`).
7. **Reverse-engineered the secure monitor's SMC ABI** and the complete secondary-CPU boot
   protocol by dumping + disassembling the monitor.
8. **All 4 CPU cores online on a mainline kernel** — `Brought up 4 CPUs` on a secure-boot
   box where upstream meson8b SMP cannot.
