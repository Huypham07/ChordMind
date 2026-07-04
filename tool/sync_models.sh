#!/usr/bin/env bash
# Copies the exported ONNX chord models into app/assets/models/ for local
# Flutter builds and tests. The .onnx files are NOT committed to git (too
# large); app/assets/models/manifest.json (small) is committed instead.
#
# Real distribution (Phase 3) will download models per the manifest instead
# of bundling them in assets — this script is a dev/CI convenience until then.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_dir="$repo_root/artifacts/onnx"
dst_dir="$repo_root/app/assets/models"

mkdir -p "$dst_dir"

shopt -s nullglob
onnx_files=("$src_dir"/*.onnx)
if [ ${#onnx_files[@]} -eq 0 ]; then
  echo "error: no .onnx files found in $src_dir" >&2
  exit 1
fi

for f in "${onnx_files[@]}"; do
  cp -v "$f" "$dst_dir/"
done

echo "synced ${#onnx_files[@]} model(s) into $dst_dir"
