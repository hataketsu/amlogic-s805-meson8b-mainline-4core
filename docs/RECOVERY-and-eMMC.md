# Recovery (un-brick) + the safe way to put rootfs on eMMC

_EN; tóm tắt tiếng Việt ở cuối. **READ THIS BEFORE TOUCHING THE eMMC.**_

## What bricks this box (learned the hard way)
The S805 **BootROM reads the bootloader from the eMMC user area at offset 0** (`mmcblk1`
sector 0), NOT from the eMMC HW boot partitions (`mmcblk1boot0/boot1`, which only hold a
*copy*). So **any write to `mmcblk1` sector 0 destroys the bootloader → brick**:
- `fdisk`/`parted` writing an MBR/GPT at sector 0,
- `mke2fs`/`mkfs` on the whole `/dev/mmcblk1`.

Symptom on power-up (UART): `... BOOT:0; READ:0; CHECK:FFFFBF00; ...` = BootROM read the
user-area bootloader, checksum failed → drops to **USB download mode** (`lsusb` = `1b8e:c003`).

## Recover the bootloader (un-brick)
Box is in BootROM USB mode (`1b8e:c003`). Options, most reliable first:

1. **Amlogic USB Burning Tool** (Windows) with the stock firmware `.img` — the standard,
   handles the secure-boot BL2 + writes all partitions. Most reliable for S805/meson8b.
2. **pyamlboot** (Linux, `.venv`): the BootROM mask-ROM mode accepts `readMemory`/`writeMemory`/
   `run` (verified: can read SRAM at `0xd9000000`). The full un-brick loads the BL2 to
   `0xd9000000`, `run`s it, then serves the rest of the **signed** bootloader
   (`bootloader.emmc.win` == `bootloader.bin`, md5 `7db678ce…`) to the BL2 via the **AMLC**
   staged protocol (`getBootAMLC` → `writeAMLCData` loop in `pyamlboot`). The exact BL2 size /
   load order for meson8b must match the stock blob. (`boot.py` only supports GX/AXG, not m8b.)
3. **SD boot** — only if SD boot is fuse-enabled: write the SD-variant bootloader into the SD's
   reserved area (sectors 1..N, partitions relocated after) → BootROM boots from SD → u-boot →
   reflash eMMC. Our SD had FAT starting at sector 1 (no reserved gap), so it was NOT bootable.

Backups we have for restore: full **TWRP** backup (`rom mod_mytv/TWRP/.../*.emmc.win`:
bootloader/boot/recovery/system/data/env/…) + `boot0.bin`/`boot1.bin` dumps.

## The SAFE way to put a Linux rootfs on eMMC (do NOT repartition from sector 0)
mainline can't read the Amlogic proprietary partition table, so `/dev/mmcblk1pN` for the Android
partitions don't appear. Two safe options:

1. **Best: don't touch the eMMC.** Put the rootfs on the **SD card** (`mmcblk0pX`) or **USB**;
   leave the eMMC for the bootloader only. (For SD-rootfs **and** WiFi at once you need USB,
   since SD + WiFi share the single SDIO controller — eMMC-on-sdhc is the other controller.)
2. **If you must use eMMC:** write the rootfs **only inside the Android `data` partition's byte
   range**, never sector 0:
   - get the `data` offset/size from u-boot `mmc part` / `printenv bootargs` (data is the big
     region ~1 GB→end, far from the offset-0 bootloader);
   - `losetup -o <data_offset> /dev/loop0 /dev/mmcblk1; mke2fs -t ext4 /dev/loop0` →
     filesystem stays inside `data`, sector 0 untouched;
   - boot with a tiny initramfs that does `losetup -o <offset> /dev/mmcblk1` then
     `switch_root` into the loop device (kernel `root=` can't take a raw offset).
   A standard MBR (sfdisk) at sector 0 still overwrites 512 B of the bootloader → brick. Avoid.

---

## Tóm tắt (Tiếng Việt) — ĐỌC TRƯỚC KHI ĐỤNG eMMC
**Cái gì brick:** BootROM S805 đọc bootloader ở **user-area `mmcblk1` offset 0** (không phải
boot0). Nên **ghi MBR/mkfs từ sector 0 = đè bootloader = brick** (UART: `CHECK:FFFFBF00` → USB
mode `1b8e:c003`).

**Recover:** (1) **Amlogic USB Burning Tool** (Windows) + ROM gốc — chắc nhất; (2) **pyamlboot**:
mask-ROM nhận `readMemory/writeMemory/run`; un-brick = nạp BL2 vào `0xd9000000`, `run`, rồi serve
bootloader signed (`bootloader.bin`, md5 `7db678ce…`) cho BL2 qua giao thức **AMLC**
(`getBootAMLC`→`writeAMLCData`). (`boot.py` chỉ hỗ trợ GX, không m8b.); (3) **SD boot** nếu fuse
cho phép — ghi bootloader vào vùng reserved của SD. Có sẵn **TWRP backup** đủ partition để restore.

**Ghi rootfs lên eMMC AN TOÀN — KHÔNG repartition từ sector 0:**
- Tốt nhất: **đừng đụng eMMC** — rootfs để **thẻ SD** hoặc **USB**, eMMC chỉ giữ bootloader.
  (Muốn SD-rootfs + WiFi cùng lúc → rootfs USB, vì SD+WiFi chung controller sdio.)
- Nếu phải dùng eMMC: ghi rootfs **chỉ trong vùng partition `data`** (offset lớn ~1GB→hết, xa
  bootloader) bằng `losetup -o <data_offset> /dev/mmcblk1` + `mke2fs` + initramfs `switch_root`
  vào loop. **Tuyệt đối không ghi sector 0.**
