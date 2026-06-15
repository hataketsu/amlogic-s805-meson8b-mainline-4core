# Các cột mốc

1. **Xác định BootROM USB recovery** (`1b8e:c003`), xác nhận SoC secure-boot (BL2 mã hoá, `CHECK:FFFFBF00`).
2. **Boot từ SD** bằng bootloader *đã ký* gốc (lấy từ backup TWRP) qua đường SD fallback của BootROM — dấu hiệu sống đầu tiên.
3. **Cứu eMMC** bằng cách khôi phục bootloader đã ký → boot độc lập.
4. **Kernel mainline chạy** (6.1.x) trên phần cứng — console UART, DRAM, clock.
5. **Debian/Armbian chạy bền từ SD** — rootfs ext4, ethernet, ssh.
6. **Tìm & sửa mất ổn định khi tải nặng** — khai báo `reserved-memory` đúng vùng TEE giữ (suy ra từ `/proc/iomem` của Android gốc).
7. **Dịch ngược SMC ABI của secure monitor** và toàn bộ giao thức khởi động nhân phụ (dump + disassemble monitor).
8. **Đủ 4 nhân CPU online trên kernel mainline** — `Brought up 4 CPUs` trên máy secure-boot mà SMP meson8b upstream bó tay.
