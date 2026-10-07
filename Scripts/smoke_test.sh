#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINARY="${1:-$ROOT/build/DiskInsight.app/Contents/MacOS/DiskInsight}"
if [[ ! -x "$BINARY" ]]; then
  echo "error: executable not found at $BINARY; build the app first" >&2
  exit 1
fi

FIXTURE="$(mktemp -d "${TMPDIR:-/tmp}/diskinsight-test.XXXXXX")"
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/data/nested" "$FIXTURE/external"
dd if=/dev/zero of="$FIXTURE/data/movie.mp4" bs=1024 count=32 2>/dev/null
dd if=/dev/zero of="$FIXTURE/data/nested/document.pdf" bs=1024 count=8 2>/dev/null
dd if=/dev/zero of="$FIXTURE/external/not-followed.bin" bs=1024 count=16 2>/dev/null
ln -s "$FIXTURE/external" "$FIXTURE/data/link"

"$BINARY" --help | grep -q -- '--scan'
"$BINARY" --scan "$FIXTURE/data" --top=10 --list-unreadable --png="$FIXTURE/treemap.png" > "$FIXTURE/scan.txt"
cat "$FIXTURE/scan.txt"
grep -q '3 files, 1 folders, 0 unreadable, 0 blocked, 0 macOS-protected' "$FIXTURE/scan.txt"
grep -q 'Read failures (showing 0 of 0)' "$FIXTURE/scan.txt"
grep -q 'movie.mp4' "$FIXTURE/scan.txt"
grep -q '\.pdf (1 files)' "$FIXTURE/scan.txt"
if grep -q 'not-followed.bin' "$FIXTURE/scan.txt"; then
  echo "error: scan followed a symbolic link" >&2
  exit 1
fi
test -s "$FIXTURE/treemap.png"
file "$FIXTURE/treemap.png" | grep -q 'PNG image data, 1600 x 900'
if "$BINARY" --scan "$FIXTURE/missing" > "$FIXTURE/error.txt" 2>&1; then
  echo "error: nonexistent scan root unexpectedly succeeded" >&2
  exit 1
fi
echo "Smoke tests passed."
