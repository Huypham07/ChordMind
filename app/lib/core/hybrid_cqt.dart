// Feasibility-spike port of `librosa.core.hybrid_cqt` (Plan B Task B0.3).
//
// Reproduces, in pure Dart, the exact feature chord-cnn-lstm expects:
//   abs(librosa.core.hybrid_cqt(y, sr=22050, bins_per_octave=36,
//       fmin=librosa.note_to_hz('F#0'), n_bins=288, tuning=None,
//       hop_length=512)).T
//
// `hybrid_cqt` stitches two different algorithms together:
//  - the top ~50 bins (short filters) use `pseudo_cqt`: a single
//    hann-windowed STFT dotted against a magnitude-only filter bank.
//  - the bottom ~238 bins (long filters, low frequencies) use the real
//    recursive-downsampling `cqt` (7 octaves, each built from a
//    progressively halved copy of the signal).
// `tuning=None` also makes `hybrid_cqt` estimate a signal-adaptive tuning
// offset (via `piptrack` peak-picking + a circular histogram mode) that
// shifts `fmin` by a few cents before any of the above runs.
//
// This is NOT a byte-exact port of librosa's `soxr_hq` resampler (that is
// a proprietary-quality polyphase resampler, infeasible to reproduce
// bit-exactly in a spike). The octave-recursion downsampling here uses a
// simple 63-tap Kaiser-windowed half-band FIR filter instead. See
// docs/task-b03-report.md for the empirical validation that this
// substitution does not change the CCL net's argmax on the two spike
// fixtures.
import 'dart:math' as math;
import 'dart:typed_data';

const double _sr = 22050.0;
const int _hopLength = 512;
// librosa.note_to_hz('F#0')
const double _fminBase = 23.12465141947715;
const int _nBins = 288;
const int _binsPerOctave = 36;

/// Computes the CCL front-end feature: magnitude hybrid_cqt, frame-major
/// (`[frame * 288 + bin]`), float32.
Float32List hybridCqt(Float64List pcm, {double sr = _sr}) {
  assert(sr == _sr, 'this port is specialized to sr=22050');

  final tuning = _estimateTuning(pcm, sr);
  final fmin = _fminBase * math.pow(2.0, tuning / _binsPerOctave);

  final freqs = List<double>.generate(
    _nBins,
    (k) => fmin * math.pow(2.0, k / _binsPerOctave),
  );

  // alpha is constant for a perfect geometric bin spacing (see report).
  final alpha = (math.pow(2.0, 2.0 / _binsPerOctave) - 1) /
      (math.pow(2.0, 2.0 / _binsPerOctave) + 1);
  final q = 1.0 / alpha; // filter_scale=1
  final lengths288 =
      List<double>.generate(_nBins, (k) => q * sr / freqs[k]);

  // Pseudo/full split: 2**ceil(log2(length)) < 2*hop_length.
  final pseudoMask = List<bool>.generate(_nBins, (k) {
    final nextPow2 = math.pow(2.0, (math.log(lengths288[k]) / math.ln2).ceil());
    return nextPow2 < 2 * _hopLength;
  });
  var nBinsPseudo = 0;
  for (final m in pseudoMask) {
    if (m) nBinsPseudo++;
  }
  final nBinsFull = _nBins - nBinsPseudo;

  final freqsFull = freqs.sublist(0, nBinsFull);
  final lengthsFull = lengths288.sublist(0, nBinsFull);
  final freqsPseudo = freqs.sublist(nBinsFull);

  final fullResult = _fullCqt(pcm, sr, freqsFull, q);
  final pseudoResult =
      nBinsPseudo > 0 ? _pseudoCqt(pcm, sr, freqsPseudo, q) : null;

  var nFrames = fullResult.nFrames;
  if (pseudoResult != null && pseudoResult.nFrames < nFrames) {
    nFrames = pseudoResult.nFrames;
  }

  // Final scale=True normalization for the full-cqt branch (uses lengths
  // at the ORIGINAL sample rate, computed once above as lengthsFull).
  final out = Float32List(nFrames * _nBins);
  for (var k = 0; k < nBinsFull; k++) {
    final invSqrtLen = 1.0 / math.sqrt(lengthsFull[k]);
    final re = fullResult.re[k];
    final im = fullResult.im[k];
    for (var f = 0; f < nFrames; f++) {
      final r = re[f] * invSqrtLen;
      final i = im[f] * invSqrtLen;
      out[f * _nBins + k] = math.sqrt(r * r + i * i);
    }
  }
  if (pseudoResult != null) {
    for (var k = 0; k < nBinsPseudo; k++) {
      final mag = pseudoResult.mag[k];
      for (var f = 0; f < nFrames; f++) {
        out[f * _nBins + nBinsFull + k] = mag[f];
      }
    }
  }
  return out;
}

