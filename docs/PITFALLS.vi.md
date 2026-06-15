# Các cạm bẫy

- **Console là `ttyAML0`, không phải `ttyS0`.** Kernel vendor 3.10 gọi UART meson là `ttyS0`; mainline gọi `ttyAML0`. Dùng `console=ttyS0` → cổng chết → init thoát → panic.
- **Luôn giữ `earlycon`.** Lúc bring-up, crash trước khi console thật init thì *không in gì*. Mất một lần boot vì treo im lặng do thiếu `earlycon`.
- **Thanh ghi secure: đọc thì abort, ghi thì bị bỏ qua âm thầm.** Ghi non-secure vào reg bị TEE khoá không lỗi — chỉ bị bỏ. "Không crash" ≠ "thành công". Crash SMP gốc chỉ lộ ở lệnh *đọc* SRAM.
- **SMC làm hỏng r2–r12.** Wrapper của hãng `push {r2-ip,lr}`. Inline-asm SMC chỉ khai r0–r3 sẽ để compiler giữ giá trị sống ở r4–r12 mà monitor phá → crash *ngay sau* một SMC nhiều thanh ghi (trông như treo). Phải clobber r4–r12/lr.
- **ext4 `metadata_csum` cần `crc32c` trong initramfs.** `mkfs.ext4` mặc định bật; initramfs chỉ có `crc16` sẽ không mount được root (`Cannot load crc32c driver`).
- **`/sbin/init` của Debian là symlink tuyệt đối.** Kiểm tra `[ -x /mnt/sbin/init ]` trước `switch_root` sẽ giải symlink theo root *initramfs* và fail — cứ `switch_root` để nó giải trong root mới.
- **Vùng TEE giữ lớn hơn nhiều so với SMC báo.** `0x701/0x702` trả vùng secure-OS 48 MB (`0x05000000`), nhưng vùng giữ *thật* (từ `/proc/iomem` Android) là `0x04f00000`–`0x0e900000` ≈ 154 MB. Giữ thiếu → abort ngẫu nhiên khi tải nặng **và** mailbox 4-nhân bị hỏng.
- **Địa chỉ load kernel.** Máy này `PHYS_OFFSET = 0x200000` (kernel ở phys `0x208000`), không phải `0x1080000` thường gặp. Dump sai dải `/dev/mem` là trượt. Đọc `_text` từ kallsyms và dòng "Kernel code" trong `iomem`.
- **`kptr_restrict`.** `/proc/kallsyms` để 0 địa chỉ mặc định — `echo 0 > /proc/sys/kernel/kptr_restrict` để lấy địa chỉ thật.
- **eMMC vô hình với mainline.** Controller là `meson8-sdhc` (chưa có driver mainline); chỉ `meson-mx-sdio` của SD chạy. Giữ bootloader đã ký ở eMMC, chạy OS từ SD.
- **Vòng chờ power-good của monitor là vô hạn.** Gọi `0x207` trực tiếp sẽ treo mãi nếu trạng thái nguồn AO chưa được boot đầy đủ của hãng thiết lập — tự lái nguồn với vòng chờ có giới hạn.
- **Máy 1 GB, không swap, `apt` giải nén nặng có thể OOM/crash.** Bật zram sớm trước khi cài lớn.
- **Đừng đặt bảng phân vùng lên SD chứa bl đã ký.** Nếu boot bl đã ký từ SD (offset 0), MBR ở sector 0 sẽ phá chữ ký BL2. (Khi eMMC đã có bl thì SD phân vùng bình thường được.)
