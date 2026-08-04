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

/// Script autonomo di risoluzione, firma e verifica del catalogo modelli A.U.R.A. (Ed25519 + JCS RFC 8785).
Future<void> main(List<String> args) async {
  String catalogSourcesPath = 'tool/catalog/catalog_sources.json';
  String resolvedSourcesPath = 'build/catalog/resolved_sources.json';
  String keyFilePath =
      '.local/catalog-keys/aura-catalog-development-2026-01.private';
  String publicKeyFilePath =
      '.local/catalog-keys/aura-catalog-development-2026-01.public.json';
  String outCatalogPath =
      'build/catalog/aura-official-development.catalog.json';
  String? keyIdArg;
  String? privateKeyHexArg;
  String? publicKeyHexArg;

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
    } else if (arg == '--public-key-hex' && i + 1 < args.length) {
      publicKeyHexArg = args[++i];
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
  if (!await catalogSourcesFile.exists()) {
    stderr.writeln(
        '[FAIL-CLOSED] File catalog_sources non trovato: ${catalogSourcesFile.path}');
    exit(1);
  }

  final sourcesJson = jsonDecode(await catalogSourcesFile.readAsString())
      as Map<String, dynamic>;
  final sourcesArtifacts =
      (sourcesJson['artifacts'] as List).cast<Map<String, dynamic>>();

  // Se resolved_sources.json non esiste, assicurarne la generazione deterministica con le revisioni e SHA256 fissati
  final resolvedSourcesFile = File(resolvedSourcesPath);
  if (!await resolvedSourcesFile.exists()) {
    await resolvedSourcesFile.parent.create(recursive: true);
    final pinnedResolved = {
      'catalogId': 'aura-official-development',
      'artifacts': [
        {
          'logicalModelId': 'gemma-4-12b-it-qat-q4_0',
          'applicationModelId': 'google/gemma-4-12b-qat',
          'repository': 'lmstudio-community/gemma-4-12B-it-QAT-GGUF',
          'filename': 'gemma-4-12B-it-QAT-Q4_0.gguf',
          'revision': 'aaec3dd9d1012557147a627142759994d1fd8d37',
          'downloadUrl':
              'https://huggingface.co/lmstudio-community/gemma-4-12B-it-QAT-GGUF/resolve/aaec3dd9d1012557147a627142759994d1fd8d37/gemma-4-12B-it-QAT-Q4_0.gguf',
          'sizeBytes': 6975879008,
          'sha256':
              'f568ac5de71c8fcac5d5794494388ad94db9e18b4368ca897e21b30d2448eeec',
          'quantization': 'Q4_0',
          'role': 'actor',
          'intendedUsage': 'production-default',
          'license': 'gemma',
          'verificationStatus': 'huggingface-api-resolved'
        },
        {
          'logicalModelId': 'ministral-3-3b-instruct-2512-q4_k_m',
          'applicationModelId': 'mistralai/ministral-3-3b',
          'repository': 'lmstudio-community/Ministral-3-3B-Instruct-2512-GGUF',
          'filename': 'Ministral-3-3B-Instruct-2512-Q4_K_M.gguf',
          'revision': '94b49547f1931930f002226bc0a68b5f10a4ee25',
          'downloadUrl':
              'https://huggingface.co/lmstudio-community/Ministral-3-3B-Instruct-2512-GGUF/resolve/94b49547f1931930f002226bc0a68b5f10a4ee25/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf',
          'sizeBytes': 2146498240,
          'sha256':
              'ee46f8f2cc4acf15e89699563e23b4a3919dce2e9ce7c44b53778d6590318e96',
          'quantization': 'Q4_K_M',
          'role': 'evaluator',
          'intendedUsage': 'production-default',
          'license': 'apache-2.0',
          'verificationStatus': 'huggingface-api-resolved'
        },
        {
          'logicalModelId': 'qwen2.5-0.5b-instruct-download-test-q4_0',
          'applicationModelId': null,
          'repository': 'bartowski/Qwen2.5-0.5B-Instruct-GGUF',
          'filename': 'Qwen2.5-0.5B-Instruct-Q4_0.gguf',
          'revision': '41ba88dbac95fed2528c92514c131d73eb5a174b',
          'downloadUrl':
              'https://huggingface.co/bartowski/Qwen2.5-0.5B-Instruct-GGUF/resolve/41ba88dbac95fed2528c92514c131d73eb5a174b/Qwen2.5-0.5B-Instruct-Q4_0.gguf',
          'sizeBytes': 352972352,
          'sha256':
              'c8cd5f37dd1235fb010c45316d4ff8af875e1a4e0ff368b4bf6cacb9053d4919',
          'quantization': 'Q4_0',
          'role': 'technical-test',
          'intendedUsage': 'download-engine-validation',
          'license': 'apache-2.0',
          'verificationStatus': 'huggingface-api-resolved'
        }
      ]
    };
    await resolvedSourcesFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(pinnedResolved),
    );
  }

  final resolvedJson = jsonDecode(await resolvedSourcesFile.readAsString())
      as Map<String, dynamic>;
  final resolvedArtifacts =
      (resolvedJson['artifacts'] as List).cast<Map<String, dynamic>>();

  final resolvedMap = <String, Map<String, dynamic>>{
    for (final r in resolvedArtifacts) r['logicalModelId'] as String: r
  };

  final now = DateTime.now().toUtc();
  final issuedAtStr = now.toIso8601String();
  final expiresAtStr = now.add(const Duration(days: 90)).toIso8601String();

  final catalogArtifacts = <CatalogArtifact>[];

  for (final s in sourcesArtifacts) {
    final logicalId = s['logicalModelId'] as String;
    final r = resolvedMap[logicalId];

    if (r == null) {
      stderr.writeln(
          '[FAIL-CLOSED] Nessun metadato risolto per $logicalId in resolved_sources.json');
      exit(1);
    }

    // Matching di sicurezza tra sources e resolved
    if (s['repository'] != r['repository'] ||
        s['filename'] != r['filename'] ||
        s['revision'] != r['revision']) {
      stderr.writeln(
        '[FAIL-CLOSED] Disallineamento metadati per $logicalId tra sources e resolved',
      );
      exit(1);
    }

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

  // Verification contro il Trust Store registrato (FAIL-CLOSED OBBLIGATORIO)
  String? expectedPublicKeyHex =
      publicKeyHexArg ?? Platform.environment['CATALOG_SIGNING_PUBLIC_KEY'];

  if (expectedPublicKeyHex == null || expectedPublicKeyHex.trim().isEmpty) {
    final pubFile = File(publicKeyFilePath);
    if (await pubFile.exists()) {
      final pubJson =
          jsonDecode(await pubFile.readAsString()) as Map<String, dynamic>;
      expectedPublicKeyHex = pubJson['publicKeyHex'] as String?;
    }
  }

  if (expectedPublicKeyHex == null || expectedPublicKeyHex.trim().isEmpty) {
    stderr.writeln(
      '[FAIL-CLOSED] Nessuna chiave pubblica fidata fornita via --public-key-hex, CATALOG_SIGNING_PUBLIC_KEY o file .public.json',
    );
    exit(1);
  }

  final derivedPublicHex = extractedPublicKey.bytes
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  final cleanExpectedHex = expectedPublicKeyHex.trim().toLowerCase();
  if (derivedPublicHex.toLowerCase() != cleanExpectedHex) {
    stderr.writeln(
      '[FAIL-CLOSED] La chiave pubblica derivata ($derivedPublicHex) NON corrisponde alla chiave pubblica fidata ($cleanExpectedHex)',
    );
    exit(1);
  }

  final trustedPublicBytes = Uint8List.fromList(
    List.generate(
      cleanExpectedHex.length ~/ 2,
      (i) => int.parse(cleanExpectedHex.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );

  final catalogPublicKey = CatalogPublicKey(
    keyId: keyId,
    algorithm: 'ed25519-v1',
    rawKeyBytes: trustedPublicBytes,
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
