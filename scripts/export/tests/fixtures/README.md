# Parity test fixtures

Three short (11 s, mono, 22050 Hz) deterministic synthetic clips used by
`scripts/export/tests/test_parity.py` to exercise the CQT-frontend +
ChordNet path identically on both the ONNX (PCM in) side and the
reference librosa-CQT + torch side. Parity only requires that the SAME
audio go through both paths, so synthetic audio is sufficient here —
these clips do not attempt to represent real-music chord content, and
passing parity on them says nothing about real-music chord-recognition
accuracy (a separate, later concern).

11 s (> 9.94 s = (108-1)*2048/22050) is deliberate: it's longer than the
ONNX front-end's fixed 108-frame window, so the reference path (which
extracts features from the file's actual duration) sees the same 108 real
frames as the ONNX path, with no zero-padding on either side. A 6 s clip
would force the ONNX side to zero-pad to reach the window while the
reference side naturally produced fewer than 108 frames -- comparing
non-aligned windows and producing a spurious parity failure.

- `triad_cmaj.wav` — sustained, harmonically rich C major triad: C4/E4/G4
  fundamentals (261.63/329.63/392.00 Hz), each with 5 harmonics at
  amplitude 1/h, plus light fixed-seed (0) Gaussian noise, normalized.
  Deliberately NOT pure sine tones: pure sines are out-of-distribution for
  chord models trained on real instrument timbre, and previously caused
  nnAudio's CQT (ONNX path) to diverge just enough from librosa's (reference
  path) that BTC's argmax flipped from `C` to `N` (no-chord) on this clip
  even though the shared CQT frontend/wrapper was correct (ChordNet stayed
  at argmax_agreement=1.0 on the same audio). The richer harmonic content
  removes that spurious divergence for both models.
- `white_noise.wav` — low-amplitude Gaussian white noise, fixed seed (42).
- `sweep_100_2000hz.wav` — linear frequency sweep, 100 Hz to 2000 Hz.

Regenerate with:

```
scripts/export/.venv/bin/python -m scripts.export.tests.fixtures.generate_fixtures
```