// ---------------------------------------------------------------------
// Full recursive-downsampling CQT (the ~238 low bins).
// ---------------------------------------------------------------------

class _ComplexOctaves {
  final int nFrames;
  final List<Float64List> re; // [bin][frame]
  final List<Float64List> im;
  _ComplexOctaves(this.nFrames, this.re, this.im);
}

_ComplexOctaves _fullCqt(
  Float64List pcm,
  double sr,
  List<double> freqsFull,
  double q,
) {
  final nBinsFull = freqsFull.length;
  final nOctaves = (nBinsFull / _binsPerOctave).ceil();
  final nFilters = math.min(_binsPerOctave, nBinsFull);

  final reOut = List<Float64List>.generate(nBinsFull, (_) => Float64List(0));
  final imOut = List<Float64List>.generate(nBinsFull, (_) => Float64List(0));

  var myY = pcm;
  var mySr = sr;
  var myHop = _hopLength;
  var minFrames = 1 << 30;

  for (var i = 0; i < nOctaves; i++) {
    final hi = nBinsFull - _binsPerOctave * i;
    final lo = math.max(0, nBinsFull - _binsPerOctave * (i + 1));
    final slFreqs = freqsFull.sublist(lo, hi);

    final bank = _buildFilterBank(slFreqs, mySr, q);
    final stft = _stftComplex(myY, bank.nFft, myHop, window: null);
    final scaleOct = math.sqrt(sr / mySr);

    final nOctBins = slFreqs.length;
    final nFramesOct = stft.nFrames;
    if (nFramesOct < minFrames) minFrames = nFramesOct;

    for (var b = 0; b < nOctBins; b++) {
      final re = Float64List(nFramesOct);
      final im = Float64List(nFramesOct);
      final basisRe = bank.re[b];
      final basisIm = bank.im[b];
      for (var f = 0; f < nFramesOct; f++) {
        double accRe = 0, accIm = 0;
        final dRe = stft.re[f];
        final dIm = stft.im[f];
        for (var j = 0; j < basisRe.length; j++) {
          final br = basisRe[j], bi = basisIm[j];
          final xr = dRe[j], xi = dIm[j];
          // (br+i*bi)*(xr+i*xi)
          accRe += br * xr - bi * xi;
          accIm += br * xi + bi * xr;
        }
        re[f] = accRe * scaleOct;
        im[f] = accIm * scaleOct;
      }
      reOut[lo + b] = re;
      imOut[lo + b] = im;
    }

    if (i < nOctaves - 1) {
      myY = _halfbandDecimate(myY);
      myHop ~/= 2;
      mySr /= 2;
    }
  }

  return _ComplexOctaves(minFrames, reOut, imOut);
}

// ---------------------------------------------------------------------
// Pseudo CQT (the ~50 high bins): single hann-windowed STFT, magnitude
// filter bank.
// ---------------------------------------------------------------------

class _MagOctave {
  final int nFrames;
  final List<Float64List> mag; // [bin][frame]
  _MagOctave(this.nFrames, this.mag);
}

_MagOctave _pseudoCqt(
  Float64List pcm,
  double sr,
  List<double> freqsPseudo,
  double q,
) {
  final bank = _buildFilterBank(
    freqsPseudo,
    sr,
    q,
    minNfft: 1 << (1 + (math.log(_hopLength) / math.ln2).ceil()),
  );
  final window = _hannWindow(bank.nFft);
  final stft = _stftComplex(pcm, bank.nFft, _hopLength, window: window);
  final invSqrtNfft = 1.0 / math.sqrt(bank.nFft);

  final nBins = freqsPseudo.length;
  final nFrames = stft.nFrames;
  final mag = List<Float64List>.generate(nBins, (_) => Float64List(nFrames));

  // Precompute |fft_basis| once per bin.
  final absBasis = List<Float64List>.generate(
    nBins,
    (b) {
      final basisRe = bank.re[b];
      final basisIm = bank.im[b];
      final a = Float64List(basisRe.length);
      for (var j = 0; j < a.length; j++) {
        a[j] = math.sqrt(basisRe[j] * basisRe[j] + basisIm[j] * basisIm[j]);
      }
      return a;
    },
  );

  for (var b = 0; b < nBins; b++) {
    final basis = absBasis[b];
    final out = mag[b];
    for (var f = 0; f < nFrames; f++) {
      double acc = 0;
      final dRe = stft.re[f];
      final dIm = stft.im[f];
      for (var j = 0; j < basis.length; j++) {
        final magD = math.sqrt(dRe[j] * dRe[j] + dIm[j] * dIm[j]);
        acc += basis[j] * magD;
      }
      out[f] = acc * invSqrtNfft;
    }
  }
  return _MagOctave(nFrames, mag);
}

