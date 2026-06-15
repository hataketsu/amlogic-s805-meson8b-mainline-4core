# Work history (chronological)

Starting point: a VNPT MyTV S805 box with the **bootloader erased** — it only enumerated as
a USB device when plugged into a PC.

1. **Diagnose USB mode.** `lsusb` → `1b8e:c003` = Amlogic BootROM USB recovery mode. BootROM
   fell through to USB because eMMC had no valid bootloader. 32-bit ARM confirmed (reset
   vector `ldr pc,[pc,#0x38]`), BootROM at `0xd9040000`.
2. **pyamlboot probing.** Dumped the BootROM, mapped readable SRAM, confirmed `READ_MEM`
   works. Found the chip is **secure** (boot state machine `INIT→READ→CHECK→…`).
3. **Found a TWRP backup** of this exact box including `bootloader.emmc.win` (4 MB). Entropy
   = 8.0, no `@AML` magic, no plaintext u-boot → **encrypted/signed = secure boot ON**.
4. **UART** connected. BootROM log: `CHECK:FFFFBF00` (signature fail) on eMMC ×3 → `USB`.
   Confirmed: BootROM only runs the eFUSE-key-encrypted BL2.
5. **SD boot.** Wrote the signed `bootloader.emmc.win` to the SD at offset 0; BootROM's SD
   fallback (`BOOT:1`) accepted it → booted the stock Android off eMMC. Box alive again.
6. **Restored eMMC bootloader** from the on-device SD copy → un-bricked permanently (boots
   standalone without SD).
7. **Mainline kernel bring-up.** Confirmed via TFTP that u-boot boots an *unsigned* kernel
   (only the bootloader is signature-gated, not the kernel). Booted Debian's
   `linux-image-6.1.0-49-armmp` + `meson8b-mxq.dtb`.
8. **dtb whack-a-mole.** Disabled secure-locked nodes that external-aborted under mainline
   drivers: `socinfo` (assist/bootrom syscon), then `efuse` + `saradc`. Renamed to an m201
   dtb. Single-core (`nosmp`) boots cleanly.
9. **initramfs** (busybox + `meson-mx-sdio` + `ext4` + `crc32c`) that `switch_root`s to an
   ext4 rootfs labelled `ARMROOT`. Built a Debian armhf rootfs via `debootstrap` + qemu.
   → **persistent Armbian/Debian from SD**, ssh, ethernet.
10. **Stability bug.** Random `external abort` under load. Root cause: the kernel was using
    **TEE-reserved DRAM**. Iterated the `reserved-memory` region; the decisive data was the
    **stock Android `/proc/iomem`** showing usable RAM = two blocks with a `0x04f00000`–
    `0x0e900000` gap → reserved that whole gap.
11. **4-core RE.** Mainline `meson8b` SMP hangs/faults (secure SRAM). Disassembled the secure
    monitor (dumped via the `smc` r0=2 read) → recovered the secondary-boot protocol
    (`0x207` set-addr, the `0x513627c` power routine, the `0x05100128` monitor entry, the
    `0x05104da4` mailbox). See `RE-secure-monitor.md`.
12. **Stock kernel RE.** Booted stock Android, dumped its kernel from `/dev/mem`
    (`kptr_restrict=0` for symbols) over `busybox nc`. Confirmed it uses the same `0x207`,
    and that the monitor clobbers r2–r12 across SMCs.
13. **The 4-core fix.** New `amlogic,meson8b-smp-tz` enable-method: power the core directly
    via AO/SCU/HHI ioremap with a **bounded** poll, set the secure mailbox + SRAM via `smc`
    r0=3, `sev`. → `power-good OK`, **`Brought up 4 CPUs`**.
14. **Permanent deploy.** 6.1.174 kernel + tz dtb + matching modules to the SD; one u-boot
    `saveenv` (drop `nosmp`).
