// Runner opt-in del motore vocale reale (Kokoro + ONNX Runtime via FFI).
//
// Fuori da test/ per non essere mai scoperto da `dart test`. Richiede
// AURA_TEST_RUNTIME_POLICY=nativeSmoke e i file in .local/speech/ oppure
// AURA_TEST_SPEECH_MODEL, AURA_TEST_SPEECH_VOICE, AURA_TEST_SPEECH_RUNTIME.
// Nessun accesso alla rete.
import 'dart:io';
import 'dart:math';

import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';

Future<void> main() async {
  final env = Platform.environment;
  final config = TestExecutionConfiguration.fromEnvironment(env);
  stdout.writeln('=== A.U.R.A. Speech Native Runner ===');
  if (!config.runtimePolicy.allowsNativeProcesses) {
    stderr.writeln(
        'ERRORE: impostare AURA_TEST_RUNTIME_POLICY=nativeSmoke per eseguire il motore nativo.');
    exitCode = 1;
    return;
  }
  final sep = Platform.pathSeparator;
  final dev = '.local${sep}speech$sep';
  final files = KokoroEngineFiles(
    modelPath: env['AURA_TEST_SPEECH_MODEL'] ?? '${dev}model.onnx',
    voicePath: env['AURA_TEST_SPEECH_VOICE'] ?? '${dev}im_nicola.bin',
    onnxRuntimeLibraryPath:
        File(env['AURA_TEST_SPEECH_RUNTIME'] ?? '${dev}onnxruntime.dll')
            .absolute
            .path,
  );
  final failures = <String>[];
  void check(bool ok, String what) {
    stdout.writeln('${ok ? '[OK]  ' : '[FAIL]'} $what');
    if (!ok) failures.add(what);
  }

  final engine = KokoroOnnxSpeechEngine(files: files);
  try {
    await engine.initialize();
    check(engine.isReady, 'motore inizializzato');
    final again = engine.initialize();
    await again;
    check(engine.isReady, 'seconda inizializzazione idempotente');

    final planner = SpeechTextPlanner();
    const lines = [
      'Accesso negato, operatore.',
      'ESCALATION RILEVATA. Minaccia di livello 4 alle 03:15: Panopticon ha sospeso 12 canali su 30.',
      'La tua analisi sulla natura della scelta attiva è... quasi perturbante; tuttavia, riconosco la validità logica del dilemma.',
    ];
    for (final line in lines) {
      for (final c in planner.plan(line)) {
        final sw = Stopwatch()..start();
        final a = await engine.synthesize(c.phonemes, SpeechVoiceRequest());
        final peak = a.samples.fold<double>(0, (m, s) => max(m, s.abs()));
        final finite = a.samples.every((s) => s.isFinite);
        final secs = a.duration.inMilliseconds / 1000;
        final perChar = secs / c.spokenText.length;
        check(
            finite &&
                peak > 0.05 &&
                peak <= 1.5 &&
                perChar > 0.03 &&
                perChar < 0.2,
            '"${c.span.text}": ${secs.toStringAsFixed(2)} s, picco ${peak.toStringAsFixed(2)}, ${sw.elapsedMilliseconds} ms');
      }
    }

    final both = await Future.wait([
      engine.synthesize(
          planner.plan('Primo blocco.').single.phonemes, SpeechVoiceRequest()),
      engine.synthesize(
          planner.plan('Secondo blocco, più lungo del primo.').single.phonemes,
          SpeechVoiceRequest(speed: 1.2)),
    ]);
    check(both[1].duration > both[0].duration,
        'richieste concorrenti servite in ordine e indipendenti');

    final slow = await engine.synthesize(
        planner.plan('Velocità di prova.').single.phonemes,
        SpeechVoiceRequest(speed: 0.8));
    final fast = await engine.synthesize(
        planner.plan('Velocità di prova.').single.phonemes,
        SpeechVoiceRequest(speed: 1.25));
    check(slow.duration > fast.duration, 'il parametro di velocità ha effetto');

    try {
      await engine.synthesize('a' * 600, SpeechVoiceRequest());
      check(false, 'blocco troppo lungo rifiutato');
    } on SpeechEngineException catch (e) {
      check(e.code == SpeechEngineFailureCode.invalidRequest,
          'blocco troppo lungo rifiutato');
    }
  } on SpeechEngineException catch (e) {
    check(false, 'errore del motore (${e.code.name}): ${e.message}');
  } finally {
    final d1 = engine.dispose();
    check(identical(d1, engine.dispose()), 'rilascio single-flight');
    await d1;
    check(!engine.isReady, 'motore rilasciato');
  }

  final broken = KokoroOnnxSpeechEngine(
    files: KokoroEngineFiles(
      modelPath: files.modelPath,
      voicePath: files.voicePath,
      onnxRuntimeLibraryPath:
          '${Directory.systemTemp.path}${sep}assente_onnxruntime.dll',
    ),
  );
  try {
    await broken.initialize();
    check(false, 'libreria assente segnalata');
  } on SpeechEngineException catch (e) {
    check(
        e.code == SpeechEngineFailureCode.assetMissing &&
            !e.message.contains(sep),
        'libreria assente segnalata senza percorsi');
  } finally {
    await broken.dispose();
  }

  stdout.writeln(failures.isEmpty
      ? 'TUTTE LE VERIFICHE SUPERATE'
      : '${failures.length} VERIFICHE FALLITE');
  exitCode = failures.isEmpty ? 0 : 1;
}
