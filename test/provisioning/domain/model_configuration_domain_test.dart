import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('Tranche 6.4f.1 — ConfiguredModelReference Tests', () {
    test(
        'ManagedModelReference serializza e deserializza in JSON correttamente',
        () {
      final ref = ManagedModelReference(installationId: 'inst_actor_123');
      final json = ref.toJson();

      expect(json['kind'], equals('managed'));
      expect(json['installationId'], equals('inst_actor_123'));

      final parsed = ConfiguredModelReference.fromJson(json);
      expect(parsed, equals(ref));
      expect(parsed, isA<ManagedModelReference>());
    });

    test(
        'ExternalModelReference serializza e deserializza in JSON correttamente',
        () {
      final ref =
          ExternalModelReference(absolutePath: r'C:\Models\custom.gguf');
      final json = ref.toJson();

      expect(json['kind'], equals('external'));
      expect(json['absolutePath'], equals(r'C:\Models\custom.gguf'));

      final parsed = ConfiguredModelReference.fromJson(json);
      expect(parsed, equals(ref));
      expect(parsed, isA<ExternalModelReference>());
    });

    test(
        'ManagedModelReference e ExternalModelReference rifiutano valori vuoti',
        () {
      expect(
        () => ManagedModelReference(installationId: '   '),
        throwsArgumentError,
      );
      expect(
        () => ExternalModelReference(absolutePath: ''),
        throwsArgumentError,
      );
    });
  });

  group('Tranche 6.4f.1 — LlamaServerConfiguration & Models Tests', () {
    test('LlamaServerConfiguration serializza e deserializza con status', () {
      final now = DateTime.now().toUtc();
      final config = LlamaServerConfiguration(
        executablePath: r'C:\Tools\llama-server.exe',
        detectedVersion: 'b3450',
        lastValidatedAtUtc: now,
        validationStatus: LlamaServerValidationStatus.valid,
      );

      final json = config.toJson();
      expect(json['executablePath'], equals(r'C:\Tools\llama-server.exe'));
      expect(json['detectedVersion'], equals('b3450'));
      expect(json['validationStatus'], equals('valid'));

      final parsed = LlamaServerConfiguration.fromJson(json);
      expect(parsed.executablePath, equals(r'C:\Tools\llama-server.exe'));
      expect(
          parsed.validationStatus, equals(LlamaServerValidationStatus.valid));
      expect(parsed.detectedVersion, equals('b3450'));
    });

    test(
        'ModelRoleConfiguration gestisce ruoli actor ed evaluator indipendenti',
        () {
      final actorRef = ManagedModelReference(installationId: 'inst_actor');
      final evalRef =
          ExternalModelReference(absolutePath: r'C:\Models\eval.gguf');

      final roleConfig = ModelRoleConfiguration(
        actor: actorRef,
        evaluator: evalRef,
      );

      final json = roleConfig.toJson();
      final parsed = ModelRoleConfiguration.fromJson(json);

      expect(parsed.actor, equals(actorRef));
      expect(parsed.evaluator, equals(evalRef));
    });

    test('ExternalModelConsent attesta versione 1 e timestamp', () {
      final consent = ExternalModelConsent.now();
      expect(
          consent.consentVersion, equals(kCurrentExternalModelConsentVersion));
      expect(consent.isValidCurrent, isTrue);

      final json = consent.toJson();
      final parsed = ExternalModelConsent.fromJson(json);

      expect(parsed.consentVersion, equals(1));
      expect(parsed.isValidCurrent, isTrue);
    });

    test('PreflightDepth enum supporta quick, runtimeProbe e fullModelLoad',
        () {
      expect(PreflightDepth.values.length, equals(3));
      expect(PreflightDepth.values, contains(PreflightDepth.quick));
      expect(PreflightDepth.values, contains(PreflightDepth.runtimeProbe));
      expect(PreflightDepth.values, contains(PreflightDepth.fullModelLoad));
    });
  });
}