// ---------------------------------------------------------------------
// Wavelet filter bank (frequency domain), per librosa.filters.wavelet +
// __vqt_filter_fft (sparsify_rows skipped -- see report for the accuracy
// impact of that simplification).
// ---------------------------------------------------------------------

class _FilterBank {
  final int nFft;
  final List<Float64List> re; // [bin][freqBin], freqBin in [0, nFft/2]
  final List<Float64List> im;
  _FilterBank(this.nFft, this.re, this.im);
}

_FilterBank _buildFilterBank(
  List<double> freqsOct,
  double sr,
  double q, {
  int? minNfft,
}) {
  final n = freqsOct.length;
  final lengths = List<double>.generate(n, (k) => q * sr / freqsOct[k]);

  var maxLen = 0.0;
  for (final l in lengths) {
    if (l > maxLen) maxLen = l;
  }
  var nFft = 1 << ((math.log(maxLen) / math.ln2).ceil());
  if (minNfft != null && nFft < minNfft) nFft = minNfft;

  final nFreqBins = nFft ~/ 2 + 1;
  final re = List<Float64List>.generate(n, (_) => Float64List(nFreqBins));
  final im = List<Float64List>.generate(n, (_) => Float64List(nFreqBins));

  for (var k = 0; k < n; k++) {
    final ilen = lengths[k];
    final start = (-ilen / 2).floor();
    final stop = (ilen / 2).floor();
    final nActual = stop - start;
    if (nActual <= 0) continue;

    final win = _hannWindow(nActual);
    final sigRe = Float64List(nActual);
    final sigIm = Float64List(nActual);
    final w = 2 * math.pi * freqsOct[k] / sr;
    double l1 = 0;
    for (var j = 0; j < nActual; j++) {
      final t = (start + j).toDouble();
      final angle = w * t;
      final c = math.cos(angle) * win[j];
      final s = math.sin(angle) * win[j];
      sigRe[j] = c;
      sigIm[j] = s;
      l1 += math.sqrt(c * c + s * s);
    }
    if (l1 > 0) {
      for (var j = 0; j < nActual; j++) {
        sigRe[j] /= l1;
        sigIm[j] /= l1;
      }
    }

    // pad_center into nFft, then scale by lengths[k]/nFft.
    final padded_re = Float64List(nFft);
    final padded_im = Float64List(nFft);
    final leftPad = (nFft - nActual) ~/ 2;
    final scale = lengths[k] / nFft;
    for (var j = 0; j < nActual; j++) {
      padded_re[leftPad + j] = sigRe[j] * scale;
      padded_im[leftPad + j] = sigIm[j] * scale;
    }

    _fftInPlace(padded_re, padded_im);
    for (var f = 0; f < nFreqBins; f++) {
      re[k][f] = padded_re[f];
      im[k][f] = padded_im[f];
    }
  }

  return _FilterBank(nFft, re, im);
}

Float64List _hannWindow(int n) {
  final w = Float64List(n);
  if (n <= 1) {
    if (n == 1) w[0] = 1.0;
    return w;
  }
  for (var i = 0; i < n; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / n);
  }
  return w;
}

// ---------------------------------------------------------------------
// STFT: center=True, pad_mode='constant' (zero padding).
// ---------------------------------------------------------------------

class _Stft {
  final int nFrames;
  final List<Float64List> re; // [frame][freqBin]
  final List<Float64List> im;
  _Stft(this.nFrames, this.re, this.im);
}

