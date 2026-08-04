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

/// Script di verifica della firma e dell'integrita dell'envelope di catalogo A.U.R.A.
///
/// Uso:
///   dart run tool/catalog/verify_catalog.dart [opzioni]
///
/// Opzioni:
///   --catalog <path>          Path al file catalog/model-manifest.json da verificare
///   --public-key-hex <hex>     Stringa esadecimale della chiave pubblica fidata
///   --key-id <string>         ID della chiave fidata (es. aura-catalog-development-2026-01)
///   --public-key-file <path>   Path al file JSON contenente keyId e publicKeyHex
Future<void> main(List<String> args) async {
  String? catalogPathArg;
  String? publicKeyHexArg;
  String? keyIdArg;
  String? publicKeyFilePathArg;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--catalog' && i + 1 < args.length) {
      catalogPathArg = args[++i];
    } else if (arg == '--public-key-hex' && i + 1 < args.length) {
      publicKeyHexArg = args[++i];
    } else if (arg == '--key-id' && i + 1 < args.length) {
      keyIdArg = args[++i];
    } else if (arg == '--public-key-file' && i + 1 < args.length) {
      publicKeyFilePathArg = args[++i];
    }
  }

  // Risoluzione dinamica del path del catalogo
  String catalogPath;
  if (catalogPathArg != null) {
    catalogPath = catalogPathArg;
  } else if (await File('release/model-manifest.json').exists()) {
    catalogPath = 'release/model-manifest.json';
  } else if (await File('build/release-staging/model-manifest.json').exists()) {
    catalogPath = 'build/release-staging/model-manifest.json';
  } else {
    catalogPath = 'build/catalog/aura-official-development.catalog.json';
  }

  final catalogFile = File(catalogPath);
  if (!await catalogFile.exists()) {
    stderr.writeln(
        '[FAIL-CLOSED] Errore: Catalogo non trovato: ${catalogFile.path}');
    exit(1);
  }

  // Risoluzione della chiave pubblica fidata (FAIL-CLOSED)
  String? keyId = keyIdArg ?? Platform.environment['CATALOG_SIGNING_KEY_ID'];
  String? publicKeyHex =
      publicKeyHexArg ?? Platform.environment['CATALOG_SIGNING_PUBLIC_KEY'];

  if (publicKeyHex == null ||
      publicKeyHex.trim().isEmpty ||
      keyId == null ||
      keyId.trim().isEmpty) {
    final pubKeyFilePath = publicKeyFilePathArg ??
        '.local/catalog-keys/aura-catalog-development-2026-01.public.json';
    final pubKeyFile = File(pubKeyFilePath);
    if (await pubKeyFile.exists()) {
      final pubJson =
          jsonDecode(await pubKeyFile.readAsString()) as Map<String, dynamic>;
      keyId ??= pubJson['keyId'] as String?;
      publicKeyHex ??= pubJson['publicKeyHex'] as String?;
    }
  }

  if (keyId == null ||
      keyId.trim().isEmpty ||
      publicKeyHex == null ||
      publicKeyHex.trim().isEmpty) {
    stderr.writeln(
      '[FAIL-CLOSED] Nessuna chiave pubblica fidata fornita via --public-key-hex, CATALOG_SIGNING_PUBLIC_KEY o file .public.json',
    );
    exit(1);
  }

  stdout
      .writeln('--- Verifica Runtime del Catalogo Firmato ($catalogPath) ---');

  final envelopeJson =
      jsonDecode(await catalogFile.readAsString()) as Map<String, dynamic>;
  final envelope = CatalogEnvelope.fromJson(envelopeJson);

  final cleanHex = publicKeyHex.trim();
  final publicBytes = Uint8List.fromList(
    List.generate(
      cleanHex.length ~/ 2,
      (i) => int.parse(cleanHex.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );

  final catalogPublicKey = CatalogPublicKey(
    keyId: keyId,
    algorithm: 'ed25519-v1',
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
      '[FAIL-CLOSED] Firma non valida! Motivo: ${verificationResult.failureReason}',
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
        '[FAIL-CLOSED] Creazione candidato fallita: ${candidateResult.errorMessage}');
    exit(1);
  }

  final candidate = candidateResult.candidate!;
  final manifest = candidate.envelope.signedPayload.manifest;
  stdout.writeln('   - Catalog ID: ${manifest.catalogId}');
  stdout.writeln(
      '   - Revision: ${candidate.envelope.signedPayload.catalogRevision}');
  stdout
      .writeln('   - Key ID fidata: ${candidate.envelope.signedPayload.keyId}');
  stdout.writeln('   - Numero Artifact: ${manifest.artifacts.length}');
  stdout.writeln('   - Validazione Trust Level: ${candidate.trustLevel}');

  stdout.writeln('\n--- Elenco Artifact Validati ---');
  for (final artifact in manifest.artifacts) {
    stdout.writeln(' * Artifact ID: ${artifact.artifactId}');
    stdout.writeln('   Display Name: ${artifact.displayName}');
    stdout.writeln('   Type: ${artifact.artifactType}');
    stdout.writeln('   Size: ${artifact.sizeBytes} bytes');
    stdout.writeln('   SHA-256: ${artifact.sha256}');
    stdout.writeln('   URI: ${artifact.downloadUri}');
    stdout.writeln('');
  }

  stdout.writeln('✅ VERIFICA RUNTIME COMPLETATA CON SUCCESSO!');
}
