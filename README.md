# fuxi HyperOS 3 GKI kernel

Workspace để xác định đúng KMI của Xiaomi 13 (`fuxi`) và build GKI 5.15 có
SukiSU Ultra + SUSFS.

## Bước 1: thu thập thông tin từ đúng ROM đang chạy

Yêu cầu:

- bootloader đã unlock;
- bật USB debugging;
- `adb devices` hiển thị thiết bị ở trạng thái `device`.

Chạy trên PowerShell:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\collect-fuxi.ps1
```

Kết quả được ghi vào `device-info/fuxi-kernel-info.txt`. Script chỉ đọc thông
tin, không flash hoặc sửa thiết bị.

Nếu `/proc/config.gz` không tồn tại, cần cung cấp thêm `boot.img` lấy từ đúng
gói HyperOS đang cài. Không dùng `boot.img` của region hoặc build khác.

## Vì sao chưa pin source ngay

Xiaomi 13 ra mắt với GKI `android13-5.15`, nhưng số LTS `5.15.x`, KMI và symbol
CRC của kernel HyperOS 3 phải được lấy từ thiết bị/module stock. Chọn một tag
GKI mới chỉ vì cùng phiên bản 5.15 có thể khiến module trong `vendor_dlkm`
không load.

Sau khi có dữ liệu, pipeline sẽ được pin theo thứ tự:

1. release/tag Android Common Kernel khớp KMI stock;
2. revision cụ thể của SukiSU Ultra;
3. revision SUSFS tương thích;
4. config fragment và ABI checks;
5. đóng gói bằng cách giữ nguyên ramdisk/boot parameters của image stock.

## Môi trường build

Android GKI phải được build trên Linux. Máy hiện tại chưa cài WSL, vì vậy có
thể chọn một trong hai:

- WSL2 Ubuntu với dung lượng trống tối thiểu khoảng 40 GB;
- GitHub Actions sau khi workflow đã được pin revision.

Không relock bootloader khi đang dùng kernel hoặc boot image đã sửa.

## GitHub Actions

Workflow `.github/workflows/build-gki.yml` chạy thủ công và build đúng một
target: `android13-5.15.178_r00` với SukiSU Ultra + SUSFS. Các nguồn và GitHub
Actions đều được pin bằng commit. Nhánh SukiSU `builtin` bật KSU và SUSFS bằng
Kconfig mặc định, vì vậy pipeline giữ nguyên `gki_defconfig` chuẩn để vượt qua
kiểm tra reproducibility của Android kernel build.

Runner chuẩn của GitHub cho repository private chỉ có 8 GB RAM. ThinLTO của
kernel này vượt quá cả RAM và swap mặc định, vì vậy pipeline đặt `LTO=none`
theo chế độ được Android kernel build system hỗ trợ. Artifact CI dùng để kiểm
tra tích hợp SukiSU/SUSFS; trước khi flash hằng ngày nên build lại với ThinLTO
và CFI trên máy/self-hosted runner có ít nhất 16 GB RAM để khớp cấu hình stock.

Artifact bao gồm:

- `Image`;
- `.config`;
- `System.map`;
- `Module.symvers`;
- `build-metadata.txt`;
- `SHA256SUMS`.

Workflow chưa tạo hoặc flash `boot.img`; bước đóng gói phải dùng image stock
đúng ROM `OS3.0.308.0.WMCCNXM` sau khi kernel build và ABI checks thành công.

## Thiết bị đã nhận diện

Dữ liệu thu ngày 20/08/2026 từ thiết bị kết nối:

- thiết bị: `fuxi` (`2211133C`);
- ROM: `OS3.0.308.0.WMCCNXM`, Android 16;
- kernel đang chạy: `5.15.178-android13-Wild`;
- base phù hợp để tái tạo trước tiên: `android13-5.15.178_r00`;
- config có `CONFIG_MODVERSIONS=y`, ThinLTO và CFI;
- kernel hiện tại đã có `CONFIG_KSU=y` và `CONFIG_KSU_SUSFS=y`.

Đây là kernel GKI tùy biến `Wild`, không phải kernel stock Xiaomi. Khi dựng bản
SukiSU Ultra mới, phải giữ nguyên thế hệ `android13-5.15` và kiểm tra ABI trước
khi thay kernel đang chạy.
