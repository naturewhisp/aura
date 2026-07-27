import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:aura_core/src/provisioning/crypto/rfc8785_jcs_canonicalizer.dart';
import 'package:aura_core/src/provisioning/domain/catalog_acquisition_models.dart';
import 'package:aura_core/src/provisioning/domain/catalog_manifest.dart';
import 'package:cryptography/cryptography.dart' as crypto;

Future<void> main(List<String> args) async {
  final catalogSourcesFile = File('tool/catalog/catalog_sources.json');
  final resolvedSourcesFile = File('build/catalog/resolved_sources.json');
  final keyFile =
      File('.local/catalog-keys/aura-catalog-development-2026-01.private');
  final outputCatalogFile =
      File('build/catalog/aura-official-development.catalog.json');
  final reportJsonFile =
      File('build/catalog/aura-official-development.catalog.report.json');
  final reportMdFile =
      File('build/catalog/aura-official-development.catalog.report.md');

  if (!await catalogSourcesFile.exists()) {
    stderr.writeln('Errore: ${catalogSourcesFile.path} non trovato.');
    exit(1);
  }
  if (!await resolvedSourcesFile.exists()) {
    stderr.writeln(
      'Errore: ${resolvedSourcesFile.path} non trovato. Esegui prima resolve_huggingface_metadata.py.',
    );
    exit(1);
  }
  if (!await keyFile.exists()) {
    stderr.writeln(
      'Errore: Chiave privata ${keyFile.path} non trovata. Esegui prima keygen_development.dart.',
    );
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
      'Errore: Disallineamento tra catalog_sources (${sourcesArtifacts.length}) e resolved_sources (${resolvedArtifacts.length}).',
    );
    exit(1);
  }

  final now = DateTime.now().toUtc();
  final issuedAtStr = now.toIso8601String();
  final expiresAtStr = now.add(const Duration(days: 90)).toIso8601String();

  final catalogArtifacts = <CatalogArtifact>[];
  final reportArtifactsList = <Map<String, dynamic>>[];

  for (var i = 0; i < sourcesArtifacts.length; i++) {
    final s = sourcesArtifacts[i];
    final r = resolvedArtifacts[i];

    final logicalId = s['logicalModelId'] as String;
    final repo = s['repository'] as String;
    final filename = s['filename'] as String;
    final revision = r['revision'] as String;

    if (revision.trim().isEmpty || revision.toLowerCase() == 'main') {
      stderr.writeln(
          'Errore: Revisione non valida o mobile per $logicalId: $revision');
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

    reportArtifactsList.add({
      'logicalModelId': logicalId,
      'role': role,
      'repository': repo,
      'revision': revision,
      'filename': filename,
      'downloadUrl': downloadUrl,
      'sizeBytes': sizeBytes,
      'sha256': sha256,
      'quantization': quantization,
      'license': license,
      'acquiredAt': issuedAtStr,
      'verificationStatus': verificationStatus,
    });
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
    keyId: 'aura-catalog-development-2026-01',
    catalogId: 'aura-official-development',
    catalogVersion: '1.0.0',
    catalogRevision: 1,
    issuedAt: issuedAtStr,
    expiresAt: expiresAtStr,
    manifest: manifest,
  );

  final canonicalBytes =
      Rfc8785JcsCanonicalizer.canonicalizeBytes(signedPayload.toJson());

  final privateKeyHex = (await keyFile.readAsString()).trim();
  final privateKeyBytes = Uint8List.fromList(
    List.generate(
      privateKeyHex.length ~/ 2,
      (i) => int.parse(privateKeyHex.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );

  final ed25519 = crypto.Ed25519();
  final keyPair = await ed25519.newKeyPairFromSeed(privateKeyBytes);
  final signature = await ed25519.sign(canonicalBytes, keyPair: keyPair);
  final signatureBase64 = base64.encode(signature.bytes);

  final envelope = CatalogEnvelope(
    signedPayload: signedPayload,
    signature: signatureBase64,
  );

  await outputCatalogFile.parent.create(recursive: true);
  await outputCatalogFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(envelope.toJson()),
  );

  final reportJson = {
    'catalogId': 'aura-official-development',
    'revision': 1,
    'keyId': 'aura-catalog-development-2026-01',
    'signatureAlgorithm': 'ed25519-v1',
    'issuedAt': issuedAtStr,
    'expiresAt': expiresAtStr,
    'artifacts': reportArtifactsList,
  };

  await reportJsonFile.writeAsString(
    const JsonEncoder.withIndent('  ').convert(reportJson),
  );

  final reportMdBuffer = StringBuffer();
  reportMdBuffer.writeln('# Report Catalogo Ufficiale Development A.U.R.A.');
  reportMdBuffer.writeln();
  reportMdBuffer.writeln('- **Catalog ID**: `aura-official-development`');
  reportMdBuffer.writeln('- **Catalog Revision**: `1`');
  reportMdBuffer.writeln('- **Key ID**: `aura-catalog-development-2026-01`');
  reportMdBuffer.writeln('- **Signature Algorithm**: `ed25519-v1`');
  reportMdBuffer.writeln('- **Issued At**: `$issuedAtStr`');
  reportMdBuffer.writeln('- **Expires At**: `$expiresAtStr`');
  reportMdBuffer.writeln();
  reportMdBuffer.writeln('## Artifacts Descritto');
  reportMdBuffer.writeln();

  for (final a in reportArtifactsList) {
    reportMdBuffer.writeln('### ${a['logicalModelId']}');
    reportMdBuffer.writeln('- **Role**: `${a['role']}`');
    reportMdBuffer.writeln('- **Repository**: `${a['repository']}`');
    reportMdBuffer.writeln('- **Pinned Revision (SHA)**: `${a['revision']}`');
    reportMdBuffer.writeln('- **Filename**: `${a['filename']}`');
    reportMdBuffer.writeln('- **Download URL**: `${a['downloadUrl']}`');
    reportMdBuffer.writeln('- **Size**: `${a['sizeBytes']}` bytes');
    reportMdBuffer.writeln('- **SHA-256**: `${a['sha256']}`');
    reportMdBuffer.writeln('- **Quantization**: `${a['quantization']}`');
    reportMdBuffer.writeln('- **License**: `${a['license']}`');
    reportMdBuffer
        .writeln('- **Verification Status**: `${a['verificationStatus']}`');
    reportMdBuffer.writeln();
  }

  await reportMdFile.writeAsString(reportMdBuffer.toString());

  stdout.writeln(
      'Catalogo firmato generato con successo -> ${outputCatalogFile.path}');
  stdout.writeln('Report JSON generato -> ${reportJsonFile.path}');
  stdout.writeln('Report Markdown generato -> ${reportMdFile.path}');
}
