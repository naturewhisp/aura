import 'dart:convert';
import 'dart:typed_data';
import 'package:aura_core/aura_offline.dart';
import 'package:cryptography/cryptography.dart' as crypto;
import 'package:test/test.dart';

void main() {
  group('DefaultValidatedCatalogCandidateFactory Tests (Finding 4)', () {
    late DefaultValidatedCatalogCandidateFactory factory;
    late CatalogValidationService validationService;
    late DefaultCatalogCompatibilityEvaluator compatibilityEvaluator;
    late crypto.SimpleKeyPair keyPair;
    late Uint8List publicKeyBytes;
    late CatalogTrustStore trustStore;
    late CatalogSignatureVerifier signatureVerifier;
    late DateTime nowUtc;

    setUp(() async {
      factory = const DefaultValidatedCatalogCandidateFactory();
      validationService = const CatalogValidationService();
      compatibilityEvaluator = const DefaultCatalogCompatibilityEvaluator();

      final algorithm = crypto.Ed25519();
      keyPair = await algorithm.newKeyPair();
      final simplePubKey = await keyPair.extractPublicKey();
      publicKeyBytes = Uint8List.fromList(simplePubKey.bytes);

      final catalogPublicKey = CatalogPublicKey(
        keyId: 'aura-release-key-2026-01',
        algorithm: 'ed25519-v1',
        rawKeyBytes: publicKeyBytes,
      );
      trustStore = InMemoryCatalogTrustStore.fromKeys([catalogPublicKey]);
      signatureVerifier = Ed25519CatalogSignatureVerifier();

      nowUtc = DateTime.parse('2026-07-22T21:30:00Z').toUtc();
    });

    test(
        'Creates ValidatedCatalogCandidate when semantic validation and signature verification succeed',
        () async {
      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'aura-official-catalog',
        generatedAt: '2026-07-22T20:00:00Z',
        artifacts: [
          CatalogArtifact(
            artifactId: 'gemma-4-12b-it-qat-q4-0',
            artifactType: CatalogArtifactType.model,
            displayName: 'Gemma Model',
            version: '1.0.0',
            buildId: 'b1',
            platform: 'windows',
            architecture: 'x64',
            fileName: 'gemma.gguf',
            sourceKind: CatalogArtifactSourceKind.remoteHttps,
            sizeBytes: 1024,
            sha256: 'a' * 64,
            compression: CatalogCompressionFormat.none,
            license: 'MIT',
            releaseChannel: 'stable',
            metadata: {
              'repositoryRevision': '72ca550021d6aceda98eb999f35b3407bce75383',
            },
          ),
        ],
      );

      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 42,
        issuedAt: '2026-07-22T20:00:00Z',
        expiresAt: '2026-08-22T20:00:00Z',
        manifest: manifest,
      );

      final canonicalBytes =
          Rfc8785JcsCanonicalizer.canonicalizeBytes(payload.toJson());
      final algorithm = crypto.Ed25519();
      final sigObj = await algorithm.sign(canonicalBytes, keyPair: keyPair);

      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(sigObj.bytes),
      );

      final result = await factory.createCandidate(
        envelope: envelope,
        source: CatalogSource.remoteSigned,
        trustStore: trustStore,
        compatibilityEvaluator: compatibilityEvaluator,
        validationService: validationService,
        signatureVerifier: signatureVerifier,
        nowUtc: nowUtc,
        applicationVersion: '1.0.0',
      );

      expect(result.isSuccess, isTrue);
      expect(result.candidate, isNotNull);
      expect(result.candidate!.trustLevel,
          equals(CatalogTrustLevel.signatureVerified));
      expect(result.candidate!.canonicalPayloadDigest, isNotEmpty);
    });

    test('Fails to create candidate when signature verification fails',
        () async {
      final manifest = CatalogManifest(
        schemaVersion: '1.0',
        catalogId: 'aura-official-catalog',
        generatedAt: '2026-07-22T20:00:00Z',
        artifacts: [
          CatalogArtifact(
            artifactId: 'gemma-4-12b-it-qat-q4-0',
            artifactType: CatalogArtifactType.model,
            displayName: 'Gemma Model',
            version: '1.0.0',
            buildId: 'b1',
            platform: 'windows',
            architecture: 'x64',
            fileName: 'gemma.gguf',
            sourceKind: CatalogArtifactSourceKind.remoteHttps,
            sizeBytes: 1024,
            sha256: 'a' * 64,
            compression: CatalogCompressionFormat.none,
            license: 'MIT',
            releaseChannel: 'stable',
            metadata: {
              'repositoryRevision': '72ca550021d6aceda98eb999f35b3407bce75383',
            },
          ),
        ],
      );

      final payload = CatalogSignedPayload(
        schemaVersion: '1.0',
        signatureAlgorithm: 'ed25519-v1',
        keyId: 'aura-release-key-2026-01',
        catalogId: 'aura-official-catalog',
        catalogVersion: '1.0.0',
        catalogRevision: 42,
        issuedAt: '2026-07-22T20:00:00Z',
        expiresAt: '2026-08-22T20:00:00Z',
        manifest: manifest,
      );

      // Firma fittizia non valida
      final envelope = CatalogEnvelope(
        signedPayload: payload,
        signature: base64.encode(Uint8List(64)),
      );

      final result = await factory.createCandidate(
        envelope: envelope,
        source: CatalogSource.remoteSigned,
        trustStore: trustStore,
        compatibilityEvaluator: compatibilityEvaluator,
        validationService: validationService,
        signatureVerifier: signatureVerifier,
        nowUtc: nowUtc,
        applicationVersion: '1.0.0',
      );

      expect(result.isSuccess, isFalse);
      expect(result.failureReason,
          equals(CatalogAcquisitionFailureReason.signatureVerificationFailed));
    });
  });
}