_Stft _stftComplex(
  Float64List y,
  int nFft,
  int hop, {
  required Float64List? window,
}) {
  final padAmount = nFft ~/ 2;
  final paddedLen = y.length + 2 * padAmount;
  final padded = Float64List(paddedLen);
  for (var i = 0; i < y.length; i++) {
    padded[padAmount + i] = y[i];
  }

  final nFrames = 1 + (paddedLen - nFft) ~/ hop;
  final nFreqBins = nFft ~/ 2 + 1;
  final re = List<Float64List>.generate(nFrames, (_) => Float64List(nFreqBins));
  final im = List<Float64List>.generate(nFrames, (_) => Float64List(nFreqBins));

  final frameRe = Float64List(nFft);
  final frameIm = Float64List(nFft);
  for (var t = 0; t < nFrames; t++) {
    final base = t * hop;
    for (var j = 0; j < nFft; j++) {
      final v = padded[base + j];
      frameRe[j] = window == null ? v : v * window[j];
      frameIm[j] = 0.0;
    }
    _fftInPlace(frameRe, frameIm);
    for (var f = 0; f < nFreqBins; f++) {
      re[t][f] = frameRe[f];
      im[t][f] = frameIm[f];
    }
  }
  return _Stft(nFrames, re, im);
}

// ---------------------------------------------------------------------
// Iterative radix-2 Cooley-Tukey FFT (in place; n must be a power of 2).
// ---------------------------------------------------------------------

void _fftInPlace(Float64List re, Float64List im) {
  final n = re.length;
  if (n <= 1) return;

  // Bit-reversal permutation.
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i];
      re[i] = re[j];
      re[j] = tr;
      final ti = im[i];
      im[i] = im[j];
      im[j] = ti;
    }
  }

  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    final wRe = math.cos(ang);
    final wIm = math.sin(ang);
    for (var i = 0; i < n; i += len) {
      var curRe = 1.0;
      var curIm = 0.0;
      for (var k = 0; k < len ~/ 2; k++) {
        final uRe = re[i + k];
        final uIm = im[i + k];
        final vRe = re[i + k + len ~/ 2] * curRe - im[i + k + len ~/ 2] * curIm;
        final vIm = re[i + k + len ~/ 2] * curIm + im[i + k + len ~/ 2] * curRe;
        re[i + k] = uRe + vRe;
        im[i + k] = uIm + vIm;
        re[i + k + len ~/ 2] = uRe - vRe;
        im[i + k + len ~/ 2] = uIm - vIm;
        final nextRe = curRe * wRe - curIm * wIm;
        final nextIm = curRe * wIm + curIm * wRe;
        curRe = nextRe;
        curIm = nextIm;
      }
    }
  }
}

// ---------------------------------------------------------------------
// Octave-recursion decimator: a simple 63-tap Kaiser-windowed half-band
// FIR lowpass (cutoff at the decimated Nyquist), NOT librosa's soxr_hq.
// See the module doc comment / task report for why this substitution is
// accurate enough for this feature.
// ---------------------------------------------------------------------

Float64List? _halfbandTaps;

Float64List _getHalfbandTaps() {
  if (_halfbandTaps != null) return _halfbandTaps!;
  const n = 63;
  const cutoff = 0.5; // relative to the DECIMATED Nyquist
  const beta = 8.6;
  final h = Float64List(n);
  final mid = (n - 1) / 2.0;
  var sum = 0.0;
  for (var i = 0; i < n; i++) {
    final t = i - mid;
    final sincVal = t == 0 ? cutoff : math.sin(math.pi * cutoff * t) / (math.pi * t);
    final kaiser = _besselI0(beta * math.sqrt(1 - math.pow(2 * i / (n - 1) - 1, 2))) /
        _besselI0(beta);
    h[i] = sincVal * kaiser;
    sum += h[i];
  }
  for (var i = 0; i < n; i++) {
    h[i] /= sum;
  }
  _halfbandTaps = h;
  return h;
}

double _besselI0(double x) {
  // Series expansion, adequate for kaiser-window beta values.
  double sum = 1.0;
  double term = 1.0;
  final xHalfSq = (x / 2) * (x / 2);
  for (var k = 1; k < 25; k++) {
    term *= xHalfSq / (k * k);
    sum += term;
  }
  return sum;
}

Float64List _halfbandDecimate(Float64List y) {
  final h = _getHalfbandTaps();
  final ntaps = h.length;
  final half = ntaps ~/ 2;
  final n = y.length;
  final filtered = Float64List(n);
  for (var i = 0; i < n; i++) {
    double acc = 0;
    for (var k = 0; k < ntaps; k++) {
      final idx = i + k - half;
      if (idx >= 0 && idx < n) {
        acc += h[k] * y[idx];
      }
    }
    filtered[i] = acc;
  }
  final outLen = n ~/ 2;
  final out = Float64List(outLen);
  // librosa's `resample(..., scale=True)` divides by sqrt(target_sr/orig_sr)
  // = sqrt(1/2) here, i.e. multiplies by sqrt(2), to keep total energy
  // approximately constant across the rate change. Without this the
  // signal amplitude (and hence every octave built from it) is
  // systematically too small, compounding per recursion depth.
  const energyCompensation = 1.4142135623730951; // sqrt(2)
  for (var i = 0; i < outLen; i++) {
    out[i] = filtered[2 * i] * energyCompensation;
  }
  return out;
}

