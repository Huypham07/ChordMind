import torch
from scripts.export.cqt_frontend import CQTFrontend
from scripts.export.config import FEATURE


def test_frontend_output_shape():
    fe = CQTFrontend(mean=0.0, std=1.0).eval()
    pcm = torch.zeros(1, FEATURE.hop_length * 200)  # ~200 frames of silence
    with torch.no_grad():
        out = fe(pcm)
    assert out.shape[0] == 1
    assert out.shape[2] == FEATURE.n_bins  # 144
    assert out.shape[1] >= 190  # ~ samples / hop


def test_frontend_normalizes():
    fe = CQTFrontend(mean=5.0, std=2.0).eval()
    pcm = torch.randn(1, FEATURE.hop_length * 120)
    raw = CQTFrontend(mean=0.0, std=1.0).eval()
    with torch.no_grad():
        a = fe(pcm)
        b = raw(pcm)
    assert torch.allclose(a, (b - 5.0) / 2.0, atol=1e-4)
