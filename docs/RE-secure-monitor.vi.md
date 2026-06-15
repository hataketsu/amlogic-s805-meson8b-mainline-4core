# Dịch ngược secure monitor Meson8b (khởi động nhân phụ)

Để bật 4 nhân cần hiểu firmware secure monitor khởi động nhân phụ thế nào. Monitor mã hoá AES trên đĩa nên không đọc tĩnh được. Mẹo: nó **thường trú ở DRAM `0x05000000`** mỗi lần boot (do bootloader đã ký nạp, không phụ thuộc OS) và expose **SMC đọc thanh ghi secure**, nên ta bảo nó tự đọc code của chính nó ra.

## SMC ABI (ARMv7 `smc #0`)

| r0 | nghĩa | tham số |
|----|-------|---------|
| 2  | đọc địa chỉ/thanh ghi secure | r1 = phys → trả về ở r0 |
| 3  | ghi địa chỉ/thanh ghi secure | r1 = phys, r2 = giá trị |
| 4  | lệnh monitor | r1 = cmd id, r2/r3 = tham số |

`r0=4, r1=0x701/0x702` trả base/size secure-mem. `r0=2` đọc DRAM secure bất kỳ → vòng lặp gọi `smc(2, addr)` trong kernel dump toàn bộ monitor.

## Dispatch SMC (~`0x05135164`)

Handler `r0=4` rẽ theo `(cmd & 0xf00)`: `0x200` → CORE handler `0x5134e84` (bảng nhảy `0x201..0x20a`; `0x207` = set boot-addr). `0x700` → thông tin MEM.

## `0x207` + routine bật nguồn `0x513627c`

`0x207`(cpu, addr): kiểm tra cpu 1–3, lưu mailbox `0x05104da4 + cpu*4`, gọi routine `0x513627c`, rồi lưu địa chỉ entry vào mailbox.

`0x513627c` tác động: SCU `0xc4300008`; AO `0xc81000e0/e4/f4`; HHI reset `0xc110419c`; SRAM `0xd901ff84(+)` & `0xd901ff80`; entry secure của monitor `0x05100128`. Trình tự: bật nguồn SCU → AO CNTL0 → reset assert → MEM_PD0 → CNTL1 → **chờ power-good (VÒNG VÔ HẠN)** → tắt isolation → SRAM boot-addr = `0x05100128` → reset deassert → SRAM ctrl `|=(1<<cpu)|1` → `sev`.

## Vì sao upstream fail và `0x207` treo

- Upstream ghi thẳng SRAM/SCU. SRAM **secure** → đọc = abort, ghi = bị bỏ.
- Gọi `0x207` treo vì **vòng chờ power-good (bước 6) không bao giờ xong** trong ngữ cảnh boot của ta — monitor quay mãi nên `smc` không trả về.

## Cách sửa

Mô phỏng `0x513627c` trong kernel non-secure: ghi AO/SCU/HHI **trực tiếp qua `ioremap`** (các reg này truy cập được từ non-secure); thay vòng chờ vô hạn bằng **vòng có giới hạn**; làm phần **secure** (mailbox `0x05104da4`, SRAM `0xd901ff84/80`) qua `smc` r0=3; `sev`. Nhân reset vào `0x05100128`, đọc mailbox, nhảy về non-secure tại `secondary_startup` của ta.

Hằng số quan trọng: `meson_smc1` dùng `mov r0,#4`; monitor **phá r2–r12** qua SMC (wrapper hãng lưu `{r2-ip,lr}`) → inline-asm phải clobber `r4–r12/lr`.
