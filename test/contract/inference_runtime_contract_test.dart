import 'package:aura_core/aura_offline.dart';
import 'package:aura_core/aura_testing.dart';
import 'package:test/test.dart';
import 'runtime_contract_test_harness.dart';

void main() {
  group('Shared Contract Test Suite Executions -', () {
    runInferenceRuntimeContractTests(
      'MockInferenceRuntime',
      () async => MockInferenceRuntime(),
    );

    runInferenceRuntimeContractTests(
      'RuleBasedInferenceRuntime',
      () async => RuleBasedInferenceRuntime(),
    );
  });
}
