import hashlib
import json
from pathlib import Path
from scripts.export.config import FEATURE
from scripts.export.load_chordnet import load_bundle

CCL_HEAD_NAMES = ("triad", "bass", "seventh", "ninth", "eleventh", "thirteenth")


def _sha256(p: Path) -> str:
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def write_manifest_entry(
    onnx_path, ckpt_path, *, name, step, decode, manifest_path, version="1",
    model_type="ChordNet",
) -> dict:
    b = load_bundle(Path(ckpt_path), model_type)
    labels = [b.idx_to_chord[i] for i in range(len(b.idx_to_chord))]
    entry = {
        "name": name,
        # Discriminator field for symmetry with the CCL entry's "model": so
        # the app can identify the model family without relying on the
        # manifest entry key (e.g. "chordnet-2e1d", "btc").
        "model": name.replace("_", "-"),
        "step": step,
        "file": Path(onnx_path).name,
        "sha256": _sha256(onnx_path),
        "version": version,
        "fs": FEATURE.sample_rate,
        "seq_len": FEATURE.seq_len,
        "n_classes": FEATURE.n_classes,
        "labels": labels,
        "decode": decode,
        "window_samples": (FEATURE.seq_len - 1) * FEATURE.hop_length,
        "opset": 17,
    }
    mp = Path(manifest_path)
    data = json.loads(mp.read_text()) if mp.exists() else {}
    data[name] = entry
    mp.write_text(json.dumps(data, indent=2))
    return entry


def write_ccl_manifest_entry(
    onnx_path, *, head_dims, manifest_path, name="chord_cnn_lstm", version="1",
) -> dict:
    """Feature-in manifest entry for chord-cnn-lstm -- a DIFFERENT schema
    than `write_manifest_entry`'s flat-170-label ChordNet/BTC entries: no
    `idx_to_chord` labels (there is no single flat class space), instead a
    `heads` list describing the 6 decomposition heads (triad/bass/seventh/
    ninth/eleventh/thirteenth) plus the `feature` recipe the app needs to
    reproduce the `hybrid_cqt` (CQTV2) front-end natively on-device, since
    the exported graph is feature-in (see `export_ccl.py`), not PCM-in.
    """
    if len(head_dims) != len(CCL_HEAD_NAMES):
        raise ValueError(
            f"expected {len(CCL_HEAD_NAMES)} head dims, got {len(head_dims)}"
        )
    entry = {
        "name": name,
        "step": "chord",
        "model": "chord-cnn-lstm",
        "input": "cqtv2_feature",
        "decode": "xhmm",
        "file": Path(onnx_path).name,
        "sha256": _sha256(onnx_path),
        "version": version,
        "opset": 17,
        "sample_rate": 22050,
        "feature": {
            "type": "hybrid_cqt",
            "sr": 22050,
            "hop_length": 512,
            "n_bins": 288,
            "bins_per_octave": 36,
            "fmin": "F#0",
            "tuning": None,
            "magnitude": True,
        },
        "heads": [
            {"name": head_name, "dim": int(dim)}
            for head_name, dim in zip(CCL_HEAD_NAMES, head_dims)
        ],
        # Plan B decode pointer: the 6 head argmaxes are NOT independently
        # meaningful chord labels -- they must be combined by the reference
        # XHMM Viterbi decoder (`extractors/xhmm_ismir.py:XHMMDecoder`)
        # against a fixed chord-template vocabulary. `chord_recognition.py`'s
        # default `chord_recognition()` call uses `chord_dict_name='submission'`,
        # i.e. `data/submission_chord_list.txt` -- that is the template file
        # the app must vendor and feed to its own XHMM decode to turn head
        # probabilities into chord label strings (see
        # `XHMMDecoder.__init_known_chord_names` for how the template is
        # expanded into the 12-key-transposed candidate chord set, and
        # `XHMMDecoder.decode` for the Viterbi combination of the 6 head
        # log-probs into a per-frame chord tag).
        "decode_assets": [
            "reference/chord-cnn-lstm-model/data/submission_chord_list.txt",
        ],
        "decode_note": (
            "6 head argmaxes (triad/bass/seventh/ninth/eleventh/thirteenth) "
            "are combined via XHMM Viterbi decoding over the chord templates "
            "in decode_assets, not read independently; see "
            "extractors/xhmm_ismir.py:XHMMDecoder.decode and "
            "chord_recognition.py for the reference call sequence."
        ),
        # Per-head class index -> label is not a flat, independently-decodable
        # lookup: e.g. the triad head packs (root x TriadTypes) + "N" into one
        # axis, and the seventh/ninth/eleventh/thirteenth heads are decoration
        # *types* (not full chords) that XHMMDecoder combines with the
        # decoded triad root. Fabricating a flat label list per class index
        # here would be misleading without also reimplementing that
        # combination logic, so we point at the source of truth instead.
        "heads_semantics": (
            "see complex_chord.py (TriadTypes/SeventhTypes/NinthTypes/"
            "EleventhTypes/ThirteenthTypes enums, ChordTypeLimit slicing) "
            "for what each head's class indices mean"
        ),
    }
    mp = Path(manifest_path)
    data = json.loads(mp.read_text()) if mp.exists() else {}
    data[name] = entry
    mp.write_text(json.dumps(data, indent=2))
    return entry
