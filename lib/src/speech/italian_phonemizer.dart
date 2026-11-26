import 'package:meta/meta.dart';

part 'italian_phonemizer_data.dart';

class _Seg {
  _Seg(this.s, this.n, this.a);
  final String s;
  final bool n, a;
}

/// Trascrizione fonetica dell'italiano scritto nei simboli attesi dal modello vocale.
///
/// Deriva dalle regole ortografiche italiane e da un lessico proprio di A.U.R.A.
/// (accento tonico, timbro di «e» e «o», sonorità della «z»); non usa espeak-ng.
/// L'ingresso deve essere già normalizzato (vedi [SpeechTextNormalizer]).
@immutable
class ItalianPhonemizer {
  ItalianPhonemizer()
      : _re = {for (final e in _patterns.entries) e.key: RegExp(e.value)};

  final Map<String, RegExp> _re;
  Map<String, String> get _lex => _foreignLexicon;
  Map<String, String> get _own => _stressLexicon;
  Set<String> get _atone => _atone_;
  Set<String> get _atone2 => _atone2_;
  static const _v = 'aeiouàèéìòóù';
  static const _acc = {
    'à': 'a',
    'è': 'ɛ',
    'é': 'e',
    'ì': 'i',
    'ò': 'ɔ',
    'ó': 'o',
    'ù': 'u'
  };
  bool _m(String k, String w) => _re[k]!.hasMatch(w);

  List<_Seg> _rules(String w) {
    final o = <_Seg>[];
    final n = w.length;
    var i = 0;
    String nx(int k) => i + k < n ? w[i + k] : '';
    bool inV(String c) => c.isNotEmpty && _v.contains(c);
    while (i < n) {
      final c = w[i];
      if (inV(c)) {
        if (c == 'i' && inV(nx(1)) && i > 0) {
          o.add(_Seg('j', false, false));
        } else if (c == 'u' &&
            inV(nx(1)) &&
            (i == 0 || 'qg'.contains(w[i - 1]))) {
          o.add(_Seg('w', false, false));
        } else {
          o.add(_Seg(_acc[c] ?? c, true, _acc.containsKey(c)));
        }
        i++;
        continue;
      }
      final dbl = nx(1) == c;
      if (dbl) i++;
      final s = w.substring(i);
      final g = dbl ? 'ː' : '';
      void p(String x, int k) {
        o.add(_Seg(x + g, false, false));
        i += k;
      }

      bool front(int k) => s.length > k && 'eièéì'.contains(s[k]);
      if (s.startsWith('sci') && s.length > 3 && inV(s[3])) {
        p('ʃ', 3);
      } else if (s.startsWith('sc') && front(2)) {
        p('ʃ', 2);
      } else if (s.startsWith('gli') && s.length > 3 && inV(s[3])) {
        p('ʎ', 3);
      } else if (s.startsWith('gli')) {
        p('ʎ', 2);
      } else if (s.startsWith('gn')) {
        p('ɲ', 2);
      } else if (s.startsWith('ch')) {
        p('k', 2);
      } else if (s.startsWith('gh')) {
        p('ɡ', 2);
      } else if (s.startsWith('qu')) {
        p('k', 1);
      } else if (c == 'c' && front(1)) {
        p('ʧ', s[1] == 'i' && s.length > 2 && inV(s[2]) ? 2 : 1);
      } else if (c == 'g' && front(1)) {
        p('ʤ', s[1] == 'i' && s.length > 2 && inV(s[2]) ? 2 : 1);
      } else if (c == 's') {
        final a = i > 0 ? w[i - 1] : '';
        final b = s.length > 1 ? s[1] : '';
        p(
            (!dbl && inV(a) && inV(b)) ||
                    (b.isNotEmpty && 'bdglmnrv'.contains(b))
                ? 'z'
                : 's',
            1);
      } else if (c == 'z') {
        p('ʦ', 1);
      } else if (c == 'x') {
        p('ks', 1);
      } else if (c == 'y') {
        p('j', 1);
      } else if (c == 'h') {
        i++;
      } else {
        p(const {'c': 'k', 'g': 'ɡ', 'q': 'k'}[c] ?? c, 1);
      }
    }
    return o;
  }

