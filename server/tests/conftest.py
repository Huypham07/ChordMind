"""Skip ONNX-dependent tests on a clean checkout.

The `.onnx` model files are gitignored (only their sha256 in
`artifacts/onnx/manifest.json` is tracked). Until `python -m scripts.export btc`
has generated them, tests that build an ORT session would hard-error rather
than skip. This guard turns those into skips so `pytest -q` stays green on a
fresh clone.
"""
import os
import pytest

from app.infrastructure.analysis.manifest import load_spec, onnx_path

_ONNX_TESTS = {
    "test_onnx_infer", "test_assemble", "test_parity", "test_analyze_file_endpoint",
}


def pytest_collection_modifyitems(config, items):
    try:
        present = os.path.exists(onnx_path(load_spec("btc")))
    except Exception:
        present = False
    if present:
        return
    skip = pytest.mark.skip(reason="btc.onnx not generated (run: python -m scripts.export btc)")
    for item in items:
        if any(name in item.nodeid for name in _ONNX_TESTS):
            item.add_marker(skip)
