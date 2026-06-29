#!/usr/bin/env python3
"""Tải các dataset cho ChordMind.

- Phần tự động: dataset có URL trực tiếp ổn định (FMA small/medium, MAESTRO).
- Phần qua thư viện: MuQ (HuggingFace, auto khi load), mirdata cho eval sets.
- Phần thủ công: audio bản quyền — chỉ in hướng dẫn.

Dùng:
    python scripts/download_datasets.py --list
    python scripts/download_datasets.py fma_small maestro
    python scripts/download_datasets.py --manual      # in hướng dẫn tự tải

# ponytail: chỉ tự tải các nguồn có URL trực tiếp ổn định; còn lại in hướng
# dẫn. Thêm nguồn mới = thêm 1 entry vào AUTO/LIB/MANUAL.
"""
from __future__ import annotations

import argparse
import sys
import urllib.request
from pathlib import Path

# ponytail: console Windows mặc định cp1252, ép UTF-8 để in được tiếng Việt.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

DATA_DIR = Path(__file__).resolve().parent.parent / "data" / "downloads"

# name -> (url, mô tả). Các URL trực tiếp, ổn định.
AUTO: dict[str, tuple[str, str]] = {
    "fma_small": (
        "https://os.unil.cloud.switch.ch/fma/fma_small.zip",
        "FMA small ~8GB, 8000 track 30s — pseudo-label/beat",
    ),
    "fma_medium": (
        "https://os.unil.cloud.switch.ch/fma/fma_medium.zip",
        "FMA medium ~22GB, 25000 track 30s",
    ),
    "fma_metadata": (
        "https://os.unil.cloud.switch.ch/fma/fma_metadata.zip",
        "FMA metadata (nhỏ, cần cho mọi FMA)",
    ),
    "maestro": (
        "https://storage.googleapis.com/magentadata/datasets/maestro/v3.0.0/maestro-v3.0.0.zip",
        "MAESTRO v3 ~120GB (audio+MIDI piano) — pseudo-label",
    ),
    "lakh_midi": (
        "http://hog.ee.columbia.edu/craffel/lmd/lmd_full.tar.gz",
        "Lakh MIDI full ~1.6GB — accompaniment (bước 8)",
    ),
}

# Dataset lấy qua thư viện Python (không tải bằng URL trực tiếp).
LIB: dict[str, str] = {
    "muq": "pip install muq; tự tải khi MuQ.from_pretrained('OpenMuQ/MuQ-large-msd-iter')",
    "ballroom/gtzan/hainsworth": "pip install mirdata; mirdata.initialize('<name>').download() — eval beat",
    "salami": "pip install mirdata; mirdata.initialize('salami').download() — eval segmentation",
    "hooktheory": "HuggingFace datasets / Hooktheory API — re-harmonization",
    "chordonomicon": "HuggingFace datasets ('Chordonomicon') — re-harmonization",
}

# Audio bản quyền — chỉ có nhãn, phải tự tải audio.
MANUAL: dict[str, str] = {
    "isophonics": "Nhãn: isophonics.net/datasets | Audio: tự tìm bản gốc",
    "billboard": "Nhãn: ddmal.music.mcgill.ca/research/billboard | Audio: tự tìm",
    "rwc_pop": "Đăng ký license: staff.aist.go.jp/m.goto/RWC-MDB",
    "uspop2002": "Nhãn: github.com/tmc323/Chord-Annotations | Audio: tự tìm",
    "dali": "Metadata+nhãn: github.com/gabolsgabs/DALI | Audio: crawl theo link YouTube trong metadata",
}


def _download(name: str, url: str) -> None:
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    dest = DATA_DIR / url.split("/")[-1]
    if dest.exists():
        print(f"[skip] {name}: đã có {dest}")
        return
    print(f"[tải ] {name}: {url}\n   -> {dest}")

    def _progress(block: int, bsize: int, total: int) -> None:
        if total > 0:
            pct = min(100, block * bsize * 100 // total)
            print(f"\r   {pct}%", end="", flush=True)

    urllib.request.urlretrieve(url, dest, _progress)  # noqa: S310 (URL tin cậy)
    print(f"\r[xong] {name}")


def print_list() -> None:
    print("== Tải tự động (URL trực tiếp) ==")
    for n, (_, d) in AUTO.items():
        print(f"  {n:14} {d}")
    print("\n== Qua thư viện Python ==")
    for n, d in LIB.items():
        print(f"  {n:14} {d}")
    print("\n== Tự tải thủ công (audio bản quyền) — dùng --manual ==")
    for n in MANUAL:
        print(f"  {n}")


def print_manual() -> None:
    print("== Dataset phải tự xin/tự tải (chỉ có nhãn, audio bản quyền) ==")
    for n, d in MANUAL.items():
        print(f"  - {n}: {d}")
    print("\nGhi chú: chiến lược paper là dùng pseudo-label trên FMA/DALI/MAESTRO")
    print("để giảm phụ thuộc audio bản quyền.")


def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Tải dataset cho ChordMind")
    p.add_argument("datasets", nargs="*", help=f"tên cần tải: {', '.join(AUTO)} | all")
    p.add_argument("--list", action="store_true", help="liệt kê tất cả")
    p.add_argument("--manual", action="store_true", help="in hướng dẫn tự tải")
    args = p.parse_args(argv)

    if args.list:
        print_list()
        return 0
    if args.manual:
        print_manual()
        return 0
    if not args.datasets:
        p.print_help()
        return 1

    targets = list(AUTO) if "all" in args.datasets else args.datasets
    for name in targets:
        if name in AUTO:
            _download(name, AUTO[name][0])
        elif name in LIB:
            print(f"[lib ] {name}: {LIB[name]}")
        elif name in MANUAL:
            print(f"[thủ công] {name}: {MANUAL[name]}")
        else:
            print(f"[?] không biết '{name}'. Dùng --list để xem danh sách.")
    return 0


def _selfcheck() -> None:
    # ponytail: kiểm tra phân loại không trùng tên + URL hợp lệ.
    names = list(AUTO) + list(LIB) + list(MANUAL)
    assert len(names) == len(set(names)), "tên dataset bị trùng giữa các nhóm"
    assert all(u.startswith("http") for u, _ in AUTO.values()), "URL AUTO phải là http(s)"
    print("selfcheck OK")


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selfcheck":
        _selfcheck()
    else:
        raise SystemExit(main(sys.argv[1:]))
