import 'package:meta/meta.dart';

/// Porzione del testo mostrato a schermo da sintetizzare come un unico blocco.
@immutable
class SpeechSpan {
  const SpeechSpan(this.start, this.end, this.text)
      : assert(start >= 0),
        assert(end >= start);

  /// Posizione iniziale (inclusa) nel testo di partenza.
  final int start;

  /// Posizione finale (esclusa) nel testo di partenza.
  final int end;

  /// Testo del blocco, uguale a `source.substring(start, end)`.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SpeechSpan &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'SpeechSpan($start, $end, "$text")';
}

/// Divide una battuta in blocchi da sintetizzare uno alla volta.
///
/// Lavora sul testo mostrato a schermo e ne restituisce le posizioni, così la
/// sincronizzazione può far comparire ogni blocco quando inizia il suo audio.
/// Il primo blocco, se lungo, viene diviso alla prima virgola utile per ridurre
/// l'attesa del primo audio; i blocchi troppo lunghi si dividono sulle virgole.
@immutable
class SpeechSegmenter {
  const SpeechSegmenter({this.maxChars = 220, this.firstChunkMaxChars = 60})
      : assert(maxChars >= 40),
        assert(firstChunkMaxChars >= 20);

  /// Lunghezza massima di un blocco; oltre, si divide sulle virgole o sugli spazi.
  final int maxChars;

  /// Oltre questa lunghezza il primo blocco si divide alla prima virgola utile.
  final int firstChunkMaxChars;

  static final _sentenceEnd = RegExp(r'(?<=[.!?;:])\s+|\n+');
  static final _comma = RegExp(r'(?<=,)\s+');
  static final _speakable = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Restituisce i blocchi nell'ordine di lettura, senza blocchi privi di parole.
  List<SpeechSpan> split(String text) {
    final out = <SpeechSpan>[];
    var from = 0;
    for (final m in [..._sentenceEnd.allMatches(text), null]) {
      final to = m?.start ?? text.length;
      _addTrimmed(text, from, to, out);
      from = m?.end ?? text.length;
    }
    if (out.isNotEmpty && out.first.text.length > firstChunkMaxChars) {
      final first = out.removeAt(0);
      final cut =
          _comma.allMatches(first.text).where((m) => m.start >= 15).firstOrNull;
      final parts = <SpeechSpan>[];
      if (cut == null) {
        parts.add(first);
      } else {
        _addTrimmed(text, first.start, first.start + cut.start, parts);
        _addTrimmed(text, first.start + cut.end, first.end, parts);
      }
      out.insertAll(0, parts);
    }
    return out;
  }

  void _addTrimmed(String text, int start, int end, List<SpeechSpan> out) {
    while (start < end && _isSpace(text.codeUnitAt(start))) {
      start++;
    }
    while (end > start && _isSpace(text.codeUnitAt(end - 1))) {
      end--;
    }
    if (start >= end) return;
    final s = text.substring(start, end);
    if (!_speakable.hasMatch(s)) return;
    if (s.length <= maxChars) {
      out.add(SpeechSpan(start, end, s));
      return;
    }
    final cuts = _comma.allMatches(s).map((m) => m.start).toList();
    var a = 0;
    while (s.length - a > maxChars) {
      final limit = a + maxChars;
      final ok = cuts.where((c) => c > a + 20 && c <= limit).toList();
      var b = ok.isNotEmpty ? ok.last : s.lastIndexOf(' ', limit);
      if (b <= a) b = limit;
      _addTrimmed(text, start + a, start + b, out);
      a = b;
    }
    _addTrimmed(text, start + a, end, out);
  }

  static bool _isSpace(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0xA0;
}
