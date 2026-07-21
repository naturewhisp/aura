@Tags(['network', 'real-model'])
library live_lm_studio_test;

import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

/// Opt-in integration test requiring an active LM Studio or OpenAI-compatible server
/// listening on http://127.0.0.1:1234.
///
/// Prerequisites:
/// 1. LM Studio (or compatible server) running locally on http://127.0.0.1:1234/v1.
/// 2. Model 'mistralai/ministral-3-3b' (or configured model) loaded in the server.
///
/// Run explicitly:
///   dart test integration_test/runtime/live_lm_studio_test.dart
void main() {
  group('Live LM Studio Integration Test -', () {
    test('Connects to live LM Studio endpoint and generates text', () async {
      const bridge = LocalApiInferenceBridge();

      try {
        final res = await bridge.generateText(
          modelId: 'mistralai/ministral-3-3b',
          messages: const [
            {'role': 'user', 'content': 'Ping'}
          ],
          maxTokens: 5,
        );
        expect(res, isNotEmpty);
      } catch (e) {
        fail(
          'Live LM Studio integration test failed. Ensure LM Studio server is running at http://127.0.0.1:1234 '
          'and model mistralai/ministral-3-3b is loaded. Underlying error: $e',
        );
      }
    });
  });
}
