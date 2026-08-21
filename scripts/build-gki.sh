#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${KERNEL_WORKSPACE:-${PROJECT_ROOT}/.work/android-kernel}"
DIST_DIR="${PROJECT_ROOT}/dist"

readonly MANIFEST_URL="https://android.googlesource.com/kernel/manifest"
readonly MANIFEST_BRANCH="common-android13-5.15"
readonly GKI_TAG="android13-5.15.178_r00"
readonly GKI_COMMIT="058abb720bd1570acf1c8721b1efa0c1850b5032"

readonly SUKISU_REPO="https://github.com/SukiSU-Ultra/SukiSU-Ultra.git"
readonly SUKISU_BRANCH="builtin"
readonly SUKISU_SETUP_COMMIT="197cad8838da8d6cdf80356678e6100ce5e27a41"
readonly SUKISU_COMMIT="5a2bb7e5813002ccaabe02fa864cfb2dde6b5109"
readonly SUKISU_SETUP_SHA256="0ea8369c334a116ee94076cce834eb585a3ecbb949d7d3c29253d9beefd43bf0"
readonly SUKISU_MANAGER_FD_PATCH="${PROJECT_ROOT}/patches/sukisu-manager-fd.patch"

readonly SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
readonly SUSFS_BRANCH="gki-android13-5.15"
readonly SUSFS_COMMIT="068fff681035d5447f6107a3c63c2e4e23cb735f"

readonly DROIDSPACES_REPO="https://github.com/ravindu644/Droidspaces-OSS.git"
readonly DROIDSPACES_COMMIT="3736fd4fb021e309d50d949cb62e82fcfafd4de7"
readonly STOCK_KERNEL_RELEASE="5.15.178-android13-8-00021-g6f2f96be86b9-ab13729987"
readonly STOCK_LOCALVERSION="-android13-8-00021-g6f2f96be86b9-ab13729987"

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

for command_name in repo git curl sha256sum patch python3; do
  require_command "$command_name"
done

