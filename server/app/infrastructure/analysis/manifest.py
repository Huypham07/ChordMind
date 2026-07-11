import json
from dataclasses import dataclass
from pathlib import Path

_MANIFEST = Path(__file__).resolve().parents[4] / "artifacts" / "onnx" / "manifest.json"

@dataclass(frozen=True)
class ModelSpec:
    name: str
    file: str
    fs: int
    window_samples: int
    labels: list[str]
    decode: str
    input: str

def load_spec(name: str) -> ModelSpec:
    m = json.loads(_MANIFEST.read_text())
    e = m[name]
    return ModelSpec(
        name=name, file=e["file"],
        fs=e.get("fs", e.get("sample_rate", 22050)),
        window_samples=e["window_samples"],
        labels=e["labels"],
        decode=e.get("decode", "vote"),
        input=e.get("input", "pcm"),
    )

def onnx_path(spec: ModelSpec) -> str:
    return str(_MANIFEST.parent / spec.file)