  List<_Seg> _nuclei(String w) {
    final o = _rules(w);
    final r = <_Seg>[];
    for (var k = 0; k < o.length; k++) {
      var s = o[k].s;
      var n = o[k].n;
      final a = o[k].a;
      final prev = r.isEmpty ? null : r.last;
      if (n &&
          !a &&
          (s == 'i' || s == 'u') &&
          prev != null &&
          prev.n &&
          'aeoɛɔ'.contains(prev.s)) {
        s = s == 'i' ? 'j' : 'w';
        n = false;
      }
      if (n &&
          (s == 'o' || s == 'e') &&
          prev != null &&
          prev.s == 'u' &&
          prev.n &&
          !prev.a &&
          k != o.length - 1) {
        r[r.length - 1] = _Seg('w', false, false);
      }
      r.add(_Seg(s, n, a));
    }
    if (r.where((x) => x.n).length == 1) {
      final k = r.indexWhere((x) => x.s == 'j');
      if (k >= 0 && k + 1 == r.length - 1 && r[k + 1].n)
        r[k] = _Seg('i', true, true);
    }
    return r;
  }

  static final _clG = RegExp(r'[ae]ndo(mi|ti|ci|vi|l[oaie]|ne|si|gli)$');
  static final _clI = RegExp(r'[aeiou]r(mi|ti|ci|vi|l[oaie]|ne|si|gli)$');
  static final _cl = RegExp(r'(mi|ti|ci|vi|l[oaie]|ne|si|gli)$');
  static final _iato = RegExp(
      r'(logi|nomi|metri|grafi|sofi|pati|archi|teri|ergi|troni|mani|fobi)[ae]$');

  String _w2(String w) {
    if (_lex.containsKey(w)) return _lex[w]!;
    final own = _own[w];
    final o = _nuclei(own ?? w);
    final nuc = [
      for (var k = 0; k < o.length; k++)
        if (o[k].n) k
    ];
    if (nuc.isEmpty) return o.map((x) => x.s).join();
    final g = nuc.where((k) => o[k].a).toList();
    final n = nuc.length;
    int at(int back) => nuc[n - back];
    int? t;
    if (_atone2.contains(w) && own == null) {
      t = null;
    } else if (g.isNotEmpty) {
      t = g.last;
    } else if (n == 1) {
      t = nuc[0];
    } else if (RegExp(r'[aeo]i$').hasMatch(w) && own == null) {
      t = at(1);
    } else if (_clG.hasMatch(w) && n > 2) {
      t = at(3);
    } else if (_clI.hasMatch(w) && n > 2) {
      final st = w.replaceFirst(_cl, '');
      t = st.endsWith('er') && !_m('PIANE_ERE', st) ? at(3) : at(2);
    } else if (RegExp(r'[aei]r$').hasMatch(w)) {
      t = 'ai'.contains(w[w.length - 2]) ? at(1) : at(2);
    } else if (w.endsWith('ere') && n > 2) {
      t = _m('PIANE_ERE', w) || w.endsWith('iere') ? at(2) : at(3);
    } else if (n > 2 &&
        w.endsWith('ano') &&
        !_m('AMB_ANO', w) &&
        !w.endsWith('iano')) {
      t = at(3);
    } else if (n > 2 &&
        w.endsWith('ono') &&
        !_m('PIANE_ONO', w) &&
        !w.endsWith('iono')) {
      t = at(3);
    } else if (n > 2 && _m('SDR', w) && !_m('PIANE_ICO', w)) {
      t = at(3);
    } else if (n > 2 && RegExp(r'[^aeiougq](e[oa]|uo|ua)$').hasMatch(w)) {
      t = at(3);
    } else if (_iato.hasMatch(w)) {
      final j = o.lastIndexWhere((x) => x.s == 'j');
      if (j >= 0) {
        o[j] = _Seg('i', true, true);
        t = j;
      } else {
        t = at(2);
      }
    } else if (!_v.contains(w[w.length - 1]) && n > 1) {
      t = w.endsWith('on') || w.endsWith('un') ? at(1) : at(2);
    } else {
      t = at(2);
    }
    final b = StringBuffer();
    for (var k = 0; k < o.length; k++) {
      if (k == t) b.write('ˈ');
      b.write(o[k].s);
    }
    return b.toString();
  }

