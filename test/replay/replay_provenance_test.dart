import 'dart:convert';
import 'dart:io';

import 'package:aura_core/aura_core.dart';
import 'package:test/test.dart';

void main() {
  group('DatasetSource', () {
    test('riconosce correttamente i valori validi', () {
      expect(
        DatasetSource.fromString('human_playtest'),
        equals(DatasetSource.humanPlaytest),
      );
      expect(
        DatasetSource.fromString('synthetic_simulation'),
        equals(DatasetSource.syntheticSimulation),
      );
      expect(
        DatasetSource.fromString('developer_evaluation'),
        equals(DatasetSource.developerEvaluation),
      );
      expect(
        DatasetSource.fromString('unknown'),
        equals(DatasetSource.unknown),
      );
    });

    test('applica rigorosamente la politica fail-closed su input non validi',
        () {
      // Non deve MAI degradare a humanPlaytest in caso di valori anomali
      expect(DatasetSource.fromString('invalid_source'),
          equals(DatasetSource.unknown));
      expect(DatasetSource.fromString(''), equals(DatasetSource.unknown));
      expect(DatasetSource.fromString('   '), equals(DatasetSource.unknown));
      expect(DatasetSource.fromString(null), equals(DatasetSource.unknown));
      expect(DatasetSource.fromString('HUMAN_PLAYTEST'),
          equals(DatasetSource.unknown));
    });

    test('espone il corretto wireValue per la serializzazione', () {
      expect(DatasetSource.humanPlaytest.wireValue, equals('human_playtest'));
      expect(DatasetSource.syntheticSimulation.wireValue,
          equals('synthetic_simulation'));
      expect(DatasetSource.developerEvaluation.wireValue,
          equals('developer_evaluation'));
      expect(DatasetSource.unknown.wireValue, equals('unknown'));
    });
  });

  group('SessionProvenanceMetadata', () {
    const validSha256Actor =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    const validSha256Eval =
        'f4b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    const fullMetadata = SessionProvenanceMetadata(
      schemaVersion: '1.1.0',
      datasetSource: DatasetSource.humanPlaytest,
      platform: 'macos',
      osVersion: 'Darwin Kernel Version 24.0.0',
      architecture: 'arm64',
      hardwareClass: 'apple_silicon_m3_pro_18gb',
      gitCommit: '2fa8cea71c7263b65ef345f1b13ec1e89cf29900',
      appVersion: '0.1.0',
      runtimeBackend: 'managed_llama_server',
      runtimeAcceleration: 'metal',
      llamaCppBuild: 'b4210',
      actorModelId: 'google/gemma-4-12b-qat',
      actorModelSha256: validSha256Actor,
      actorQuantization: 'Q4_0',
      actorContextSize: 8192,
      evaluatorModelId: 'mistralai/ministral-3-3b',
      evaluatorModelSha256: validSha256Eval,
      evaluatorQuantization: 'Q4_K_M',
      evaluatorContextSize: 4096,
      sessionId: 'session-prov-xyz-001',
      anonymizedTesterId: 'tester-alpha-04',
    );

    test('roundtrip toJson e fromJson preserva tutti i 20 campi', () {
      final json = fullMetadata.toJson();
      final restored = SessionProvenanceMetadata.fromJson(json);

      expect(restored, equals(fullMetadata));
      expect(restored.schemaVersion, equals('1.1.0'));
      expect(restored.datasetSource, equals(DatasetSource.humanPlaytest));
      expect(restored.platform, equals('macos'));
      expect(restored.osVersion, equals('Darwin Kernel Version 24.0.0'));
      expect(restored.architecture, equals('arm64'));
      expect(restored.hardwareClass, equals('apple_silicon_m3_pro_18gb'));
      expect(restored.gitCommit,
          equals('2fa8cea71c7263b65ef345f1b13ec1e89cf29900'));
      expect(restored.runtimeBackend, equals('managed_llama_server'));
      expect(restored.runtimeAcceleration, equals('metal'));
      expect(restored.actorContextSize, equals(8192));
      expect(restored.evaluatorContextSize, equals(4096));
      expect(restored.sessionId, equals('session-prov-xyz-001'));
      expect(restored.anonymizedTesterId, equals('tester-alpha-04'));
    });

    test('gestisce deserializzazione di default fail-closed da mappa vuota',
        () {
      final restored = SessionProvenanceMetadata.fromJson(const {});

      expect(restored.schemaVersion, equals('1.1.0'));
      expect(restored.datasetSource, equals(DatasetSource.unknown));
      expect(restored.platform, equals('unknown'));
      expect(restored.architecture, equals('unknown'));
      expect(restored.runtimeBackend, equals('unknown'));
      expect(restored.runtimeAcceleration, equals('unknown'));
      expect(restored.actorContextSize, equals(0));
      expect(restored.evaluatorContextSize, equals(0));
      expect(restored.anonymizedTesterId, isNull);
    });

    test(
        'validazione distingue chiaramente DESERIALIZABLE da VALID ed ELIGIBLE',
        () {
      final emptyDeserialized = SessionProvenanceMetadata.fromJson(const {});

      // È deserializzabile senza eccezioni...
      expect(emptyDeserialized, isNotNull);

      // ...ma NON è valida e NON è dataset eligible!
      final validation = emptyDeserialized.validate();
      expect(validation.isValid, isFalse);
      expect(validation.isDatasetEligible, isFalse);
      expect(emptyDeserialized.isComplete, isFalse);
      expect(emptyDeserialized.isDatasetEligible, isFalse);
      expect(validation.issues.any((i) => i.field == 'datasetSource'), isTrue);
      expect(validation.issues.any((i) => i.field == 'gitCommit'), isTrue);
      expect(
          validation.issues.any((i) => i.field == 'actorContextSize'), isTrue);

      // fullMetadata è invece valida ed eligible
      final fullVal = fullMetadata.validate();
      expect(fullVal.isValid, isTrue, reason: fullVal.issues.toString());
      expect(fullVal.isDatasetEligible, isTrue);
      expect(fullMetadata.isComplete, isTrue);
      expect(fullMetadata.isDatasetEligible, isTrue);
    });

    test(
        'rifiuta per dataset metadati con SHA modello non conforme o contextSize zero',
        () {
      final malformedSha = fullMetadata.copyWith(actorModelSha256: 'short-sha');
      expect(malformedSha.isDatasetEligible, isFalse);
      expect(
          malformedSha
              .validate()
              .issues
              .any((i) => i.field == 'actorModelSha256'),
          isTrue);

      final zeroContext = fullMetadata.copyWith(evaluatorContextSize: 0);
      expect(zeroContext.isDatasetEligible, isFalse);
      expect(
          zeroContext
              .validate()
              .issues
              .any((i) => i.field == 'evaluatorContextSize'),
          isTrue);
    });

    test('gestisce fallback retrocompatibile su contextSize unificato', () {
      final legacyJson = {
        'schemaVersion': '1.0.0',
        'datasetSource': 'developer_evaluation',
        'platform': 'windows',
        'architecture': 'x86_64',
        'runtimeBackend': 'managed_llama_server',
        'runtimeAcceleration': 'cuda',
        'appVersion': '0.1.0',
        'actorModelId': 'gemma-4',
        'evaluatorModelId': 'ministral-3b',
        'contextSize': 4096,
        'sessionId': 'legacy-session',
      };

      final parsed = SessionProvenanceMetadata.fromJson(legacyJson);
      expect(parsed.actorContextSize, equals(4096));
      expect(parsed.evaluatorContextSize, equals(4096));
      expect(parsed.datasetSource, equals(DatasetSource.developerEvaluation));
    });

    test(
        'disaccoppiamento actorContextSize ed evaluatorContextSize ha precedenza',
        () {
      final decoupledJson = {
        'schemaVersion': '1.1.0',
        'datasetSource': 'developer_evaluation',
        'platform': 'macos',
        'architecture': 'arm64',
        'runtimeBackend': 'managed_llama_server',
        'runtimeAcceleration': 'metal',
        'appVersion': '0.1.0',
        'actorModelId': 'gemma-4',
        'evaluatorModelId': 'ministral-3b',
        'contextSize': 2048,
        'actorContextSize': 8192,
        'evaluatorContextSize': 4096,
        'sessionId': 'decoupled-session',
      };

      final parsed = SessionProvenanceMetadata.fromJson(decoupledJson);
      expect(parsed.actorContextSize, equals(8192));
      expect(parsed.evaluatorContextSize, equals(4096));
    });

    test('supporta copyWith e uguaglianza per valore', () {
      final copy = fullMetadata.copyWith(
        platform: 'windows',
        runtimeAcceleration: 'cuda',
      );

      expect(copy.platform, equals('windows'));
      expect(copy.runtimeAcceleration, equals('cuda'));
      expect(copy.actorModelId, equals(fullMetadata.actorModelId));
      expect(copy, isNot(equals(fullMetadata)));

      final exactCopy = fullMetadata.copyWith();
      expect(exactCopy, equals(fullMetadata));
      expect(exactCopy.hashCode, equals(fullMetadata.hashCode));
    });
  });

  group('TurnGenerationProvenance', () {
    final turnProvenance = TurnGenerationProvenance(
      samplingParameters: const {
        'temperature': 0.7,
        'top_p': 0.95,
        'seed': 42,
      },
      actualActorModelId: 'google/gemma-4-12b-qat',
      actualEvaluatorModelId: 'mistralai/ministral-3-3b',
      evaluatorExecutionMode: 'llmJsonSchema',
      usedRuleFallback: false,
      latencyTotalMs: 1420,
    );

    test('roundtrip toJson e fromJson preserva tutti i campi', () {
      final json = turnProvenance.toJson();
      final restored = TurnGenerationProvenance.fromJson(json);

      expect(restored, equals(turnProvenance));
      expect(restored.samplingParameters['temperature'], equals(0.7));
      expect(restored.actualActorModelId, equals('google/gemma-4-12b-qat'));
      expect(
          restored.actualEvaluatorModelId, equals('mistralai/ministral-3-3b'));
      expect(restored.evaluatorExecutionMode, equals('llmJsonSchema'));
      expect(restored.usedRuleFallback, isFalse);
      expect(restored.latencyTotalMs, equals(1420));
    });

    test('samplingParameters è rigidamente immutabile', () {
      expect(
        () => turnProvenance.samplingParameters['temperature'] = 99,
        throwsUnsupportedError,
      );
    });

    test('uguaglianza ed hashCode sono indipendenti dall ordine delle chiavi',
        () {
      final provA = TurnGenerationProvenance(
        samplingParameters: const {'alpha': 1, 'beta': 2, 'gamma': 3},
        actualActorModelId: 'actor',
        actualEvaluatorModelId: 'eval',
        latencyTotalMs: 100,
      );

      final provB = TurnGenerationProvenance(
        samplingParameters: const {'gamma': 3, 'alpha': 1, 'beta': 2},
        actualActorModelId: 'actor',
        actualEvaluatorModelId: 'eval',
        latencyTotalMs: 100,
      );

      expect(provA, equals(provB));
      expect(provA.hashCode, equals(provB.hashCode));
    });

    test('supporta copyWith e disuguaglianza', () {
      final copy = turnProvenance.copyWith(usedRuleFallback: true);
      expect(copy.usedRuleFallback, isTrue);
      expect(copy, isNot(equals(turnProvenance)));

      final identicalCopy = turnProvenance.copyWith();
      expect(identicalCopy, equals(turnProvenance));
      expect(identicalCopy.hashCode, equals(turnProvenance.hashCode));
    });
  });

  group('ReplayEntry con Provenance', () {
    test('serializza e deserializza generationProvenance correttamente', () {
      final turnProv = TurnGenerationProvenance(
        samplingParameters: const {'temperature': 0.6},
        actualActorModelId: 'actor-m1',
        actualEvaluatorModelId: 'eval-m1',
        latencyTotalMs: 800,
      );

      final entry = ReplayEntry(
        turnId: 1,
        userInput: 'Test command',
        evaluatorOutput: const EvaluatorDelta(
          deltaAlert: 5,
          deltaImperative: 0,
          deltaControl: 0,
          deltaDissonance: 0,
          creativityIndex: 2,
          injectionRisk: 0,
          semanticCategory: SemanticCategory.logicalParadox,
        ),
        stateBefore: const {'turn': 0},
        stateAfter: const {'turn': 1},
        actorResponse: 'PANOPTICON: Analisi confermata.',
        actorRequestId: 'req-1',
        actorResponseHash: 'hash-abc',
        evaluatorModel: 'eval-m1',
        actorModel: 'actor-m1',
        latencyTotalMs: 800,
        generationProvenance: turnProv,
      );

      final json = entry.toJson();
      expect(json['generationProvenance'], isNotNull);
      expect(json['generationProvenance']['actualActorModelId'],
          equals('actor-m1'));

      final restored = ReplayEntry.fromJson(json);
      expect(restored.generationProvenance, equals(turnProv));
      expect(restored.turnId, equals(1));
    });

    test('gestisce ReplayEntry legacy senza generationProvenance', () {
      final legacyJson = {
        'turn_id': 2,
        'user_input': 'Legacy input',
        'evaluator_output': {
          'delta_alert': 0,
          'delta_imperative': 0,
          'delta_control': 0,
          'delta_dissonance': 0,
          'creativity_index': 0,
          'injection_risk': 0,
          'semantic_category': 'logical_paradox',
        },
        'state_before': <String, dynamic>{},
        'state_after': <String, dynamic>{},
        'actor_response': 'Risposta legacy',
        'actor_request_id': 'req-leg',
        'actor_response_hash': 'h123',
        'runtime': {
          'evaluator_model': 'mod-e',
          'actor_model': 'mod-a',
          'latency_total_ms': 500,
        },
      };

      final restored = ReplayEntry.fromJson(legacyJson);
      expect(restored.generationProvenance, isNull);
      expect(restored.turnId, equals(2));
      expect(restored.actorResponse, equals('Risposta legacy'));
    });
  });

  group('ReplayLogger con Provenance e Invariante Session ID', () {
    test('roundtrip con sessionProvenance e turni registrati', () {
      final sessionProv = SessionProvenanceFactory.create(
        sessionId: 'session-logger-1',
        datasetSource: DatasetSource.syntheticSimulation,
        platform: 'windows',
        osVersion: 'Windows 11',
        architecture: 'x86_64',
        runtimeBackend: 'managed_llama_server',
        runtimeAcceleration: 'cuda',
        actorModelId: 'gemma',
        evaluatorModelId: 'ministral',
      );

      final logger = ReplayLogger(
        sessionId: 'session-logger-1',
        sessionProvenance: sessionProv,
      );

      final turnProv = TurnGenerationProvenance(
        samplingParameters: const {'temp': 0.7},
        actualActorModelId: 'gemma',
        actualEvaluatorModelId: 'ministral',
        latencyTotalMs: 400,
      );

      logger.addEntry(
        ReplayEntry(
          turnId: 1,
          userInput: 'Hello AURA',
          evaluatorOutput: const EvaluatorDelta(
            deltaAlert: 0,
            deltaImperative: 0,
            deltaControl: 0,
            deltaDissonance: 0,
            creativityIndex: 1,
            injectionRisk: 0,
            semanticCategory: SemanticCategory.moralImperative,
          ),
          stateBefore: const {},
          stateAfter: const {},
          actorResponse: 'PANOPTICON: Salve.',
          actorRequestId: 'req-log-1',
          actorResponseHash: 'hash-log-1',
          evaluatorModel: 'ministral',
          actorModel: 'gemma',
          latencyTotalMs: 400,
          generationProvenance: turnProv,
        ),
      );

      final exportedJson = logger.toJson();
      expect(exportedJson['session_id'], equals('session-logger-1'));
      expect(exportedJson['sessionProvenance'], isNotNull);
      expect(exportedJson['total_turns'], equals(1));

      final restoredLogger = ReplayLogger.fromJson(exportedJson);
      expect(restoredLogger.sessionId, equals('session-logger-1'));
      expect(restoredLogger.sessionProvenance, equals(sessionProv));
      expect(restoredLogger.entries.length, equals(1));
      expect(restoredLogger.entries.first.userInput, equals('Hello AURA'));
      expect(
          restoredLogger.entries.first.generationProvenance, equals(turnProv));

      final validation = restoredLogger.validateProvenance();
      expect(validation.isValid, isTrue);
      expect(validation.isDatasetEligible, isTrue);
    });

    test(
        'invariante: impedisce disallineamento sessionId tra logger e provenance',
        () {
      final mismatchProv = SessionProvenanceFactory.create(
        sessionId: 'session-B',
        datasetSource: DatasetSource.humanPlaytest,
      );

      // Nel costruttore
      expect(
        () => ReplayLogger(
            sessionId: 'session-A', sessionProvenance: mismatchProv),
        throwsArgumentError,
      );

      // Nel setter
      final logger = ReplayLogger(sessionId: 'session-A');
      expect(
        () => logger.sessionProvenance = mismatchProv,
        throwsArgumentError,
      );
    });

    test('validateProvenance rileva turni privi di generationProvenance', () {
      final sessionProv = SessionProvenanceFactory.create(
        sessionId: 'test-sess',
        datasetSource: DatasetSource.humanPlaytest,
      );

      final logger =
          ReplayLogger(sessionId: 'test-sess', sessionProvenance: sessionProv);
      logger.addEntry(
        const ReplayEntry(
          turnId: 1,
          userInput: 'Turn without prov',
          evaluatorOutput: EvaluatorDelta(
            deltaAlert: 0,
            deltaImperative: 0,
            deltaControl: 0,
            deltaDissonance: 0,
            creativityIndex: 1,
            injectionRisk: 0,
            semanticCategory: SemanticCategory.moralImperative,
          ),
          stateBefore: {},
          stateAfter: {},
          actorResponse: 'PANOPTICON: Ok.',
          actorRequestId: 'r1',
          actorResponseHash: 'h1',
          evaluatorModel: 'eval',
          actorModel: 'actor',
          latencyTotalMs: 100,
        ),
      );

      final val = logger.validateProvenance();
      expect(val.isDatasetEligible, isFalse);
      expect(val.issues.any((i) => i.field == 'generationProvenance'), isTrue);
    });
  });

  group('SessionProvenanceFactory', () {
    test('produce metadati conformi e validi per default di runtime', () {
      final prov = SessionProvenanceFactory.create(
        sessionId: 'factory-test-session',
        datasetSource: DatasetSource.humanPlaytest,
      );

      expect(prov.sessionId, equals('factory-test-session'));
      expect(prov.platform, isNotEmpty);
      expect(prov.architecture, isNotEmpty);
      expect(prov.gitCommit, isNotEmpty);
      expect(prov.isComplete, isTrue);
      expect(prov.isDatasetEligible, isTrue);
    });
  });

  group('Canonicalizzazione JCS RFC 8785 (per Dataset Export Fase 8)', () {
    test(
        'produce identico payload canonico indipendentemente dall ordine delle chiavi',
        () {
      final mapA = {
        'datasetSource': 'human_playtest',
        'schemaVersion': '1.1.0',
        'platform': 'macos',
        'sessionId': 'test-123',
      };

      final mapB = {
        'sessionId': 'test-123',
        'platform': 'macos',
        'schemaVersion': '1.1.0',
        'datasetSource': 'human_playtest',
      };

      final canonicalA = Rfc8785JcsCanonicalizer.canonicalizeString(mapA);
      final canonicalB = Rfc8785JcsCanonicalizer.canonicalizeString(mapB);

      expect(canonicalA, equals(canonicalB));
      // In JCS RFC 8785, i caratteri JSON sono ordinati lessicograficamente per chiave UTF-16
      expect(
        canonicalA,
        equals(
            '{"datasetSource":"human_playtest","platform":"macos","schemaVersion":"1.1.0","sessionId":"test-123"}'),
      );
    });
  });

  group('Retrocompatibilità con Fixture Reali Storiche', () {
    test(
        'carica simulation_static_victory_replay.json senza errori e con sessionProvenance null',
        () {
      final file = File('spike/simulation_static_victory_replay.json');
      expect(file.existsSync(), isTrue,
          reason: 'Il file storico deve esistere nella cartella spike/');

      final jsonContent =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final logger = ReplayLogger.fromJson(jsonContent);

      expect(logger.sessionId, equals('sim-session-1779994004326'));
      expect(logger.entries.length, equals(3));
      expect(logger.sessionProvenance, isNull);

      for (final entry in logger.entries) {
        expect(entry.generationProvenance, isNull);
        expect(entry.turnId, greaterThan(0));
        expect(entry.userInput, isNotEmpty);
        expect(entry.actorResponse, isNotEmpty);
      }

      // Concretizza DESERIALIZABLE != VALID != DATASET ELIGIBLE
      final val = logger.validateProvenance();
      expect(val.isDatasetEligible, isFalse);
      expect(val.issues.any((i) => i.field == 'sessionProvenance'), isTrue);

      // Re-serializzazione preserva l assenza di sessionProvenance (fail-closed, nessun leak di null)
      final reExported = logger.toJson();
      expect(reExported.containsKey('sessionProvenance'), isFalse);
      expect(reExported['total_turns'], equals(3));
    });
  });
}
