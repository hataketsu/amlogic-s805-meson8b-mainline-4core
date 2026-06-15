# Lịch sử công việc (theo trình tự)

Khởi điểm: TV box VNPT MyTV S805 bị **xoá bootloader** — chỉ hiện ra như thiết bị USB khi cắm vào PC.

1. **Chẩn đoán chế độ USB.** `lsusb` → `1b8e:c003` = Amlogic BootROM USB recovery. ARM 32-bit, BootROM ở `0xd9040000`.
2. **Dò bằng pyamlboot.** Dump BootROM, đọc được SRAM. Xác nhận chip **secure**.
3. **Tìm thấy backup TWRP** của đúng máy này gồm `bootloader.emmc.win` (4 MB). Entropy 8.0, không có magic `@AML` → **mã hoá/đã ký = secure boot BẬT**.
4. **UART.** Log BootROM: `CHECK:FFFFBF00` (sai chữ ký) trên eMMC ×3 → `USB`.
5. **Boot SD.** Ghi bl đã ký ra SD offset 0; SD fallback (`BOOT:1`) chấp nhận → boot Android gốc từ eMMC. Máy sống lại.
6. **Khôi phục bl eMMC** từ bản copy trên SD → hết brick hẳn.
7. **Đưa kernel mainline lên.** Xác nhận u-boot boot được kernel *chưa ký* (chỉ bootloader bị chặn chữ ký). Boot Debian `linux-image-6.1.0-49-armmp` + `meson8b-mxq.dtb`.
8. **Vá dtb dần.** Tắt các node bị khoá secure gây external abort: `socinfo`, rồi `efuse` + `saradc`. 1 nhân (`nosmp`) boot sạch.
9. **initramfs** (busybox + `meson-mx-sdio` + `ext4` + `crc32c`) `switch_root` sang rootfs ext4 nhãn `ARMROOT`. → **Armbian/Debian bền từ SD**, ssh, ethernet.
10. **Lỗi ổn định.** `external abort` ngẫu nhiên khi tải. Nguyên nhân: kernel dùng nhầm **DRAM TEE giữ**. Dữ liệu quyết định là `/proc/iomem` của Android gốc → khai báo `reserved-memory` cả vùng `0x04f00000`–`0x0e900000`.
11. **RE 4 nhân.** SMP meson8b mainline treo/lỗi (SRAM secure). Dump + disassemble secure monitor → lấy được giao thức khởi động nhân phụ. Xem `RE-secure-monitor.vi.md`.
12. **RE kernel gốc.** Boot Android, dump kernel từ `/dev/mem` (`kptr_restrict=0`) qua `busybox nc`. Xác nhận dùng cùng `0x207` và monitor phá r2–r12 qua SMC.
13. **Sửa 4 nhân.** Enable-method mới `amlogic,meson8b-smp-tz`: tự bật nguồn nhân qua AO/SCU/HHI với vòng chờ có giới hạn, set mailbox + SRAM secure qua `smc` r0=3, `sev`. → `power-good OK`, **`Brought up 4 CPUs`**.
14. **Triển khai cố định.** Kernel 6.1.174 + dtb tz + module khớp lên SD; một lần `saveenv` (bỏ `nosmp`).