// ---------------------------------------------------------------------
// Tuning estimation: librosa.estimate_tuning (piptrack + circular-mode
// histogram), specialized to bins_per_octave=36 / tuning=None.
// ---------------------------------------------------------------------

double _estimateTuning(Float64List y, double sr) {
  const nFft = 2048;
  const hop = 512; // win_length(=n_fft) // 4
  const fmin = 150.0;
  final fmax = math.min(4000.0, sr / 2);
  const threshold = 0.1;

  final window = _hannWindow(nFft);
  final stft = _stftComplex(y, nFft, hop, window: window);
  final nFreqBins = nFft ~/ 2 + 1;

  final pitches = <double>[];
  final mags = <double>[];

  final s = Float64List(nFreqBins);
  for (var t = 0; t < stft.nFrames; t++) {
    final dRe = stft.re[t];
    final dIm = stft.im[t];
    var maxS = 0.0;
    for (var f = 0; f < nFreqBins; f++) {
      s[f] = math.sqrt(dRe[f] * dRe[f] + dIm[f] * dIm[f]);
      if (s[f] > maxS) maxS = s[f];
    }
    final refValue = threshold * maxS;

    for (var f = 0; f < nFreqBins; f++) {
      final freq = f * sr / nFft;
      if (freq < fmin || freq >= fmax) continue;

      final sPrev = f > 0 ? s[f - 1] : 0.0;
      final sNext = f < nFreqBins - 1 ? s[f + 1] : 0.0;

      // np.gradient central difference (edges: one-sided).
      double avg;
      if (f == 0) {
        avg = s[1] - s[0];
      } else if (f == nFreqBins - 1) {
        avg = s[f] - s[f - 1];
      } else {
        avg = (sNext - sPrev) / 2.0;
      }

      double shift = 0.0;
      if (f > 0 && f < nFreqBins - 1) {
        final a = sNext + sPrev - 2 * s[f];
        final b = (sNext - sPrev) / 2.0;
        if (a != 0 && b.abs() < a.abs()) {
          shift = -b / a;
        }
      }
      final dskew = 0.5 * avg * shift;

      final st = s[f] > refValue ? s[f] : 0.0;
      final stPrev = sPrev > refValue ? sPrev : 0.0;
      final stNext = sNext > refValue ? sNext : 0.0;
      final isLocalMax = f > 0 && st > stPrev && (f == nFreqBins - 1 || st >= stNext);

      if (isLocalMax && st > 0) {
        final pitch = (f + shift) * sr / nFft;
        final mag = s[f] + dskew;
        pitches.add(pitch);
        mags.add(mag);
      }
    }
  }

  if (pitches.isEmpty) return 0.0;

  final sortedMags = List<double>.from(mags)..sort();
  final med = sortedMags.length.isOdd
      ? sortedMags[sortedMags.length ~/ 2]
      : (sortedMags[sortedMags.length ~/ 2 - 1] + sortedMags[sortedMags.length ~/ 2]) / 2.0;

  final selected = <double>[];
  for (var i = 0; i < pitches.length; i++) {
    if (mags[i] >= med) selected.add(pitches[i]);
  }
  if (selected.isEmpty) return 0.0;

  return _pitchTuning(selected);
}

double _pitchTuning(List<double> frequencies) {
  final residuals = <double>[];
  for (final f in frequencies) {
    if (f <= 0) continue;
    final octs = math.log(f / 27.5) / math.ln2;
    var r = (_binsPerOctave * octs) % 1.0;
    if (r < 0) r += 1.0; // Dart's % can be negative-safe already, but be sure
    if (r >= 0.5) r -= 1.0;
    residuals.add(r);
  }
  if (residuals.isEmpty) return 0.0;

  const nBins = 100; // ceil(1/0.01)
  const binWidth = 1.0 / nBins;
  final counts = List<int>.filled(nBins, 0);
  for (final r in residuals) {
    var idx = ((r + 0.5) / binWidth).floor();
    if (idx < 0) idx = 0;
    if (idx >= nBins) idx = nBins - 1;
    counts[idx]++;
  }
  var best = 0;
  for (var i = 1; i < nBins; i++) {
    if (counts[i] > counts[best]) best = i;
  }
  return -0.5 + best * binWidth;
}
