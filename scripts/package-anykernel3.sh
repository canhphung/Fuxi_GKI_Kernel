#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <Image> <output-directory>" >&2
  exit 2
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE_PATH="$(realpath "$1")"
OUTPUT_DIR="$(mkdir -p "$2" && cd "$2" && pwd)"

readonly ANYKERNEL_REPO="https://github.com/osm0sis/AnyKernel3.git"
readonly ANYKERNEL_COMMIT="e4b1bb25ca2aabcfd57f694a5998d87130701b71"
readonly ZIP_NAME="Fuxi_GKI_5.15.178_SukiSU_SUSFS_Droidspaces_AnyKernel3.zip"

for command_name in git zip unzip realpath; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "Missing required command: $command_name" >&2
    exit 1
  }
done
test -s "$IMAGE_PATH"

package_dir="$(mktemp -d)"
trap 'rm -rf "$package_dir"' EXIT

git -C "$package_dir" init
git -C "$package_dir" remote add origin "$ANYKERNEL_REPO"
git -C "$package_dir" fetch --depth=1 origin "$ANYKERNEL_COMMIT"
git -C "$package_dir" checkout --detach FETCH_HEAD
test "$(git -C "$package_dir" rev-parse HEAD)" = "$ANYKERNEL_COMMIT"

rm -rf \
  "$package_dir/.git" \
  "$package_dir/.github" \
  "$package_dir/README.md"
find "$package_dir" -type f -name placeholder -delete

install -m 0755 "$PROJECT_ROOT/anykernel/anykernel.sh" \
  "$package_dir/anykernel.sh"
install -m 0644 "$IMAGE_PATH" "$package_dir/Image"

zip_path="$OUTPUT_DIR/$ZIP_NAME"
rm -f "$zip_path"
(
  cd "$package_dir"
  zip -r9 "$zip_path" .
)

unzip -t "$zip_path"
zip_entries="$(unzip -Z1 "$zip_path")"
for required_entry in anykernel.sh Image LICENSE META-INF/com/google/android/update-binary tools/ak3-core.sh; do
  grep -Fqx "$required_entry" <<< "$zip_entries"
done

echo "AnyKernel3 package written to $zip_path"
