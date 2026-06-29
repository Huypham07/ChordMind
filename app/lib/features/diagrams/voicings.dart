class GuitarVoicing {
  final List<int> frets; // 6 strings low->high, -1 muted, 0 open
  final int baseFret;
  final List<int> barres;
  const GuitarVoicing(this.frets, {this.baseFret = 1, this.barres = const []});
}

// ponytail: small static table of open chords; expand or compute from a library if needed.
const guitarVoicings = <String, GuitarVoicing>{
  'C':  GuitarVoicing([-1, 3, 2, 0, 1, 0]),
  'G':  GuitarVoicing([3, 2, 0, 0, 0, 3]),
  'Am': GuitarVoicing([-1, 0, 2, 2, 1, 0]),
  'F':  GuitarVoicing([1, 3, 3, 2, 1, 1], barres: [1]),
  'D':  GuitarVoicing([-1, -1, 0, 2, 3, 2]),
  'E':  GuitarVoicing([0, 2, 2, 1, 0, 0]),
  'Em': GuitarVoicing([0, 2, 2, 0, 0, 0]),
  'Dm': GuitarVoicing([-1, -1, 0, 2, 3, 1]),
};

const _roots = {'C':0,'C#':1,'Db':1,'D':2,'D#':3,'Eb':3,'E':4,'F':5,
  'F#':6,'Gb':6,'G':7,'G#':8,'Ab':8,'A':9,'A#':10,'Bb':10,'B':11};

List<int> pianoNotes(String chord) {
  final isMinor = chord.contains('m') && !chord.contains('maj');
  final rootName = chord.replaceAll(RegExp(r'(m|maj|7|dim|aug|sus).*$'), '');
  final root = _roots[rootName] ?? 0;
  final third = isMinor ? 3 : 4;
  return [root, (root + third) % 12, (root + 7) % 12];
}