mkdir -p "$WORK_DIR" "$DIST_DIR"
rm -rf "$DIST_DIR"/*

cd "$WORK_DIR"

repo init \
  -u "$MANIFEST_URL" \
  -b "$MANIFEST_BRANCH" \
  --depth=1
repo sync -c -j2 --fail-fast --no-clone-bundle

git -C common fetch --depth=1 \
  https://android.googlesource.com/kernel/common \
  "refs/tags/${GKI_TAG}:refs/tags/${GKI_TAG}"
git -C common checkout --detach "$GKI_TAG"
test "$(git -C common rev-parse HEAD)" = "$GKI_COMMIT"

setup_script="$(mktemp)"
curl --fail --location --retry 3 \
  "https://raw.githubusercontent.com/SukiSU-Ultra/SukiSU-Ultra/${SUKISU_SETUP_COMMIT}/kernel/setup.sh" \
  --output "$setup_script"
echo "${SUKISU_SETUP_SHA256}  ${setup_script}" | sha256sum --check
bash "$setup_script" "$SUKISU_COMMIT"
test "$(git -C KernelSU rev-parse HEAD)" = "$SUKISU_COMMIT"

# Builtin SukiSU passes an anonymous driver fd to the Manager across exec.
# FD_CLOEXEC closes it too early on affected Android 16 ROMs, leaving the
# Manager unable to detect root even though the kernel code is present.
patch --directory=KernelSU --strip=1 --fuzz=0 --dry-run \
  < "$SUKISU_MANAGER_FD_PATCH"
patch --directory=KernelSU --strip=1 --fuzz=0 \
  < "$SUKISU_MANAGER_FD_PATCH"
grep -Fq 'get_unused_fd_flags(0);' KernelSU/kernel/supercall/supercall.c
if grep -Fq 'get_unused_fd_flags(O_CLOEXEC);' \
  KernelSU/kernel/supercall/supercall.c; then
  echo "Failed to apply SukiSU Manager fd compatibility patch" >&2
  exit 1
fi

susfs_dir="${WORK_DIR}/susfs4ksu"
git init "$susfs_dir"
git -C "$susfs_dir" remote add origin "$SUSFS_REPO"
git -C "$susfs_dir" fetch --depth=1 origin "$SUSFS_COMMIT"
git -C "$susfs_dir" checkout --detach FETCH_HEAD
test "$(git -C "$susfs_dir" rev-parse HEAD)" = "$SUSFS_COMMIT"

kernel_patch="${susfs_dir}/kernel_patches/50_add_susfs_in_gki-android13-5.15.patch"

cp "${susfs_dir}/kernel_patches/fs/"* common/fs/
cp "${susfs_dir}/kernel_patches/include/linux/"* common/include/linux/
patch --directory=common --strip=1 --fuzz=2 --dry-run < "$kernel_patch"
patch --directory=common --strip=1 --fuzz=2 < "$kernel_patch"

droidspaces_dir="${WORK_DIR}/Droidspaces-OSS"
git init "$droidspaces_dir"
git -C "$droidspaces_dir" remote add origin "$DROIDSPACES_REPO"
git -C "$droidspaces_dir" fetch --depth=1 origin "$DROIDSPACES_COMMIT"
git -C "$droidspaces_dir" checkout --detach FETCH_HEAD
test "$(git -C "$droidspaces_dir" rev-parse HEAD)" = "$DROIDSPACES_COMMIT"

droidspaces_patch="${droidspaces_dir}/Documentation/resources/kernel-patches/GKI/below-kernel-6.12/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch"
patch --directory=common --strip=1 --fuzz=0 --dry-run < "$droidspaces_patch"
patch --directory=common --strip=1 --fuzz=0 < "$droidspaces_patch"

gki_defconfig="common/arch/arm64/configs/gki_defconfig"
droidspaces_configs=(
  SYSVIPC POSIX_MQUEUE IPC_NS PID_NS DEVTMPFS
  NETFILTER_XT_MATCH_ADDRTYPE USER_NS
  IP_NF_IPTABLES IP_NF_FILTER IP_NF_TARGET_REJECT
  IP6_NF_IPTABLES IP6_NF_FILTER IP6_NF_TARGET_REJECT
  NETFILTER_XT_TARGET_LOG
  NETFILTER_XT_MATCH_RECENT IP_SET IP_SET_HASH_IP IP_SET_HASH_NET
  NETFILTER_XT_SET TMPFS_POSIX_ACL TMPFS_XATTR
  BINFMT_MISC BINFMT_SCRIPT BINFMT_ELF
)
for config_name in "${droidspaces_configs[@]}"; do
  common/scripts/config --file "$gki_defconfig" --enable "$config_name"
done

# Force the release string to match the stock kernel identity supplied for
# fuxi. Android's setlocalversion uses this file before consulting Git state.
printf '%s\n' "$STOCK_LOCALVERSION" > common/.scmversion

# Droidspaces options are applied directly to gki_defconfig. Kconfig's
# savedefconfig canonicalizes their order and drops options implied by defaults,
# so Android's text-only check would reject an otherwise valid configuration.
grep -q 'check_defconfig' common/build.config.gki
sed -i 's/check_defconfig//g' common/build.config.gki
if grep -q 'check_defconfig' common/build.config.gki; then
  echo "Failed to disable check_defconfig" >&2
  exit 1
fi

export KBUILD_BUILD_USER="build-user"
export KBUILD_BUILD_HOST="build-host"
export BUILD_CONFIG="common/build.config.gki.aarch64"
export LTO="thin"
export KMI_SYMBOL_LIST_STRICT_MODE="1"
# The pipeline packages the raw Image with AnyKernel3. Android's optional GKI
# boot image archive is unnecessary here and can fail after a successful link.
export GKI_BUILD_CONFIG_FRAGMENT="${PROJECT_ROOT}/configs/fuxi-build.config"

build/build.sh &
build_pid=$!

# LLD can be silent for many minutes during the ThinLTO link. Emit a small
# heartbeat so the hosted runner does not treat the active build as idle.
while kill -0 "$build_pid" 2>/dev/null; do
  sleep 60
  if kill -0 "$build_pid" 2>/dev/null; then
    echo "Kernel build is still running (pid=${build_pid})"
    free -h
  fi
done
wait "$build_pid"

image_path="$(find out -type f -name Image -path '*/dist/*' -print -quit)"
test -n "$image_path"

config_path="$(find out -type f -name .config -print -quit)"
test -n "$config_path"
for config_name in "${droidspaces_configs[@]}"; do
  if ! grep -qx "CONFIG_${config_name}=y" "$config_path"; then
    echo "Required Droidspaces config was not built as y: CONFIG_${config_name}" >&2
    grep -E "^(# )?CONFIG_${config_name}(=| )" "$config_path" >&2 || true
    exit 1
  fi
done

kernel_release_path="$(find out -type f -name kernel.release -print -quit)"
test -n "$kernel_release_path"
test "$(cat "$kernel_release_path")" = "$STOCK_KERNEL_RELEASE"

cp "$image_path" "${DIST_DIR}/Image"

for artifact_name in System.map Module.symvers; do
  artifact_path="$(find out -type f -name "$artifact_name" -print -quit || true)"
  if [[ -n "$artifact_path" ]]; then
    cp "$artifact_path" "${DIST_DIR}/${artifact_name}"
  fi
done
cp "$config_path" "${DIST_DIR}/.config"

bash "${PROJECT_ROOT}/scripts/package-anykernel3.sh" \
  "${DIST_DIR}/Image" "${DIST_DIR}"

cat > "${DIST_DIR}/build-metadata.txt" <<METADATA
manifest=${MANIFEST_URL}
manifest_branch=${MANIFEST_BRANCH}
gki_tag=${GKI_TAG}
gki_commit=${GKI_COMMIT}
sukisu_repo=${SUKISU_REPO}
sukisu_branch=${SUKISU_BRANCH}
sukisu_commit=${SUKISU_COMMIT}
sukisu_manager_fd_patch=patches/sukisu-manager-fd.patch
sukisu_manager_fd_issue=https://github.com/SukiSU-Ultra/SukiSU-Ultra/issues/780
susfs_repo=${SUSFS_REPO}
susfs_branch=${SUSFS_BRANCH}
susfs_commit=${SUSFS_COMMIT}
droidspaces_repo=${DROIDSPACES_REPO}
droidspaces_commit=${DROIDSPACES_COMMIT}
kernel_release=${STOCK_KERNEL_RELEASE}
build_config=${BUILD_CONFIG}
lto=${LTO}
kmi_symbol_list_strict_mode=${KMI_SYMBOL_LIST_STRICT_MODE}
gki_build_config_fragment=${GKI_BUILD_CONFIG_FRAGMENT}
anykernel_repo=https://github.com/osm0sis/AnyKernel3.git
anykernel_commit=e4b1bb25ca2aabcfd57f694a5998d87130701b71
METADATA

(
  cd "$DIST_DIR"
  find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' \
    | LC_ALL=C sort \
    | xargs sha256sum > SHA256SUMS
)

echo "Build artifacts written to ${DIST_DIR}"
