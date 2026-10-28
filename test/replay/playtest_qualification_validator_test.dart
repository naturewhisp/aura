import 'dart:convert';
import 'dart:io';

import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('Playtest Qualification & Replay Validator (Fase 6.11.5)', () {
    // Fixture SINTETICA costruita a mano per esercitare il ramo positivo del
    // validatore. Non è un'evidenza di playtest e non deve mai essere citata
    // come tale nella matrice hardware.
    const fixturePath =
        'test/fixtures/replay/synthetic_validator_fixture_replay.json';

    Future<ProcessResult> runValidatorOn(Map<String, dynamic> json) async {
      final tempDir =
          await Directory.systemTemp.createTemp('aura_playtest_validator_');
      final tempFile = File('${tempDir.path}${Platform.pathSeparator}r.json');
      await tempFile.writeAsString(jsonEncode(json));
      try {
        return await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            'tool/replay/validate_playtest_replay.dart',
            '--replay',
            tempFile.path
          ],
        );
      } finally {
        await tempDir.delete(recursive: true);
      }
    }

    Map<String, dynamic> loadFixture() =>
        jsonDecode(File(fixturePath).readAsStringSync())
            as Map<String, dynamic>;

    test('CLI rifiuta modelli con SHA-256 dell\'input vuoto', () async {
      final json = loadFixture();
      final prov = Map<String, dynamic>.from(json['sessionProvenance'] as Map);
      prov['actorModelSha256'] =
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      json['sessionProvenance'] = prov;

      final result = await runValidatorOn(json);

      expect(result.exitCode, equals(1));
      expect(result.stderr.toString(), contains('input vuoto'));
    });

    test('CLI rifiuta turni senza snapshot di stato', () async {
      final json = loadFixture();
      final entries = (json['entries'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map)..['state_after'] = {})
          .toList();
      json['entries'] = entries;

      final result = await runValidatorOn(json);

      expect(result.exitCode, equals(1));
      expect(result.stderr.toString(), contains('privi di snapshot di stato'));
    });

    test('CLI rifiuta risposte con tag <dialogo> non rimossi', () async {
      final json = loadFixture();
      final entries = (json['entries'] as List).map((e) {
        final entry = Map<String, dynamic>.from(e as Map);
        entry['actor_response'] =
            '<dialogo>${entry['actor_response']}</dialogo>';
        return entry;
      }).toList();
      json['entries'] = entries;

      final result = await runValidatorOn(json);

      expect(result.exitCode, equals(1));
      expect(result.stderr.toString(), contains('tag <dialogo>'));
    });

    test('la fixture sintetica contiene 10 turni e provenance completa', () {
      final file = File(fixturePath);
      expect(file.existsSync(), isTrue);

      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final logger = ReplayLogger.fromJson(json);

      expect(logger.entries.length, equals(10));
      expect(logger.sessionProvenance, isNotNull);

      final prov = logger.sessionProvenance!;
      expect(prov.platform, equals('macos'));
      expect(prov.architecture, equals('arm64'));
      expect(prov.hardwareClass, equals('synthetic_fixture_arm64'));
      expect(prov.runtimeAcceleration, equals('metal'));
      expect(prov.datasetSource, equals(DatasetSource.humanPlaytest));

      for (final entry in logger.entries) {
        expect(entry.generationProvenance, isNotNull);
        final tps = entry.generationProvenance!
            .samplingParameters['tokens_per_second'] as num?;
        expect(tps, isNotNull);
        expect(tps!, greaterThan(0));
      }

      final validation = logger.validateProvenance();
      expect(validation.isValid, isTrue);
      expect(validation.isLoraTrainingEligible, isTrue);
    });

    test(
        'CLI validate_playtest_replay.dart valida con successo la fixture (exit code 0)',
        () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          'run',
          'tool/replay/validate_playtest_replay.dart',
          '--replay',
          fixturePath,
        ],
      );

      expect(result.exitCode, equals(0),
          reason: 'STDOUT: ${result.stdout}\nSTDERR: ${result.stderr}');
      expect(result.stdout.toString(), contains('PASS - PLAYTEST_VERIFIED'));
      expect(result.stdout.toString(),
          contains('Eleggibilita LoRA:      CERTIFICATA'));
      expect(result.stdout.toString(), contains('synthetic_fixture_arm64'));
    });

    test('CLI rifiuta replay con meno di 10 turni (exit code 1)', () async {
      final file = File(fixturePath);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final entries = json['entries'] as List;

      // Troncamento a 5 turni
      final shortJson = Map<String, dynamic>.from(json)
        ..['entries'] = entries.take(5).toList()
        ..['total_turns'] = 5;

      final tempFile = File('test/fixtures/replay/temp_short_replay.json');
      tempFile.writeAsStringSync(jsonEncode(shortJson));

      try {
        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            'tool/replay/validate_playtest_replay.dart',
            '--replay',
            tempFile.path,
          ],
        );

        expect(result.exitCode, equals(1));
        expect(result.stderr.toString(),
            contains('Numero di turni insufficiente per la qualifica: 5'));
      } finally {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      }
    });

    test('CLI rifiuta replay con architettura non corrispondente (exit code 1)',
        () async {
      final file = File(fixturePath);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final prov = Map<String, dynamic>.from(json['sessionProvenance'] as Map);
      prov['architecture'] = 'x86_64'; // Simulazione non-arm64
      final invalidJson = Map<String, dynamic>.from(json)
        ..['sessionProvenance'] = prov;

      final tempFile =
          File('test/fixtures/replay/temp_invalid_arch_replay.json');
      tempFile.writeAsStringSync(jsonEncode(invalidJson));

      try {
        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            'tool/replay/validate_playtest_replay.dart',
            '--replay',
            tempFile.path,
          ],
        );

        expect(result.exitCode, equals(1));
        expect(result.stderr.toString(), contains('Architecture mismatch'));
      } finally {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      }
    });

    test(
        'CLI rifiuta replay con sorgente non-humanPlaytest (es. syntheticSimulation)',
        () async {
      final file = File(fixturePath);
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final prov = Map<String, dynamic>.from(json['sessionProvenance'] as Map);
      prov['datasetSource'] = 'synthetic_simulation';
      final invalidJson = Map<String, dynamic>.from(json)
        ..['sessionProvenance'] = prov;

      final tempFile = File('test/fixtures/replay/temp_synth_replay.json');
      tempFile.writeAsStringSync(jsonEncode(invalidJson));

      try {
        final result = await Process.run(
          Platform.resolvedExecutable,
          [
            'run',
            'tool/replay/validate_playtest_replay.dart',
            '--replay',
            tempFile.path,
          ],
        );

        expect(result.exitCode, equals(1));
        expect(
            result.stderr.toString(), contains('DatasetSource non eleggibile'));
      } finally {
        if (tempFile.existsSync()) {
          tempFile.deleteSync();
        }
      }
    });
  });
}
