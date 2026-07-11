"""Regression gate for the full analysis pipeline.

Re-runs the Python pipeline on the committed deterministic golden clip and
asserts the output still matches the committed snapshot. Catches any drift in
decode/beat-sync/key/assemble across the whole chain.

This is a Python-pipeline regression snapshot, NOT a Dart<->Python parity
check (see tests/fixtures/make_golden.py). Regenerate the golden with:
    python -m tests.fixtures.make_golden
"""
import json
from pathlib import Path

from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.audio_io import decode_pcm
from app.infrastructure.analysis.assemble import analyze_pcm

FIX = Path(__file__).resolve().parents[1] / "fixtures"


def test_pipeline_matches_golden():
    spec = load_spec("btc")
    pcm = decode_pcm(str(FIX / "golden_clip.wav"), spec.fs)
    got = analyze_pcm(pcm, "golden", "Golden", spec)
    exp = json.loads((FIX / "golden_btc.json").read_text())

    assert got["key"] == exp["key"]
    assert abs(got["source"]["bpm"] - exp["source"]["bpm"]) < 0.5

    gc, ec = got["chords"], exp["chords"]
    assert [c["chord"] for c in gc] == [c["chord"] for c in ec]
    for g, e in zip(gc, ec):
        assert abs(g["start"] - e["start"]) <= 0.10
        assert abs(g["end"] - e["end"]) <= 0.10


def test_c_major_triad_reads_as_c_major():
    """Sanity: the C-major-triad golden clip estimates C major end-to-end."""
    spec = load_spec("btc")
    pcm = decode_pcm(str(FIX / "golden_clip.wav"), spec.fs)
    got = analyze_pcm(pcm, "golden", "Golden", spec)
    assert got["key"] == "C major"
