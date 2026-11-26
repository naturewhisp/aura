import 'package:meta/meta.dart';

/// Prepara il testo di una battuta per la sintesi vocale italiana.
///
/// Rimuove i tag dell'agent-loop e la formattazione, scrive in lettere numeri,
/// orari e percentuali e sostituisce le sigle note con la loro lettura.
/// Non modifica il testo mostrato a schermo: lavora su una copia destinata alla voce.
@immutable
class SpeechTextNormalizer {
  const SpeechTextNormalizer();

  static final _tags = RegExp(r'<[^<>]{1,40}>');
  static final _markup = RegExp(r'[*_#`~|\[\]{}]');
  static final _quotes = RegExp('["“”«»„]');
  static final _spaces = RegExp(r'[ \t]+');
  static final _time = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');
  static final _percent = RegExp(r'(\d+(?:[.,]\d+)?)\s?%');
  static final _decimal = RegExp(r'\b(\d+)[.,](\d+)\b');
  static final _integer = RegExp(r'\d+');
  static final _acronym = RegExp(r'\b[A-Z]{2,5}\b');

  /// Lettura delle sigle ricorrenti; le altre parole in maiuscolo restano parole.
  static const Map<String, String> acronyms = {
    'IA': 'i a',
    'AI': 'a i',
    'CPU': 'ci pi u',
    'GPU': 'gi pi u',
    'RAM': 'ram',
    'ID': 'i di',
    'OK': 'okei',
    'USB': 'u esse bi',
    'IP': 'i pi',
    'DNA': 'di enne a',
    'LED': 'led',
  };

  /// Restituisce il testo pronto per la fonetica.
  String normalize(String text) {
    var t = text.replaceAll(_tags, ' ');
    t = t
        .replaceAll('…', '...')
        .replaceAll(_markup, ' ')
        .replaceAll(_quotes, '');
    t = t.replaceAll('’', "'").replaceAll('‘', "'");
    t = t.replaceAll('–', ',').replaceAll('—', ',');
    t = t.replaceAllMapped(_acronym, (m) => acronyms[m[0]!] ?? m[0]!);
    t = t.replaceAllMapped(_time, (m) {
      final h = int.parse(m[1]!);
      final min = int.parse(m[2]!);
      final hour = h == 1 ? 'una' : ItalianNumberWords.cardinal(h);
      return min == 0 ? hour : '$hour e ${ItalianNumberWords.cardinal(min)}';
    });
    t = t.replaceAllMapped(_percent, (m) => '${_number(m[1]!)} per cento');
    t = t.replaceAllMapped(_decimal, (m) => _number('${m[1]},${m[2]}'));
    t = t.replaceAllMapped(_integer, (m) => _number(m[0]!));
    final lines = t
        .split('\n')
        .map((l) => l.replaceAll(_spaces, ' ').trim())
        .where((l) => l.isNotEmpty);
    return lines.join('\n');
  }

  static String _number(String s) {
    final parts = s.split(RegExp('[.,]'));
    // «uno» isolato è un numerale tonico, non l'articolo atono.
    final whole = parts[0] == '1'
        ? 'ùno'
        : ItalianNumberWords.cardinal(int.parse(parts[0]));
    if (parts.length == 1) return whole;
    final digits = parts[1]
        .split('')
        .map((d) => ItalianNumberWords.cardinal(int.parse(d)));
    return '$whole virgola ${digits.join(' ')}';
  }
}

/// Numeri cardinali italiani in lettere.
abstract final class ItalianNumberWords {
  static const _units = [
    'zero', 'uno', 'due', 'tre', 'quattro', 'cinque', 'sei', 'sette', 'otto',
    'nove', //
    'dieci', 'undici', 'dodici', 'tredici', 'quattordici', 'quindici',
    'sedici', //
    'diciassette', 'diciotto', 'diciannove',
  ];
  static const _tens = [
    '', '', 'venti', 'trenta', 'quaranta', 'cinquanta', 'sessanta',
    'settanta', //
    'ottanta', 'novanta',
  ];

  /// Scrive [n] in lettere; oltre il miliardo restituisce le cifre una per una.
  static String cardinal(int n) {
    if (n < 0) return 'meno ${cardinal(-n)}';
    if (n >= 1000000000) {
      return n.toString().split('').map((d) => _units[int.parse(d)]).join(' ');
    }
    if (n < 20) return _units[n];
    if (n < 100) {
      final u = n % 10;
      var t = _tens[n ~/ 10];
      if (u == 1 || u == 8) t = t.substring(0, t.length - 1);
      return u == 0 ? t : '$t${_units[u]}';
    }
    if (n < 1000) {
      final rest = n % 100;
      final h = n ~/ 100 == 1 ? 'cento' : '${_units[n ~/ 100]}cento';
      if (rest == 0) return h;
      final r = cardinal(rest);
      return r.startsWith('o') ? '${h.substring(0, h.length - 1)}$r' : '$h$r';
    }
    if (n < 1000000) {
      final k = n ~/ 1000;
      final rest = n % 1000;
      final head = k == 1 ? 'mille' : '${cardinal(k)}mila';
      return rest == 0 ? head : '$head${cardinal(rest)}';
    }
    final m = n ~/ 1000000;
    final rest = n % 1000000;
    final head = m == 1 ? 'un milione' : '${cardinal(m)} milioni';
    return rest == 0 ? head : '$head ${cardinal(rest)}';
  }
}
