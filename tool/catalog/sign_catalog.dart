import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura_core/src/provisioning/crypto/catalog_public_key.dart';
import 'package:aura_core/src/provisioning/crypto/catalog_signature_verifier.dart';
import 'package:aura_core/src/provisioning/crypto/catalog_trust_store.dart';
import 'package:aura_core/src/provisioning/crypto/rfc8785_jcs_canonicalizer.dart';
import 'package:aura_core/src/provisioning/domain/catalog_acquisition_models.dart';
import 'package:aura_core/src/provisioning/domain/catalog_manifest.dart';
import 'package:cryptography/cryptography.dart' as crypto;

/// Script di firma dei cataloghi ufficiali A.U.R.A. con Ed25519 + JCS (RFC 8785).
///
/// Uso:
///   dart run tool/catalog/sign_catalog.dart [opzioni]
///
/// Opzioni:
///   --catalog-sources <path>   (default: tool/catalog/catalog_sources.json)
///   --resolved-sources <path>  (default: build/catalog/resolved_sources.json)
///   --key-file <path>          (default: .local/catalog-keys/aura-catalog-development-2026-01.private)
///   --out-catalog <path>       (default: build/catalog/aura-official-development.catalog.json)
///   --key-id <string>          (default: da env CATALOG_SIGNING_KEY_ID o aura-catalog-development-2026-01)
///   --private-key-hex <string> (default: da env CATALOG_SIGNING_PRIVATE_KEY o da --key-file)
Future<void> main(List<String> args) async {
  String catalogSourcesPath = 'tool/catalog/catalog_sources.json';
  String resolvedSourcesPath = 'build/catalog/resolved_sources.json';
  String keyFilePath =
      '.local/catalog-keys/aura-catalog-development-2026-01.private';
  String outCatalogPath =
      'build/catalog/aura-official-development.catalog.json';
  String? keyIdArg;
  String? privateKeyHexArg;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--catalog-sources' && i + 1 < args.length) {
      catalogSourcesPath = args[++i];
    } else if (arg == '--resolved-sources' && i + 1 < args.length) {
      resolvedSourcesPath = args[++i];
    } else if (arg == '--key-file' && i + 1 < args.length) {
      keyFilePath = args[++i];
    } else if (arg == '--out-catalog' && i + 1 < args.length) {
      outCatalogPath = args[++i];
    } else if (arg == '--key-id' && i + 1 < args.length) {
      keyIdArg = args[++i];
    } else if (arg == '--private-key-hex' && i + 1 < args.length) {
      privateKeyHexArg = args[++i];
    }
  }

  final keyId = keyIdArg ??
      Platform.environment['CATALOG_SIGNING_KEY_ID'] ??
      'aura-catalog-development-2026-01';

  String? privateKeyHex =
      privateKeyHexArg ?? Platform.environment['CATALOG_SIGNING_PRIVATE_KEY'];

  if (privateKeyHex == null || privateKeyHex.trim().isEmpty) {
    final keyFile = File(keyFilePath);
    if (await keyFile.exists()) {
      privateKeyHex = (await keyFile.readAsString()).trim();
    } else {
      stderr.writeln(
        '[FAIL-CLOSED] Nessuna chiave privata trovata in CATALOG_SIGNING_PRIVATE_KEY o ${keyFile.path}',
      );
      exit(1);
    }
  }

  final catalogSourcesFile = File(catalogSourcesPath);
  final resolvedSourcesFile = File(resolvedSourcesPath);

  if (!await catalogSourcesFile.exists()) {
    stderr.writeln(
        '[FAIL-CLOSED] File catalog_sources non trovato: ${catalogSourcesFile.path}');
    exit(1);
  }

  if (!await resolvedSourcesFile.exists()) {
    stderr.writeln(
        '[FAIL-CLOSED] File resolved_sources non trovato: ${resolvedSourcesFile.path}');
    exit(1);
  }

  final sourcesJson = jsonDecode(await catalogSourcesFile.readAsString())
      as Map<String, dynamic>;
  final resolvedJson = jsonDecode(await resolvedSourcesFile.readAsString())
      as Map<String, dynamic>;

  final sourcesArtifacts =
      (sourcesJson['artifacts'] as List).cast<Map<String, dynamic>>();
  final resolvedArtifacts =
      (resolvedJson['artifacts'] as List).cast<Map<String, dynamic>>();

  if (sourcesArtifacts.length != resolvedArtifacts.length) {
    stderr.writeln(
      '[FAIL-CLOSED] Disallineamento tra catalog_sources (${sourcesArtifacts.length}) e resolved_sources (${resolvedArtifacts.length}).',
    );
    exit(1);
  }

  final now = DateTime.now().toUtc();
  final issuedAtStr = now.toIso8601String();
  final expiresAtStr = now.add(const Duration(days: 90)).toIso8601String();

  final catalogArtifacts = <CatalogArtifact>[];

  for (var i = 0; i < sourcesArtifacts.length; i++) {
    final s = sourcesArtifacts[i];
    final r = resolvedArtifacts[i];

    final logicalId = s['logicalModelId'] as String;
    final repo = s['repository'] as String;
    final filename = s['filename'] as String;
    final revision = r['revision'] as String;

    if (revision.trim().isEmpty || revision.toLowerCase() == 'main') {
      stderr.writeln(
          '[FAIL-CLOSED] Revisione non valida o mobile per $logicalId: $revision');
      exit(1);
    }

    final role = s['role'] as String;
    final intendedUsage = s['intendedUsage'] as String;
    final quantization = s['quantization'] as String;
    final appModelId = s['applicationModelId'] as String?;
    final downloadUrl = r['downloadUrl'] as String;
    final sizeBytes = r['sizeBytes'] as int;
    final sha256 = r['sha256'] as String;
    final license = r['license'] as String? ?? 'unknown';
    final verificationStatus =
        r['verificationStatus'] as String? ?? 'huggingface-api-resolved';

    final isActor = role == 'actor';
    final isEvaluator = role == 'evaluator';
    final isTechTest = role == 'technical-test';

    final displayName = isActor
        ? 'Gemma 4 12B IT QAT (Q4_0)'
        : isEvaluator
            ? 'Ministral 3B Instruct 2512 (Q4_K_M)'
            : 'Qwen 2.5 0.5B Instruct Download Test (Q4_0)';

    final version = isActor
        ? '4.0.0'
        : isEvaluator
            ? '3.0.0'
            : '2.5.0';

    final buildId = isActor
        ? 'qat-q4_0-v1'
        : isEvaluator
            ? 'q4_k_m-v1'
            : 'q4_0-test-v1';

    final capabilities = isActor
        ? const ['generate_character_response', 'instruction_following']
        : isEvaluator
            ? const [
                'score_user_input',
                'produce_json_delta',
                'detect_injection_attempt'
              ]
            : const ['technical_download_test'];

    final catalogArtifact = CatalogArtifact(
      artifactId: logicalId,
      artifactType: CatalogArtifactType.model,
      displayName: displayName,
      version: version,
      buildId: buildId,
      platform: 'all',
      architecture: 'gguf',
      fileName: filename,
      sourceKind: CatalogArtifactSourceKind.remoteHttps,
      downloadUri: downloadUrl,
      sizeBytes: sizeBytes,
      sha256: sha256,
      license: license,
      quantization: quantization,
      capabilities: capabilities,
      deprecated: false,
      releaseChannel: 'stable',
      metadata: {
        'role': role,
        'intendedUsage': intendedUsage,
        'selectable': !isTechTest,
        'defaultActor': isActor,
        'defaultEvaluator': isEvaluator,
        if (appModelId != null) 'applicationModelId': appModelId,
        'repository': repo,
        'revision': revision,
        'verificationStatus': verificationStatus,
      },
    );

    catalogArtifacts.add(catalogArtifact);
  }

  final manifest = CatalogManifest(
    schemaVersion: '1.0',
    catalogId: 'aura-official-development',
    generatedAt: issuedAtStr,
    artifacts: catalogArtifacts,
  );

  final signedPayload = CatalogSignedPayload(
    schemaVersion: '1.0',
    signatureAlgorithm: 'ed25519-v1',
    keyId: keyId,
    catalogId: 'aura-official-development',
    catalogVersion: '1.0.0',
    catalogRevision: 1,
    issuedAt: issuedAtStr,
    expiresAt: expiresAtStr,
    manifest: manifest,
  );

  final canonicalBytes =
      Rfc8785JcsCanonicalizer.canonicalizeBytes(signedPayload.toJson());

  final privateKeyClean = privateKeyHex.trim();
  final privateKeyBytes = Uint8List.fromList(
    List.generate(
      privateKeyClean.length ~/ 2,
      (i) => int.parse(privateKeyClean.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );

  final ed25519 = crypto.Ed25519();
  final keyPair = await ed25519.newKeyPairFromSeed(privateKeyBytes);
  final extractedPublicKey = await keyPair.extractPublicKey();
  final signature = await ed25519.sign(canonicalBytes, keyPair: keyPair);
  final signatureBase64 = base64.encode(signature.bytes);

  final envelope = CatalogEnvelope(
    signedPayload: signedPayload,
    signature: signatureBase64,
  );

  // Verification self-check
  final catalogPublicKey = CatalogPublicKey(
    keyId: keyId,
    algorithm: 'ed25519-v1',
    rawKeyBytes: Uint8List.fromList(extractedPublicKey.bytes),
  );

  final trustStore = InMemoryCatalogTrustStore.fromKeys([catalogPublicKey]);
  final verifier = Ed25519CatalogSignatureVerifier();

  final checkResult = await verifier.verify(
    envelope: envelope,
    canonicalSignedPayload: canonicalBytes,
    trustStore: trustStore,
  );

  if (!checkResult.isValid) {
    stderr.writeln(
      '[FAIL-CLOSED] Auto-verifica della firma del catalogo fallita: ${checkResult.failureReason}',
    );
    exit(1);
  }

  final outFile = File(outCatalogPath);
  await outFile.parent.create(recursive: true);
  await outFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(envelope.toJson()),
  );

  stdout.writeln(
    '✅ Catalogo firmato e verificato con successo: ${outFile.path} (KeyId: $keyId)',
  );
}
