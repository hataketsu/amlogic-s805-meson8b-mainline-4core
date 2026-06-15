# Amlogic S805 (Meson8b) — Linux mainline + đủ 4 nhân trên TV box secure-boot

Hồi sinh một **TV box VNPT MyTV** (Amlogic **S805 / Meson8b**, board `m8b_m201_1G_tee`,
1 GB, 4× Cortex-A5, **secure boot / TrustZone**) từ tình trạng **mất bootloader** cho tới
khi chạy Debian/Armbian kernel mainline trên **cả 4 nhân CPU** — điều mà code SMP meson8b
upstream không làm được trên máy secure-boot.

Repo này ghi lại toàn bộ quá trình reverse-engineering và cung cấp các phần tái sử dụng được:
patch kernel, device tree, và script build.

## Tóm tắt kết quả

| | |
|---|---|
| Cứu brick | Khôi phục bootloader **đã ký** gốc vào eMMC (BootROM USB + backup TWRP) |
| Hệ điều hành | Debian 12 armhf + **kernel mainline 6.1.174**, boot từ thẻ SD |
| Mất ổn định khi tải nặng | Tìm ra nguyên nhân: kernel dùng nhầm **DRAM mà TEE giữ riêng** → khai báo `reserved-memory` |
| **4 nhân** | **Chạy được** — khởi động các nhân phụ qua giao thức của secure monitor, lấy được bằng cách dịch ngược firmware |
| **WiFi (RTL8189ES)** | **Chạy được** — kết nối WPA2 + internet; pinmux `sd_a` + vá OCR `meson-mx-sdio` 1 dòng + `xtal_32k_out` + driver `8189es`. Xem [docs/WIFI.md](docs/WIFI.md) |
| **HDMI** | **Chạy được** (forced 720p + console fbcon) trên cây xdarklight 6.20 TranSwitch-HDMI. Xem [docs/HDMI.md](docs/HDMI.md) |

Kết quả nổi bật: **`nproc` = 4** trên kernel mainline, trên máy mà secure monitor (TrustZone)
khoá việc bật nguồn CPU. SMP `meson8b` upstream giả định SoC không secure nên treo/lỗi ở đây;
patch này khởi động nhân phụ giống cách firmware gốc làm.

## Vì sao upstream không chạy được

`arch/arm/mach-meson/platsmp.c` mainline (`amlogic,meson8b-smp`) bật nhân bằng cách **ghi
trực tiếp** vào SCU, các thanh ghi nguồn CPU vùng AO, và SRAM holding-pen của SMP. Trên máy
này các vùng đó nằm sau **secure monitor**:

- SRAM holding-pen bị **khoá secure** → đọc từ non-secure = *external abort* (ghi thì bị
  **âm thầm bỏ qua** — đây là điểm khó nhận ra).
- Reset vector của nhân phụ trỏ **vào secure monitor**, monitor chỉ thả nhân sau khi
  **mailbox theo từng nhân** được set; cơ chế upstream không đụng tới mailbox đó.
- SMC "set boot addr + bật nguồn" (`0x207`) của monitor có tồn tại nhưng **vòng lặp chờ
  power-good bên trong nó quay vô hạn** trong ngữ cảnh boot của ta.

## Cách patch này bật 4 nhân

Thêm một enable-method mới `amlogic,meson8b-smp-tz`, mô phỏng đúng những gì secure monitor
làm bên trong (lấy được bằng cách dịch ngược monitor — xem
[docs/RE-secure-monitor.vi.md](docs/RE-secure-monitor.vi.md)):

1. **Tự bật nguồn nhân** qua các thanh ghi AO / SCU / HHI (các thanh ghi này *truy cập được*
   từ non-secure) với vòng chờ power-good **có giới hạn** (vòng của monitor là vô hạn).
2. Set **mailbox** theo nhân (`0x05104da4 + cpu*4`) bằng địa chỉ entry của kernel, và set
   SRAM holding-pen (`0xd901ff84`, `0xd901ff80`) trỏ tới entry secure của monitor
   `0x05100128` — tất cả qua SMC **ghi thanh ghi secure** của monitor (`smc` r0=3).
3. `sev`. Nhân reset vào monitor, monitor đọc mailbox rồi nhảy về non-secure tại
   `secondary_startup` của ta.

Kèm theo việc khai báo `reserved-memory` cho **toàn bộ vùng DRAM mà TEE giữ** (`0x04e00000`–
`0x0e900000`, suy ra từ `/proc/iomem` của Android gốc) — cần cho cả việc mailbox 4-nhân không
bị hỏng *lẫn* sự ổn định chung khi tải nặng.

## Cấu trúc

```
kernel/   0001-meson8b-smp-tz-secure-monitor.patch   # patch platsmp.c (cho v6.1.174)
dtb/      meson8b-m201.dts        # 1 nhân: reserved-memory + tắt các node bị khoá secure
          meson8b-m201-tz.dts     # 4 nhân: + cpus enable-method = "amlogic,meson8b-smp-tz"
scripts/  build-kernel.sh  make-initramfs.sh  build-sd.sh
docs/     STATUS, HISTORY, MILESTONES, PITFALLS, RE-secure-monitor, WIFI, VIDEO-DECODE (song ngữ)
```

## Bắt đầu nhanh

```bash
./scripts/build-kernel.sh            # tải linux 6.1.174, áp patch, cross-build
dtc -I dts -O dtb -o meson8b-m201-tz.dtb dtb/meson8b-m201-tz.dts
./scripts/make-initramfs.sh
./scripts/build-sd.sh /dev/sdX
```

Boot từ u-boot:
```
setenv bootargs 'console=ttyAML0,115200n8 rootwait rw'
fatload mmc 0 0x11000000 uImage; fatload mmc 0 0x12000000 uInitrd; fatload mmc 0 0x10000000 dtb
bootm 0x11000000 0x12000000 0x10000000
```

## Đặc thù phần cứng (đúng máy này)

- SoC Amlogic S805 / Meson8b, Cortex-A5 ×4, 1 GB, board `m8b_m201_1G_tee`, secure boot BẬT.
- Console là **`ttyAML0`** trên mainline (kernel vendor 3.10 gọi là `ttyS0`).
- SD chạy qua controller SDIO (`meson-mx-sdio`); controller của eMMC (`meson8-sdhc`) chưa có
  driver mainline → eMMC không dùng được từ kernel mainline (giữ bootloader đã ký ở eMMC,
  chạy hệ điều hành từ SD).
- Vùng DRAM TEE giữ: `0x04f00000`–`0x0e900000` (≈154 MB), secure-monitor ở `0x05000000`.

## Lưu ý / phạm vi

- Các địa chỉ `0x05100128` / `0x05104da4` / `0xd901ff80` và các offset AO/SCU/HHI là **đặc thù
  cho bản firmware này**. Máy S805 khác có thể khác — hãy lấy lại bằng phương pháp trong
  `docs/RE-secure-monitor.vi.md` (dump monitor qua SMC đọc `r0=2`, rồi disassemble).
- 1 nhân thì chạy ở mọi máy; đường 4 nhân phụ thuộc monitor có expose SMC đọc/ghi secure +
  SMC core (bản VNPT 2018 này có).
- Không kèm firmware độc quyền (bootloader / secure-monitor là của hãng).

## Giấy phép

Patch kernel: GPL-2.0 (dẫn xuất từ `arch/arm/mach-meson/platsmp.c`). Docs/scripts: MIT.
