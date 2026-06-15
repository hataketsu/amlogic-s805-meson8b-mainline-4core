# Amlogic S805 (Meson8b) — mainline Linux + all 4 cores on a secure-boot TV box

Reviving a **VNPT MyTV** TV box (Amlogic **S805 / Meson8b**, board `m8b_m201_1G_tee`,
1 GB, 4× Cortex-A5, **secure boot / TrustZone**) from an erased bootloader all the way
to mainline-kernel Debian/Armbian running on **all 4 CPU cores** — which the upstream
meson8b SMP code cannot do on a secure-boot box.

This repo documents the full reverse-engineering effort and ships the reusable pieces:
a kernel patch, device trees, and build scripts.

## TL;DR results

| | |
|---|---|
| Un-brick | Restored the original **signed** bootloader to eMMC (BootROM USB + TWRP backup) |
| OS | Debian 12 armhf + **mainline kernel 6.1.174**, boots from SD |
| Storage instability | Root-caused: kernel was using **TEE-reserved DRAM** → `reserved-memory` carve-out |
| **4 cores** | **Working** — secondary CPUs brought up via the vendor secure-monitor protocol, recovered by disassembling the firmware |
| **WiFi (RTL8189ES)** | **Working** — WPA2 + internet; `sd_a` pinmux + 1-line `meson-mx-sdio` OCR patch + `xtal_32k_out` + out-of-tree `8189es`. See [docs/WIFI.md](docs/WIFI.md) |
| **HDMI** | **Working** (forced 720p + fbcon) on the xdarklight 6.20 TranSwitch-HDMI tree. See [docs/HDMI.md](docs/HDMI.md) |

The headline result: **`nproc` = 4** on a mainline kernel, on a box whose proprietary
TrustZone monitor gates CPU power-up. Upstream `meson8b` SMP assumes a non-secure SoC and
hangs/faults here; this patch routes secondary boot the way the stock firmware does.

## Why upstream doesn't work here

Mainline `arch/arm/mach-meson/platsmp.c` (`amlogic,meson8b-smp`) brings up cores by
**directly** poking the SCU, the AO CPU-power registers, and the SMP holding-pen SRAM.
On this box those live behind the **secure monitor**:

- The SMP holding-pen SRAM is **secure-locked** → a non-secure read is an *external abort*
  (secure writes are silently dropped — that's the subtle part).
- The secondary CPUs' reset vector goes **into the secure monitor**, which only releases a
  core after its **per-CPU mailbox** is set; the mainline mechanism never touches that mailbox.
- The monitor's own "set boot addr + power" SMC (`0x207`) exists but its internal
  **power-good poll spins forever** in our boot context.

## How this patch boots 4 cores

A new CPU enable-method `amlogic,meson8b-smp-tz` that mirrors what the firmware's secure
monitor does internally (recovered by disassembling the monitor — see
[docs/RE-secure-monitor.md](docs/RE-secure-monitor.md)):

1. **Power the core ourselves** via the AO / SCU / HHI registers (these *are* non-secure
   accessible) with a **bounded** power-good poll (the monitor's own poll is unbounded).
2. Set the monitor's per-CPU **mailbox** (`0x05104da4 + cpu*4`) to the kernel entry, and the
   SMP holding-pen SRAM (`0xd901ff84`, `0xd901ff80`) to the monitor's secure entry
   `0x05100128` — all via the monitor's **secure-register-write SMC** (`smc` r0=3).
3. `sev`. The core resets into the monitor, which reads the mailbox and drops to non-secure
   at our `secondary_startup`.

Plus a `reserved-memory` carve-out of the **entire TEE-reserved DRAM gap** (`0x04e00000`–
`0x0e900000`, derived from the stock Android `/proc/iomem`) — required for both the 4-core
mailbox to survive *and* general stability under load.

## Layout

```
kernel/   0001-meson8b-smp-tz-secure-monitor.patch   # the platsmp.c patch (against v6.1.174)
dtb/      meson8b-m201.dts        # 1-core: secmem reservation + disabled secure-locked nodes
          meson8b-m201-tz.dts     # 4-core: + cpus enable-method = "amlogic,meson8b-smp-tz"
scripts/  build-kernel.sh  make-initramfs.sh  build-sd.sh
docs/     STATUS  HISTORY  MILESTONES  PITFALLS  RE-secure-monitor  WIFI  VIDEO-DECODE
          android-iomem.txt  stock-smp-symbols.txt
```

## Quick start

```bash
# 1. kernel
./scripts/build-kernel.sh            # downloads linux 6.1.174, applies the patch, cross-builds
# 2. device tree (4-core)
dtc -I dts -O dtb -o meson8b-m201-tz.dtb dtb/meson8b-m201-tz.dts
# 3. initramfs that loads meson-mx-sdio + ext4 and switch_roots to LABEL=ARMROOT
./scripts/make-initramfs.sh
# 4. write the SD (FAT boot + ext4 rootfs) and deploy
./scripts/build-sd.sh /dev/sdX
```

Boot from u-boot:
```
setenv bootargs 'console=ttyAML0,115200n8 rootwait rw'
fatload mmc 0 0x11000000 uImage; fatload mmc 0 0x12000000 uInitrd; fatload mmc 0 0x10000000 dtb
bootm 0x11000000 0x12000000 0x10000000
```

## Hardware specifics (this exact box)

- SoC Amlogic S805 / Meson8b, Cortex-A5 ×4, 1 GB, board `m8b_m201_1G_tee`, secure boot ON.
- Console is **`ttyAML0`** on mainline (the 3.10 vendor kernel called it `ttyS0`).
- SD via the SDIO controller (`meson-mx-sdio`); eMMC's controller (`meson8-sdhc`) has no
  mainline driver, so eMMC is not usable from the mainline kernel (we keep the signed
  bootloader there and run the OS from SD).
- TEE-reserved DRAM: `0x04f00000`–`0x0e900000` (≈154 MB), secure-monitor at `0x05000000`.

## Caveats / scope

- The `0x05100128` / `0x05104da4` / `0xd901ff80` addresses and the AO/SCU/HHI offsets are
  specific to **this firmware build**. Another S805 box's monitor may differ — re-derive
  with the method in `docs/RE-secure-monitor.md` (dump the monitor via the `smc` r0=2 read,
  disassemble it).
- Single-core works everywhere; the 4-core path depends on the monitor exposing the
  secure-register r/w and core SMCs (this VNPT 2018 build does).
- No proprietary firmware blobs are included (bootloader / secure-monitor are the vendor's).

## License

Kernel patch: GPL-2.0 (derives from `arch/arm/mach-meson/platsmp.c`). Docs/scripts: MIT.
