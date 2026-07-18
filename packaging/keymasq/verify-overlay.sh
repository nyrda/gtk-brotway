#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/../.." && pwd)"
architecture="$(uname -m)"
artifact="${1:-$repo_root/dist/gtk4-brotway-keymasq-$architecture.tar.zst}"

if [[ ! -f "$artifact" ]]; then
  echo "Bundle not found: $artifact" >&2
  exit 2
fi

verify_root="$(mktemp -d)"
launcher_pid=""
cleanup() {
  if [[ -n "$launcher_pid" ]]; then
    kill "$launcher_pid" 2>/dev/null || true
    wait "$launcher_pid" 2>/dev/null || true
  fi
  rm -rf -- "$verify_root"
}
trap cleanup EXIT INT TERM

while IFS= read -r member; do
  case "$member" in
    /*|../*|*/../*) echo "Unsafe archive member: $member" >&2; exit 1 ;;
  esac
done < <(tar --list --file "$artifact")

tar --extract --file "$artifact" --directory "$verify_root"
private_dir="$verify_root/lib/gtk4-brotway"
required=(
  "$private_dir/libgtk-4.so"
  "$private_dir/libgtk-4.so.1"
  "$private_dir/gtk4-broadwayd"
  "$private_dir/gtk4-brotway-run"
  "$private_dir/gtk4-brotway-debugmenu"
  "$verify_root/share/licenses/gtk4-brotway/COPYING"
  "$verify_root/manifest.json"
)
for path in "${required[@]}"; do
  [[ -e "$path" ]] || { echo "Missing bundle member: $path" >&2; exit 1; }
done
[[ "$(readlink -- "$private_dir/libgtk-4.so")" == libgtk-4.so.1 ]]
gtk_real_name="$(readlink -- "$private_dir/libgtk-4.so.1")"
[[ "$gtk_real_name" == libgtk-4.so.1.* ]]
[[ -f "$private_dir/$gtk_real_name" ]]

python - "$verify_root/manifest.json" "$architecture" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
assert manifest["format"] == 1
assert manifest["architecture"] == sys.argv[2]
assert len(manifest["source"]["commit"]) == 40
assert len(manifest["source"]["archive_sha256"]) == 64
assert manifest["runtime"]["private_prefix"] == "lib/gtk4-brotway"
assert manifest["runtime"]["prefix_environment"] == "BROTWAY_PREFIX"
PY

readelf --dynamic "$private_dir/libgtk-4.so.1" | grep -Fq 'Library soname: [libgtk-4.so.1]'
for executable in \
  "$private_dir/libgtk-4.so.1" \
  "$private_dir/gtk4-broadwayd" \
  "$private_dir/gtk4-brotway-run" \
  "$private_dir/gtk4-brotway-debugmenu"; do
  if LD_LIBRARY_PATH="$private_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
      ldd "$executable" | grep -Fq 'not found'; then
    echo "Unresolved dynamic dependency in $executable" >&2
    LD_LIBRARY_PATH="$private_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
      ldd "$executable" >&2
    exit 1
  fi
done

env -u BROTWAY_PREFIX "$private_dir/gtk4-brotway-run" --help \
  | grep -Fq 'Run a GTK4 app over the brotway Broadway backend'

runtime_dir="$verify_root/runtime"
mkdir -m700 -- "$runtime_dir"
port="${BROTWAY_VERIFY_PORT:-18095}"
log="$verify_root/brotway.log"
loader="$(readelf --program-headers "$private_dir/gtk4-broadwayd" \
  | sed -n 's/.*interpreter: \([^]]*\).*/\1/p')"
[[ -x "$loader" ]] || { echo "ELF loader not found: $loader" >&2; exit 1; }
XDG_RUNTIME_DIR="$runtime_dir" \
  BROTWAY_LOADER="$loader" \
  BROTWAY_LIBRARY_PATH="$private_dir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
  "$private_dir/gtk4-brotway-run" --display :95 --port "$port" >"$log" 2>&1 &
launcher_pid=$!

ready=0
for _ in {1..100}; do
  if ! kill -0 "$launcher_pid" 2>/dev/null; then
    cat "$log" >&2
    echo "gtk4-brotway-run exited before its HTTP endpoint was ready" >&2
    exit 1
  fi
  if curl --fail --silent "http://127.0.0.1:$port/" >/dev/null; then
    ready=1
    break
  fi
  sleep 0.1
done
if [[ "$ready" != 1 ]]; then
  cat "$log" >&2
  echo "Broadway HTTP endpoint did not become ready" >&2
  exit 1
fi

kill "$launcher_pid"
status=0
wait "$launcher_pid" || status=$?
launcher_pid=""
if [[ "$status" != 143 ]]; then
  echo "Unexpected launcher termination status: $status" >&2
  exit 1
fi
printf 'Verified %s\n' "$artifact"
