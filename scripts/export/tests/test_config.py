from scripts.export.config import FEATURE, REFERENCE_ROOT

def test_feature_matches_reference_yaml():
    assert FEATURE.n_bins == 144
    assert FEATURE.bins_per_octave == 24
    assert FEATURE.hop_length == 2048
    assert FEATURE.sample_rate == 22050
    assert FEATURE.n_classes == 170
    assert FEATURE.seq_len == 108

def test_reference_root_has_chordnet():
    assert (REFERENCE_ROOT / "src" / "models" / "chord_net.py").exists()
