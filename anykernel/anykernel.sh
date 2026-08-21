#!/sbin/sh
# AnyKernel3 Ramdisk Mod Script
# https://github.com/osm0sis/AnyKernel3

properties() { '
kernel.string=Fuxi GKI 5.15.178 - SukiSU Ultra + SUSFS + Droidspaces
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=fuxi
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; }

# Xiaomi 13 is an A/B device. The kernel lives in the active boot partition;
# the Android 13+ first-stage ramdisk is stored separately in init_boot.
BLOCK=boot;
IS_SLOT_DEVICE=1;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

. tools/ak3-core.sh;

# Replace only the kernel while retaining the existing boot image metadata.
split_boot;
flash_boot;
