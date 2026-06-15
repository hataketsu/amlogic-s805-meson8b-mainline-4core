# Pitfalls & gotchas

- **Console is `ttyAML0`, not `ttyS0`.** The 3.10 vendor kernel named the meson UART
  `ttyS0`; mainline names it `ttyAML0`. `console=ttyS0` gives a dead port → init exits → panic.
- **Always keep `earlycon`.** During bring-up, a crash before the real console inits prints
  *nothing*. We lost a boot cycle to a silent hang for want of `earlycon`.
- **Secure registers: reads abort, writes are silently dropped.** A non-secure write to a
  TEE-locked reg doesn't fault — it's ignored. So "no crash" ≠ "it worked". The original SMP
  crash only surfaced on the SRAM *read*; the AO writes had been quietly dropped.
- **The SMC clobbers r2–r12.** The vendor wrappers `push {r2-ip,lr}`. An inline-asm SMC that
  only lists r0–r3 lets the compiler keep live values in r4–r12 that the monitor trashes →
  the caller crashes *right after* a register-heavy SMC (looks like a hang). Clobber r4–r12/lr.
- **ext4 `metadata_csum` needs `crc32c` in the initramfs.** `mkfs.ext4` defaults to it; an
  initramfs with only `crc16` fails to mount root with `Cannot load crc32c driver`.
- **Debian's `/sbin/init` is an absolute symlink.** A pre-`switch_root` `[ -x /mnt/sbin/init ]`
  check resolves the absolute target against the *initramfs* root and fails — just
  `switch_root` and let it resolve in the new root.
- **The TEE-reserved region is much bigger than the SMC reports.** `0x701/0x702` returned the
  48 MB secure-OS sub-region (`0x05000000`), but the *real* reserved gap (from stock
  `/proc/iomem`) is `0x04f00000`–`0x0e900000` ≈ 154 MB. Under-reserving → random aborts under
  load **and** the 4-core mailbox getting corrupted.
- **Kernel phys load address.** This box's `PHYS_OFFSET = 0x200000` (kernel at phys
  `0x208000`), not the usual `0x1080000`. Dumping the wrong range from `/dev/mem` misses it.
  Read `_text` from kallsyms and the `iomem` "Kernel code" line.
- **`kptr_restrict`.** `/proc/kallsyms` zeroes addresses by default — `echo 0 >
  /proc/sys/kernel/kptr_restrict` (root) to get real addresses for RE.
- **eMMC is invisible to mainline.** Its controller is `meson8-sdhc` (no mainline driver);
  only the SD's `meson-mx-sdio` works. Keep the signed bootloader in eMMC, run the OS from SD.
- **The monitor's power-good poll is unbounded.** Calling its `0x207` directly hangs forever
  if the AO power state isn't what the full vendor boot establishes — drive the power
  yourself with a bounded poll instead.
- **1 GB box, no swap, heavy `apt` unpack can OOM/crash.** Enable zram early before large
  installs.
- **Don't put a partition table on a secure-bl SD.** If you boot the signed bootloader from
  SD (offset 0), an MBR at sector 0 corrupts the BL2 signature. (Once eMMC holds the bl, the
  SD can be normally partitioned.)
