import librosa
import torch
from nnAudio.features.cqt import CQT

from scripts.export.config import FEATURE


class CQTFrontend(torch.nn.Module):
    """Raw PCM -> normalized CQT [B, frames, n_bins], graph-exportable.

    Matches the training/eval feature recipe in
    reference/ChordMini/src/evaluation/utils/common.py:extract_song_features
    (and identically reference/ChordMini/src/data/AudioChordDataset.py):

        cqt = librosa.cqt(audio, sr=22050, n_bins=144, bins_per_octave=24,
                           hop_length=2048, fmin=librosa.note_to_hz('C1'))
        feature = np.log(np.abs(cqt) + 1e-6).T

    followed by (x - mean) / std normalization (applied later at inference
    time in the reference pipeline; consolidated into this module here).
    """

    def __init__(self, mean: float, std: float):
        super().__init__()
        self.cqt = CQT(
            sr=FEATURE.sample_rate,
            hop_length=FEATURE.hop_length,
            n_bins=FEATURE.n_bins,
            bins_per_octave=FEATURE.bins_per_octave,
            fmin=librosa.note_to_hz("C1"),
            output_format="Magnitude",
            verbose=False,
        )
        self.register_buffer("mean", torch.tensor(float(mean)))
        self.register_buffer("std", torch.tensor(float(std)))

    def forward(self, pcm: torch.Tensor) -> torch.Tensor:
        mag = self.cqt(pcm)  # [B, n_bins, frames]
        logmag = torch.log(mag + 1e-6)  # matches np.log(np.abs(cqt) + 1e-6)
        feat = logmag.transpose(1, 2)  # [B, frames, n_bins]
        return (feat - self.mean) / self.std
