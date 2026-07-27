import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura_core/src/provisioning/crypto/catalog_public_key.dart';
import 'package:aura_core/src/provisioning/crypto/catalog_signature_verifier.dart';
import 'package:aura_core/src/provisioning/crypto/catalog_trust_store.dart';
import 'package:aura_core/src/provisioning/crypto/rfc8785_jcs_canonicalizer.dart';
import 'package:aura_core/src/provisioning/domain/catalog_acquisition_models.dart';
import 'package:aura_core/src/provisioning/domain/catalog_compatibility_evaluator.dart';
import 'package:aura_core/src/provisioning/domain/validated_catalog_candidate_factory.dart';
import 'package:aura_core/src/provisioning/validation/catalog_validation_service.dart';

Future<void> main(List<String> args) async {
  final catalogFile =
      File('build/catalog/aura-official-development.catalog.json');
  final publicKeyFile =
      File('.local/catalog-keys/aura-catalog-development-2026-01.public.json');

  if (!await catalogFile.exists()) {
    stderr.writeln('Errore: Catalogo non trovato: ${catalogFile.path}');
    exit(1);
  }
  if (!await publicKeyFile.exists()) {
    stderr.writeln(
      'Errore: Chiave pubblica non trovata: ${publicKeyFile.path}',
    );
    exit(1);
  }

  stdout.writeln('--- Verifica Runtime del Catalogo Firmato ---');

  final envelopeJson =
      jsonDecode(await catalogFile.readAsString()) as Map<String, dynamic>;
  final envelope = CatalogEnvelope.fromJson(envelopeJson);

  final publicKeyJson =
      jsonDecode(await publicKeyFile.readAsString()) as Map<String, dynamic>;
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

  final trustStore = InMemoryCatalogTrustStore.fromKeys([catalogPublicKey]);

  final canonicalPayloadBytes = Rfc8785JcsCanonicalizer.canonicalizeBytes(
    envelope.signedPayload.toJson(),
  );

  final verifier = Ed25519CatalogSignatureVerifier();
  final verificationResult = await verifier.verify(
    envelope: envelope,
    canonicalSignedPayload: canonicalPayloadBytes,
    trustStore: trustStore,
  );

  stdout.writeln('1. Risultato Verifica Firma: ${verificationResult.status}');
  if (!verificationResult.isValid) {
    stderr.writeln(
      'Firma non valida! Motivo: ${verificationResult.failureReason}',
    );
    exit(1);
  }

  final factory = const DefaultValidatedCatalogCandidateFactory();
  final candidateResult = await factory.createCandidate(
    envelope: envelope,
    source: CatalogSource.remoteSigned,
    trustStore: trustStore,
    compatibilityEvaluator: const DefaultCatalogCompatibilityEvaluator(),
    validationService: const CatalogValidationService(),
    signatureVerifier: verifier,
    nowUtc: DateTime.now().toUtc(),
    applicationVersion: '1.0.0',
  );

  stdout.writeln('2. Risultato Candidato Catalogo:');
  if (!candidateResult.isSuccess) {
    stderr.writeln(
        'Creazione candidato fallita: ${candidateResult.errorMessage}');
    exit(1);
  }
  final candidate = candidateResult.candidate!;
  final manifest = candidate.envelope.signedPayload.manifest;
  stdout.writeln('   - Catalog ID: ${manifest.catalogId}');
  stdout.writeln(
      '   - Revision: ${candidate.envelope.signedPayload.catalogRevision}');
  stdout.writeln(
    '   - Numero Artifact: ${manifest.artifacts.length}',
  );
  stdout.writeln('   - Validazione Trust Level: ${candidate.trustLevel}');

  stdout.writeln('\n--- Elenco Artifact Validati ---');
  for (final artifact in manifest.artifacts) {
    stdout.writeln(' * Artifact ID: ${artifact.artifactId}');
    stdout.writeln('   Display Name: ${artifact.displayName}');
    stdout.writeln('   Type: ${artifact.artifactType}');
    stdout.writeln('   Size: ${artifact.sizeBytes} bytes');
    stdout.writeln('   SHA-256: ${artifact.sha256}');
    stdout.writeln('   URI: ${artifact.downloadUri}');
    stdout.writeln('   Metadata: ${artifact.metadata}');
    stdout.writeln('');
  }

  stdout.writeln('VERIFICA RUNTIME COMPLETATA CON SUCCESSO!');
}
