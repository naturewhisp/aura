// Strumento di sviluppo: sintetizza una battuta con il motore vocale Kokoro.
//
// Uso:
//   dart run tool/speech/aura_speak.dart --testo "Accesso negato." --uscita prova.wav
//   dart run tool/speech/aura_speak.dart --file battute.txt --uscita cartella
//
// I file del motore si cercano in .local/speech/ (model.onnx, im_nicola.bin,
// onnxruntime.dll) oppure si indicano con --modello, --voce e --runtime.

import 'dart:io';
import 'dart:typed_data';

import 'package:aura_core/aura_offline.dart';

const _usage = '''
Uso: dart run tool/speech/aura_speak.dart (--testo <testo> | --file <file>) --uscita <percorso>
       [--modello <model.onnx>] [--voce <voce.bin>] [--runtime <onnxruntime.dll>]
       [--thread <n>] [--velocita <0.5-2.0>]

Con --testo, --uscita è un file .wav. Con --file (una battuta per riga), --uscita è una cartella.''';

Future<void> main(List<String> args) async {
  final Map<String, String> opts;
  try {
    opts = _parse(args);
  } on FormatException catch (e) {
    stderr.writeln('ERRORE: ${e.message}\n\n$_usage');
    exitCode = 1;
    return;
  }
  final sep = Platform.pathSeparator;
  final dev = '.local${sep}speech$sep';
  final files = KokoroEngineFiles(
    modelPath: opts['modello'] ?? '${dev}model.onnx',
    voicePath: opts['voce'] ?? '${dev}im_nicola.bin',
    onnxRuntimeLibraryPath:
        File(opts['runtime'] ?? '${dev}onnxruntime.dll').absolute.path,
  );
  final int threads;
  final double speed;
  try {
    threads = int.parse(opts['thread'] ?? '4');
    speed = double.parse(opts['velocita'] ?? '1.0');
    if (threads < 1 || threads > 64)
      throw const FormatException('--thread fuori intervallo');
  } on FormatException {
    stderr.writeln(
        'ERRORE: valori non validi per --thread o --velocita.\n\n$_usage');
    exitCode = 1;
    return;
  }
  final lines = opts.containsKey('testo')
      ? [opts['testo']!]
      : File(opts['file']!)
          .readAsLinesSync()
          .where((l) => l.trim().isNotEmpty)
          .toList();

  final engine = KokoroOnnxSpeechEngine(files: files, threads: threads);
  final planner = SpeechTextPlanner();
  final request = SpeechVoiceRequest(speed: speed);
  try {
    final start = Stopwatch()..start();
    await engine.initialize();
    stdout.writeln(
        'Motore pronto in ${start.elapsedMilliseconds} ms (${engine.id}, $threads thread).');
    for (var i = 0; i < lines.length; i++) {
      final chunks = planner.plan(lines[i]);
      final w = Stopwatch()..start();
      int? firstMs;
      final samples = <double>[];
      for (final c in chunks) {
        final audio = await engine.synthesize(c.phonemes, request);
        firstMs ??= w.elapsedMilliseconds;
        samples.addAll(audio.samples);
      }
      final audio = SpeechAudio(
        samples: Float32List.fromList(samples),
        sampleRate: KokoroOnnxSpeechEngine.sampleRate,
      );
      final out = opts.containsKey('testo')
          ? opts['uscita']!
          : '${opts['uscita']}${sep}battuta_${i + 1}.wav';
      File(out).parent.createSync(recursive: true);
      File(out).writeAsBytesSync(encodePcm16Wav(audio));
      final secs = audio.duration.inMilliseconds / 1000;
      final rt = secs / (w.elapsedMilliseconds / 1000);
      stdout.writeln(
          '${i + 1}: ${chunks.length} blocchi, ${secs.toStringAsFixed(1)} s di voce, '
          'primo audio ${firstMs ?? 0} ms, ${rt.toStringAsFixed(1)}x tempo reale -> $out');
    }
  } on SpeechEngineException catch (e) {
    stderr.writeln('ERRORE (${e.code.name}): ${e.message}');
    exitCode = 1;
  } finally {
    await engine.dispose();
  }
}

Map<String, String> _parse(List<String> args) {
  const known = {
    'testo',
    'file',
    'uscita',
    'modello',
    'voce',
    'runtime',
    'thread',
    'velocita'
  };
  final out = <String, String>{};
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--') || !known.contains(a.substring(2))) {
      throw FormatException('opzione sconosciuta: $a');
    }
    if (i + 1 >= args.length) throw FormatException('valore mancante per $a');
    out[a.substring(2)] = args[++i];
  }
  if (out.containsKey('testo') == out.containsKey('file')) {
    throw const FormatException('indicare una sola tra --testo e --file');
  }
  if (!out.containsKey('uscita'))
    throw const FormatException('--uscita obbligatoria');
  return out;
}