  static final _ton = RegExp('ˈ([jw]?)([eo])');
  String _w3(String w) {
    if (_lex.containsKey(w)) return _lex[w]!;
    final p = _w2(w);
    final m = _ton.firstMatch(p);
    if (m == null || (_own.containsKey(w) && RegExp('[éó]').hasMatch(_own[w]!)))
      return p;
    if ('éó'.contains(w[w.length - 1])) return p;
    final gl = m.group(1)!, v = m.group(2)!, tail = p.substring(m.end);
    final nd = RegExp('[aeiouɛɔ]').allMatches(tail).length;
    final before = m.start > 0 ? p[m.start - 1] : '';
    bool op;
    if (v == 'e') {
      if (RegExp(
              r'(rilev|sollev|rivest|rest|perd|merc|pen?etr|cautel|ciec|terz|legger|cre)[aeoi]$|influenz[ai]$|influenzano$|(^|s)ciec(hi|he)$|cautel')
          .hasMatch(w)) {
        op = true;
      } else if (w.contains('pieg')) {
        op = false;
      } else if (before == 'j' || gl == 'j') {
        op =
            !RegExp(r'(iezz|iett[oaie]$|iement|iev[oaie]$_|ieno_)').hasMatch(w);
      } else if (RegExp(r'(ment[eoi]|ezz[ae]|essa|esse)$').hasMatch(w) &&
          !RegExp(r'(process|access|compless)').hasMatch(w)) {
        op = RegExp(r'(process|success|access|compless)[oaie]$').hasMatch(w);
      } else if (nd >= 2) {
        op = !_m('E_CHIUSE3', w);
      } else {
        op = _m('E_APERTE', w) &&
            !RegExp(r'^(mentre|entro|entra|dentro|quest.|quell.|stess.|premess.|compromess.|permess.|emess.|trasmess.|rimess.|mess.|scommess.|promess.|ess.|sess.|protett.|strett.|ristrett.|tre|sera|vera|vero|merce|parete|rete|fede|leggero|ment[ei]|sement.)$')
                .hasMatch(w);
      }
    } else {
      if (before == 'w' ||
          gl == 'w' ||
          w == 'suoi' ||
          w == 'tuoi' ||
          _m('COSA', w)) {
        op = true;
      } else {
        op = !(_m('O_CHIUSE', w) ||
                RegExp(r'[nm](?![aeiouɛɔjwnm])|rs[aeo]|rre|rm[aeio]$')
                        .matchAsPrefix(tail) !=
                    null ||
                RegExp(r'(post[oaie]|(dott|rott|ridott)[oaie]|mostr[aeoi]|ascolt[oaie]|risors[ae]|forz[ae]_|scansiono|torr.|corr.)$')
                    .hasMatch(w)) ||
            RegExp(r'(forte|morte|porta|norma|enorme|^corpo|oste|^costo)$')
                .hasMatch(w);
      }
    }
    return op
        ? '${p.substring(0, m.start)}ˈ$gl${v == 'e' ? 'ɛ' : 'ɔ'}$tail'
        : p;
  }

  static final _zIni = RegExp(r'z(i[oaei]|ucch|amp|upp|app|itt|olf|opp)');
  static final _zj = RegExp('([ʦʣ]ː?|z)j(?=ˈ?[aeouɛɔ])');
  static final _numeralS = RegExp(
    r'^(venti|trenta|quaranta|cinquanta|sessanta|settanta|ottanta|novanta|cento|mila)s(ei|ette)$',
  );

  String _word(String w) {
    var p = _w3(w);
    if (_lex.containsKey(w)) return p;
    // Nei numerali composti («ventisei», «trentasette») la «s» resta sorda.
    if (_numeralS.hasMatch(w)) p = p.replaceFirst(RegExp(r'z(?=ˈ?[eɛ])'), 's');
    if (_atone.contains(w)) p = p.replaceAll('ˈ', '');
    if (w.contains('z')) {
      final zs = RegExp('zz?').allMatches(w).toList();
      var k = 0;
      p = p.replaceAllMapped('ʦ', (m) {
        if (k >= zs.length) return m.group(0)!;
        final z = zs[k++];
        final s = w.substring(z.start > 0 ? z.start - 1 : 0, z.end);
        final son =
            (s.startsWith('i') && s.endsWith('zz') && !_m('IZZ_SORDE', w)) ||
                _m('SONORE', w) ||
                (z.start == 0 && _zIni.matchAsPrefix(w) == null);
        return son ? 'ʣ' : 'ʦ';
      });
    }
    return p.replaceAllMapped(_zj, (m) => '${m.group(1)}i');
  }

  static final _tok = RegExp('[a-zàèéìòóù]+|[^a-zàèéìòóù]+');

  /// Restituisce la trascrizione fonetica di [t], parola per parola.
  ///
  /// Punteggiatura e spazi restano al loro posto; gli apostrofi vengono rimossi.
  String transcribe(String t) {
    t = t.toLowerCase().replaceAll('’', "'").replaceAll('…', '...');
    final b = StringBuffer();
    for (final m in _tok.allMatches(t)) {
      final x = m.group(0)!;
      b.write(RegExp('[a-zàèéìòóù]').hasMatch(x[0])
          ? _word(x)
          : x.replaceAll("'", ''));
    }
    return b
        .toString()
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll('sː', 'S')
        .replaceAll('lː', 'll')
        .replaceAll('mː', 'mm')
        .replaceAll('nː', 'nn')
        .replaceAll('rː', 'rɾ')
        .replaceAll('g', 'ɡ');
  }
}
