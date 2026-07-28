import 'package:aura_core/aura_offline.dart';
import '../provisioning_test_helpers.dart';
import 'package:test/test.dart';

void main() {
  late MemoryProvisioningFileSystem fileSystem;
  late ProvisioningLock lock;
  late JsonModelConfigurationRepository repo;
  const storePath = r'C:\Users\Test\AppData\Local\AURA\store';

  setUp(() {
    fileSystem = MemoryProvisioningFileSystem();
    lock = InMemoryProvisioningLock();
    repo = JsonModelConfigurationRepository(
      storeDirectoryPath: storePath,
      fileSystem: fileSystem,
      lock: lock,
    );
  });

  group('Tranche 6.4f.1 — JsonModelConfigurationRepository Tests', () {
    test('readRecord restituisce record vuoto se il file non esiste', () async {
      final record = await repo.readRecord();
      expect(record.schemaVersion, equals(1));
      expect(record.runtime, isNull);
      expect(record.models.actor, isNull);
      expect(record.models.evaluator, isNull);
      expect(record.externalModelConsent, isNull);
    });

    test(
        'replaceRecord e updateRecord salvano e leggono la configurazione atomica',
        () async {
      final runtimeConfig = LlamaServerConfiguration(
        executablePath: r'C:\Tools\llama-server.exe',
        detectedVersion: 'b3400',
        validationStatus: LlamaServerValidationStatus.valid,
      );

      final modelConfig = ModelRoleConfiguration(
        actor: ManagedModelReference(installationId: 'inst_actor'),
        evaluator: ExternalModelReference(absolutePath: r'C:\Gguf\eval.gguf'),
      );

      final consent = ExternalModelConsent.now();

      final record = ModelConfigurationRecord(
        schemaVersion: 1,
        runtime: runtimeConfig,
        models: modelConfig,
        externalModelConsent: consent,
      );

      await repo.replaceRecord(record);

      final read = await repo.readRecord();
      expect(read.schemaVersion, equals(1));
      expect(read.runtime, equals(runtimeConfig));
      expect(read.models.actor,
          equals(ManagedModelReference(installationId: 'inst_actor')));
      expect(read.models.evaluator,
          equals(ExternalModelReference(absolutePath: r'C:\Gguf\eval.gguf')));
      expect(read.externalModelConsent, equals(consent));
    });

    test('readRecord esegue il fallback al file .bak se il primario è corrotto',
        () async {
      final validRecord = ModelConfigurationRecord(
        schemaVersion: 1,
        runtime: const LlamaServerConfiguration(
          executablePath: r'C:\Tools\llama-server.exe',
          validationStatus: LlamaServerValidationStatus.valid,
        ),
        models: ModelRoleConfiguration(
          actor: ManagedModelReference(installationId: 'inst_actor_valid'),
        ),
      );

      // Prima scrittura per creare il file primario
      await repo.replaceRecord(validRecord);
      // Seconda scrittura per generare la copia di backup .bak
      await repo.replaceRecord(validRecord);

      final primaryFile = '$storePath\\model_configuration.json';
      final backupFile = '$storePath\\model_configuration.json.bak';

      expect(await fileSystem.fileExists(primaryFile), isTrue);
      expect(await fileSystem.fileExists(backupFile), isTrue);

      // Corrompiamo il file primario
      await fileSystem.writeStringRecoverably(primaryFile, '{ INVALID JSON }');

      final recovered = await repo.readRecord();
      expect(recovered.models.actor,
          equals(ManagedModelReference(installationId: 'inst_actor_valid')));
    });
  });
}
