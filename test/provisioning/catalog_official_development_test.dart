import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura_core/aura_offline.dart';
import 'package:test/test.dart';

void main() {
  group('Official Development Catalog (Tranche 6.4c) Tests', () {
    late File catalogFile;
    late File publicKeyFile;
    late CatalogEnvelope envelope;
    late CatalogTrustStore trustStore;
    late Uint8List canonicalPayloadBytes;
    late Ed25519CatalogSignatureVerifier verifier;

    setUp(() async {
      catalogFile =
          File('build/catalog/aura-official-development.catalog.json');
      publicKeyFile = File(
          '.local/catalog-keys/aura-catalog-development-2026-01.public.json');

      expect(
        await catalogFile.exists(),
        isTrue,
        reason: 'Il file di catalogo generato deve esistere su disco.',
      );
      expect(
        await publicKeyFile.exists(),
        isTrue,
        reason: 'La chiave pubblica di sviluppo deve esistere su disco.',
      );

      final envelopeJson =
          jsonDecode(await catalogFile.readAsString()) as Map<String, dynamic>;
      envelope = CatalogEnvelope.fromJson(envelopeJson);

      final publicKeyJson = jsonDecode(await publicKeyFile.readAsString())
          as Map<String, dynamic>;
      final keyId = publicKeyJson['keyId'] as String;
      final algorithm = publicKeyJson['algorithm'] as String;
      final publicKeyHex = publicKeyJson['publicKeyHex'] as String;

      final publicBytes = Uint8List.fromList(
        List.generate(
          publicKeyHex.length ~/ 2,
          (i) => int.parse(publicKeyHex.substring(i * 2, i * 2 + 2), radix: 16),
        ),
      );

      final catalogPublicKey = CatalogPublicKey(
        keyId: keyId,
        algorithm: algorithm,
        rawKeyBytes: publicBytes,
      );

      trustStore = InMemoryCatalogTrustStore.fromKeys([catalogPublicKey]);
      canonicalPayloadBytes = Rfc8785JcsCanonicalizer.canonicalizeBytes(
        envelope.signedPayload.toJson(),
      );
      verifier = Ed25519CatalogSignatureVerifier();
    });

    test('Contains exactly the three required official development artifacts',
        () {
      final manifest = envelope.signedPayload.manifest;
      expect(manifest.catalogId, equals('aura-official-development'));
      expect(envelope.signedPayload.catalogRevision, equals(1));
      expect(manifest.artifacts.length, equals(3));

      final logicalIds = manifest.artifacts.map((a) => a.artifactId).toList();
      expect(
        logicalIds,
        containsAll([
          'gemma-4-12b-it-qat-q4_0',
          'ministral-3-3b-instruct-2512-q4_k_m',
          'qwen2.5-0.5b-instruct-download-test-q4_0',
        ]),
      );
    });

    test(
        'All artifacts have pinned full 40-character SHA commits and no main branch URLs',
        () {
      final manifest = envelope.signedPayload.manifest;
      final shaRegex = RegExp(r'^[0-9a-f]{40}$', caseSensitive: false);

      for (final artifact in manifest.artifacts) {
        final revision = artifact.metadata['revision'] as String?;
        expect(revision, isNotNull);
        expect(
          shaRegex.hasMatch(revision!),
          isTrue,
          reason:
              'La revisione dell\'artifact ${artifact.artifactId} deve essere un commit SHA completo a 40 caratteri.',
        );

        expect(
          artifact.downloadUri,
          isNotNull,
        );
        expect(
          artifact.downloadUri,
          isNot(contains('/resolve/main/')),
          reason: 'Nessun URL deve contenere il branch mobile main.',
        );
      }
    });

    test('Actor, Evaluator, and Technical Test roles and metadata invariants',
        () {
      final manifest = envelope.signedPayload.manifest;

      final actor = manifest.artifacts
          .firstWhere((a) => a.artifactId == 'gemma-4-12b-it-qat-q4_0');
      expect(actor.metadata['role'], equals('actor'));
      expect(actor.metadata['defaultActor'], isTrue);
      expect(actor.metadata['defaultEvaluator'], isFalse);
      expect(actor.metadata['selectable'], isTrue);

      final evaluator = manifest.artifacts.firstWhere(
          (a) => a.artifactId == 'ministral-3-3b-instruct-2512-q4_k_m');
      expect(evaluator.metadata['role'], equals('evaluator'));
      expect(evaluator.metadata['defaultEvaluator'], isTrue);
      expect(evaluator.metadata['defaultActor'], isFalse);
      expect(evaluator.metadata['selectable'], isTrue);

      final techTest = manifest.artifacts.firstWhere(
          (a) => a.artifactId == 'qwen2.5-0.5b-instruct-download-test-q4_0');
      expect(techTest.metadata['role'], equals('technical-test'));
      expect(techTest.metadata['selectable'], isFalse);
      expect(techTest.metadata['defaultActor'], isFalse);
      expect(techTest.metadata['defaultEvaluator'], isFalse);
    });

    test('Cryptographic Ed25519 signature is valid', () async {
      final result = await verifier.verify(
        envelope: envelope,
        canonicalSignedPayload: canonicalPayloadBytes,
        trustStore: trustStore,
      );

      expect(result.isValid, isTrue);
      expect(
        result.status,
        equals(CatalogSignatureVerificationStatus.valid),
      );
    });

    test('Tampered signature is rejected by signature verifier', () async {
      final tamperedSignature =
          base64.encode(Uint8List(64)); // 64 zero bytes signature
      final tamperedEnvelope = CatalogEnvelope(
        signedPayload: envelope.signedPayload,
        signature: tamperedSignature,
      );

      final result = await verifier.verify(
        envelope: tamperedEnvelope,
        canonicalSignedPayload: canonicalPayloadBytes,
        trustStore: trustStore,
      );

      expect(result.isValid, isFalse);
      expect(
        result.status,
        equals(CatalogSignatureVerificationStatus.failed),
      );
    });

    test('Runtime pipeline factory accepts and validates the candidate',
        () async {
      final factory = const DefaultValidatedCatalogCandidateFactory();
      final result = await factory.createCandidate(
        envelope: envelope,
        source: CatalogSource.remoteSigned,
        trustStore: trustStore,
        compatibilityEvaluator: const DefaultCatalogCompatibilityEvaluator(),
        validationService: const CatalogValidationService(),
        signatureVerifier: verifier,
        nowUtc: DateTime.now().toUtc(),
        applicationVersion: '1.0.0',
      );

      expect(result.isSuccess, isTrue);
      final candidate = result.candidate!;
      expect(
        candidate.trustLevel,
        equals(CatalogTrustLevel.signatureVerified),
      );
      expect(
        candidate.envelope.signedPayload.catalogId,
        equals('aura-official-development'),
      );
    });
  });
}
