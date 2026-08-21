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
gồm `Image`, `.config`, `System.map`, `Module.symvers`, metadata và checksum.

Pipeline không đóng gói hoặc flash `boot.img`. Hãy dùng đúng boot image của ROM
đang chạy. Khi dùng Droidspaces cùng SUSFS, phải tắt **Hide SUS mounts for all
processes** trong SUSFS4KSU để container có thể khởi động.
