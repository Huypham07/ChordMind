from app.domain.entities import AnalysisResult
from app.domain.ports import ModelSlot
from .manifest import load_spec
from .audio_io import decode_pcm
from .assemble import analyze_pcm

class OnnxAnalysisSlot(ModelSlot):
    def __init__(self, model_name: str = "btc"):
        self._spec = load_spec(model_name)

    def run(self, youtube_id: str, title: str, duration: float) -> AnalysisResult:
        raise NotImplementedError("YouTube ingestion is out of scope for #1; use run_file")

    def run_file(self, song_id: str, title: str, audio_path: str) -> AnalysisResult:
        pcm = decode_pcm(audio_path, self._spec.fs)
        data = analyze_pcm(pcm, song_id, title, self._spec)
        return AnalysisResult.from_dict(data)
