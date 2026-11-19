/// Famiglie a larghezza fissa reali da usare quando `fontFamily: 'monospace'`
/// non viene risolta dal sistema (Windows non espone una famiglia generica
/// "monospace"): senza fallback i caratteri di disegno del logo ASCII e
/// l'allineamento del terminale vengono resi con un font proporzionale.
const List<String> kTerminalFontFallback = [
  'Cascadia Mono',
  'Consolas',
  'Menlo',
  'DejaVu Sans Mono',
  'Courier New',
];
