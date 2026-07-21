import 'dart:io';
import 'package:test/test.dart';

// Import all entry points to verify they compile and can be resolved.
// ignore_for_file: unnecessary_import
import 'package:aura_core/aura_core.dart';
import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';

void main() {
  group('Architectural Entry Points Tests -', () {
    test('Verify all public entry points compile and can be instantiated', () {
      // GameState from aura_core.dart
      final state = GameState.initial(
        sessionId: 'test-api-check',
        aiIdentityId: 'panopticon',
        targetObjectiveId: 'containment_grid_override',
      );
      expect(state.sessionId, equals('test-api-check'));

      // ModelCatalog from aura_offline.dart
      final catalog = ModelCatalog.initialDefault();
      expect(catalog.models, isNotEmpty);

      // MockInferenceBridge from aura_testing.dart
      final mockBridge = MockInferenceBridge();
      expect(mockBridge, isA<InferenceBridge>());
    });

    test('Verify NO consumer files import deep package:aura_core/src/...', () {
      final rootDir = Directory.current;
      final targetDirs = ['bin', 'test', 'app/lib', 'app/test'];

      for (final dirName in targetDirs) {
        final dir = Directory('${rootDir.path}/$dirName');
        if (!dir.existsSync()) continue;

        final files = dir.listSync(recursive: true).whereType<File>();
        for (final file in files) {
          if (!file.path.endsWith('.dart')) continue;

          // Skip this test file itself since it might contain string patterns.
          if (file.path.endsWith('public_api_entrypoints_test.dart')) continue;

          final content = file.readAsStringSync();
          final hasDeepImport = content.contains(RegExp(
            r"import\s+['\u0022]package:aura_core/src/",
            caseSensitive: false,
          ));

          expect(
            hasDeepImport,
            isFalse,
            reason:
                'File ${file.path} contains a deep import of package:aura_core/src/. '
                'Only use the public entry points: '
                'package:aura_core/aura_core.dart, '
                'package:aura_core/aura_offline.dart, or '
                'package:aura_core/aura_testing.dart.',
          );
        }
      }
    });

    test('Verify aura_core.dart does not export offline/testing elements', () {
      final file = File('lib/aura_core.dart');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();

      final forbiddenExports = [
        'mock_inference_bridge.dart',
        'local_api_inference_bridge.dart',
        'rule_based_evaluator_bridge.dart',
        'rule_based_inference_runtime.dart',
        'mock_inference_runtime.dart',
        'runtime_contract_test_harness.dart',
        'evaluator_agent.dart',
        'actor_agent.dart',
        'model_catalog.dart',
        'model_router.dart',
        'agent_registry.dart',
        'message_envelope.dart',
      ];

      for (final export in forbiddenExports) {
        expect(
          content.contains(export),
          isFalse,
          reason: 'lib/aura_core.dart should not export $export',
        );
      }
    });

    test('Verify aura_offline.dart exports offline but not testing elements',
        () {
      final file = File('lib/aura_offline.dart');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();

      expect(content.contains("export 'aura_core.dart';"), isTrue);
      expect(content.contains('local_api_inference_bridge.dart'), isTrue);
      expect(content.contains('rule_based_inference_runtime.dart'), isTrue);
      expect(content.contains('evaluator_agent.dart'), isTrue);
      expect(content.contains('actor_agent.dart'), isTrue);
      expect(content.contains('model_catalog.dart'), isTrue);
      expect(content.contains('model_router.dart'), isTrue);

      // Should not export MockInferenceBridge or MockInferenceRuntime
      expect(content.contains('mock_inference_bridge.dart'), isFalse);
      expect(content.contains('mock_inference_runtime.dart'), isFalse);
      expect(content.contains('runtime_contract_test_harness.dart'), isFalse);
    });

    test(
        'Verify aura_testing.dart exports mock and offline agents for fallback, but not offline router/catalog',
        () {
      final file = File('lib/aura_testing.dart');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();

      expect(content.contains("export 'aura_core.dart';"), isTrue);
      expect(content.contains('mock_inference_bridge.dart'), isTrue);
      expect(content.contains('mock_inference_runtime.dart'), isTrue);
      expect(content.contains('evaluator_agent.dart'), isTrue);
      expect(content.contains('actor_agent.dart'), isTrue);
      expect(content.contains('rule_based_evaluator_bridge.dart'), isTrue);

      // Should not export offline router/catalog/registry
      expect(content.contains('local_api_inference_bridge.dart'), isFalse);
      expect(content.contains('model_catalog.dart'), isFalse);
      expect(content.contains('model_router.dart'), isFalse);
      expect(content.contains('agent_registry.dart'), isFalse);
      expect(content.contains('message_envelope.dart'), isFalse);
    });
  });
}
