# Fuxi GKI Kernel

GKI `android13-5.15.178_r00` cho Xiaomi 13 (`fuxi`), build bằng ThinLTO với:

- SukiSU Ultra;
- SUSFS;
- cấu hình và bản vá kABI cho Droidspaces-OSS.

Kernel release được đặt thành:

```text
5.15.178-android13-8-00021-g6f2f96be86b9-ab13729987
```

Chạy workflow **Build Fuxi GKI Kernel** thủ công trong GitHub Actions. Artifact
gồm ZIP AnyKernel3 có thể flash, `Image`, `.config`, metadata và checksum.

Flash file `Fuxi_GKI_5.15.178_SukiSU_SUSFS_Droidspaces_AnyKernel3.zip` bằng
recovery hoặc ứng dụng kernel flasher. Gói chỉ hỗ trợ `fuxi`, tự chọn slot đang
hoạt động và thay `Image` trong boot hiện tại. Nên sao lưu boot của đúng bản ROM
trước khi flash để có thể khôi phục nếu máy không khởi động.

Khi dùng Droidspaces cùng SUSFS, phải tắt **Hide SUS mounts for all processes**
trong SUSFS4KSU để container có thể khởi động.
