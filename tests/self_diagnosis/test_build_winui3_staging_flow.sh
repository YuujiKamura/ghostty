#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

cp "$ROOT_DIR/build-winui3.sh" "$TMP_DIR/build-winui3.sh"
chmod +x "$TMP_DIR/build-winui3.sh"

mkdir -p "$TMP_DIR/fake-bin"

cat >"$TMP_DIR/fake-bin/python" <<'EOF'
#!/usr/bin/env bash
case "${LOCK_MODE:-unlocked}" in
  stable)
    [[ "$*" == *"zig-out-winui3/bin/ghostty.exe"* ]] && exit 1
    exit 0
    ;;
  both)
    [[ "$*" == *"zig-out-winui3/bin/ghostty.exe"* ]] && exit 1
    [[ "$*" == *"zig-out-winui3-staging/bin/ghostty.exe"* ]] && exit 1
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
chmod +x "$TMP_DIR/fake-bin/python"

cat >"$TMP_DIR/fake-bin/zig" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
prefix=""
while (($#)); do
  if [[ "$1" == "--prefix" ]]; then
    prefix="$2"
    shift 2
    continue
  fi
  shift
done
mkdir -p "$prefix/bin"
printf 'ghostty' >"$prefix/bin/ghostty.exe"
EOF
chmod +x "$TMP_DIR/fake-bin/zig"

PATH="$TMP_DIR/fake-bin:$PATH"

run_build() {
  (
    cd "$TMP_DIR"
    bash ./build-winui3.sh
  )
}

mkdir -p "$TMP_DIR/zig-out-winui3/bin"
printf 'stable-old' >"$TMP_DIR/zig-out-winui3/bin/ghostty.exe"

LOCK_MODE=stable run_build >/tmp/test_build_winui3_staging_flow.1.log 2>&1

if [[ ! -f "$TMP_DIR/zig-out-winui3-staging/bin/ghostty.exe" ]]; then
  echo "expected staging build output at zig-out-winui3-staging/bin/ghostty.exe"
  exit 1
fi

LOCK_MODE=unlocked run_build >/tmp/test_build_winui3_staging_flow.2.log 2>&1

if [[ ! -f "$TMP_DIR/zig-out-winui3/bin/ghostty.exe" ]]; then
  echo "expected stable build output at zig-out-winui3/bin/ghostty.exe"
  exit 1
fi

if [[ -d "$TMP_DIR/zig-out-winui3-staging" ]]; then
  echo "expected zig-out-winui3-staging to be removed after stable build"
  exit 1
fi

echo "PASS: build-winui3 staging flow"
