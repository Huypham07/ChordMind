import numpy as np
from app.infrastructure.analysis.manifest import load_spec
from app.infrastructure.analysis.assemble import analyze_pcm

def test_analyze_pcm_shape():
    spec = load_spec("btc")
    pcm = np.zeros(spec.window_samples, dtype="float32")
    res = analyze_pcm(pcm, "abc", "Test", spec)
    assert set(res) >= {"songId","source","key","beats","downbeats","chords","synchronizedChords","segments","melody"}
    assert res["source"]["timeSignature"] == 4
    assert isinstance(res["chords"], list)
