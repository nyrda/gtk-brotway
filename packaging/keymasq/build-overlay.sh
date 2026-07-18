#!/usr/bin/env bash
set -euo pipefail

# This bundle is intentionally built against current Arch Linux. Keymasq later
# collects the dynamic dependency closure into the AppImage from the same image.
readonly SOURCE_REPOSITORY="https://github.com/nyrda/gtk-brotway"
readonly SOURCE_COMMIT="8d204d09eca8613ee0bd59786a29935b5917f188"
readonly UPSTREAM_TAG="4.22.4-3.2.0"
readonly SOURCE_ARCHIVE_SHA256="d8c014748930fb787a94804e9bf153c9b61335f5ab580860ad833ad790ff1891"
readonly SOURCE_DATE_EPOCH="1784334137"

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
architecture="$(uname -m)"
case "$architecture" in
  x86_64|aarch64) ;;
  *) echo "Unsupported architecture: $architecture" >&2; exit 2 ;;
esac

build_root="${BROTWAY_BUILD_ROOT:-$repo_root/_build/keymasq-overlay-$architecture}"
output_dir="${BROTWAY_OUTPUT_DIR:-$repo_root/dist}"
artifact="$output_dir/gtk4-brotway-keymasq-$architecture.tar.zst"
source_archive="$build_root/source.tar.gz"
source_dir="$build_root/source"
meson_build="$build_root/meson"
stage="$build_root/stage"

case "$build_root" in
  "$repo_root"/_build/keymasq-overlay-*) ;;
  *) echo "BROTWAY_BUILD_ROOT must be below $repo_root/_build/keymasq-overlay-*" >&2; exit 2 ;;
esac

rm -rf -- "$build_root"
mkdir -p -- "$build_root" "$output_dir"

curl --fail --location --retry 3 --output "$source_archive" \
  "$SOURCE_REPOSITORY/archive/$SOURCE_COMMIT.tar.gz"
printf '%s  %s\n' "$SOURCE_ARCHIVE_SHA256" "$source_archive" | sha256sum --check --strict

mkdir -p -- "$source_dir"
tar -xzf "$source_archive" --strip-components=1 -C "$source_dir"
patch --directory="$source_dir" --strip=1 < "$script_dir/gtk-brotway-run-relocatable.patch"

meson setup "$meson_build" "$source_dir" \
  --buildtype=release \
  -Dbroadway-backend=true \
  -Dx11-backend=false \
  -Dwayland-backend=false \
  -Dwin32-backend=false \
  -Dmacos-backend=false \
  -Dvulkan=disabled \
  -Dintrospection=disabled \
  -Ddocumentation=false \
  -Dman-pages=false \
  -Dbuild-testsuite=false \
  -Dbuild-tests=false \
  -Dbuild-examples=false \
  -Dbuild-demos=false \
  -Dmedia-gstreamer=disabled \
  -Dprint-cups=disabled
meson compile -C "$meson_build"

private_dir="$stage/lib/gtk4-brotway"
license_dir="$stage/share/licenses/gtk4-brotway"
mkdir -p -- "$private_dir" "$license_dir"

gtk_real="$(readlink -f -- "$meson_build/gtk/libgtk-4.so.1")"
gtk_name="$(basename -- "$gtk_real")"
install -m755 -- "$gtk_real" "$private_dir/$gtk_name"
ln -s -- "$gtk_name" "$private_dir/libgtk-4.so.1"
ln -s -- libgtk-4.so.1 "$private_dir/libgtk-4.so"
install -m755 -- "$meson_build/gdk/broadway/gtk4-broadwayd" "$private_dir/gtk4-broadwayd"
install -m755 -- "$meson_build/tools/gtk4-brotway-run" "$private_dir/gtk4-brotway-run"
install -m755 -- "$meson_build/tools/gtk4-brotway-debugmenu" "$private_dir/gtk4-brotway-debugmenu"
install -m644 -- "$source_dir/COPYING" "$license_dir/COPYING"

export SOURCE_REPOSITORY SOURCE_COMMIT UPSTREAM_TAG SOURCE_ARCHIVE_SHA256 SOURCE_DATE_EPOCH
export BROTWAY_MANIFEST_ARCHITECTURE="$architecture"
export BROTWAY_MANIFEST_OUTPUT="$stage/manifest.json"
python - <<'PY'
import json
import os
import platform
import subprocess

packages = [
    "base-devel", "meson", "ninja", "glib2", "glib2-devel", "cairo", "pango",
    "gdk-pixbuf2", "graphene", "libepoxy", "fribidi", "harfbuzz",
    "libxkbcommon", "libjpeg-turbo", "libpng", "libtiff", "libdrm",
]
versions = {}
for package in packages:
    query = subprocess.run(
        ["pacman", "-Q", package], text=True, capture_output=True, check=False
    )
    if query.returncode == 0:
        name, version = query.stdout.strip().split(maxsplit=1)
        versions[name] = version

manifest = {
    "format": 1,
    "purpose": "Keymasq AppImage private GTK Broadway overlay",
    "architecture": os.environ["BROTWAY_MANIFEST_ARCHITECTURE"],
    "source": {
        "repository": os.environ["SOURCE_REPOSITORY"],
        "upstream_tag": os.environ["UPSTREAM_TAG"],
        "commit": os.environ["SOURCE_COMMIT"],
        "archive_sha256": os.environ["SOURCE_ARCHIVE_SHA256"],
    },
    "build": {
        "distribution": "Arch Linux",
        "kernel_machine": platform.machine(),
        "source_date_epoch": int(os.environ["SOURCE_DATE_EPOCH"]),
        "package_versions": versions,
    },
    "runtime": {
        "private_prefix": "lib/gtk4-brotway",
        "prefix_environment": "BROTWAY_PREFIX",
        "gtk_soname": "libgtk-4.so.1",
    },
}
with open(os.environ["BROTWAY_MANIFEST_OUTPUT"], "w", encoding="utf-8") as output:
    json.dump(manifest, output, indent=2, sort_keys=True)
    output.write("\n")
PY

find "$stage" -exec touch --date="@$SOURCE_DATE_EPOCH" {} +
tar --create --directory="$stage" --sort=name --mtime="@$SOURCE_DATE_EPOCH" \
  --owner=0 --group=0 --numeric-owner --format=posix \
  --pax-option=delete=atime,delete=ctime \
  --use-compress-program='zstd -19 -T0' --file="$artifact" .

"$script_dir/verify-overlay.sh" "$artifact"
(cd -- "$output_dir" && sha256sum "$(basename -- "$artifact")" \
  > "$(basename -- "$artifact").sha256")
cat "$artifact.sha256"
printf 'Built %s\n' "$artifact"
