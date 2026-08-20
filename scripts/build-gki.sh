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

readonly SUSFS_REPO="https://gitlab.com/simonpunk/susfs4ksu.git"
readonly SUSFS_BRANCH="gki-android13-5.15"
readonly SUSFS_COMMIT="068fff681035d5447f6107a3c63c2e4e23cb735f"

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

# GitHub-hosted private-repository runners have limited RAM. Keep ThinLTO
# enabled for GKI/CFI compatibility, but serialize its backend workers to
# avoid the linker being killed at its peak memory usage.
cat >> common/Makefile <<'MAKEFILE'

ifdef CONFIG_LTO_CLANG_THIN
KBUILD_LDFLAGS += --thinlto-jobs=1
endif
MAKEFILE

export KBUILD_BUILD_USER="build-user"
export KBUILD_BUILD_HOST="build-host"
export BUILD_CONFIG="common/build.config.gki.aarch64"

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

cp "$image_path" "${DIST_DIR}/Image"

for artifact_name in System.map Module.symvers .config; do
  artifact_path="$(find out -type f -name "$artifact_name" -print -quit || true)"
  if [[ -n "$artifact_path" ]]; then
    cp "$artifact_path" "${DIST_DIR}/${artifact_name}"
  fi
done

cat > "${DIST_DIR}/build-metadata.txt" <<METADATA
manifest=${MANIFEST_URL}
manifest_branch=${MANIFEST_BRANCH}
gki_tag=${GKI_TAG}
gki_commit=${GKI_COMMIT}
sukisu_repo=${SUKISU_REPO}
sukisu_branch=${SUKISU_BRANCH}
sukisu_commit=${SUKISU_COMMIT}
susfs_repo=${SUSFS_REPO}
susfs_branch=${SUSFS_BRANCH}
susfs_commit=${SUSFS_COMMIT}
build_config=${BUILD_CONFIG}
METADATA

(
  cd "$DIST_DIR"
  sha256sum Image System.map Module.symvers .config build-metadata.txt 2>/dev/null \
    > SHA256SUMS
)

echo "Build artifacts written to ${DIST_DIR}"
