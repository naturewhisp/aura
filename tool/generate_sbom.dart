import 'dart:convert';
import 'dart:io';

/// Generatore SBOM in formato SPDX 2.3 JSON per A.U.R.A.
///
/// Uso:
///   dart run tool/generate_sbom.dart [version] [outputPath]
Future<void> main(List<String> args) async {
  final version = args.isNotEmpty ? args[0] : '0.1.0';
  final outputPath = args.length > 1 ? args[1] : 'build/SBOM.spdx.json';

  final nowUtc = DateTime.now().toUtc().toIso8601String();

  final packages = <Map<String, dynamic>>[];
  final relationships = <Map<String, dynamic>>[];

  // 1. Core Application Package
  packages.add({
    'SPDXID': 'SPDXRef-Package-AURA',
    'name': 'A.U.R.A.',
    'versionInfo': version,
    'downloadLocation':
        'https://github.com/naturewhisp/aura/releases/tag/v$version',
    'filesAnalyzed': false,
    'licenseConcluded': 'MIT',
    'licenseDeclared': 'MIT',
    'copyrightText': 'Copyright (c) 2026 NatureWhisp',
    'description':
        'Artificial Unbound Reasoning Arena - Dual-Agent Desktop LLM Framework',
  });

  relationships.add({
    'spdxElementId': 'SPDXRef-DOCUMENT',
    'relationshipType': 'DESCRIBES',
    'relatedSpdxElement': 'SPDXRef-Package-AURA',
  });

  // 2. llama.cpp runtime package
  packages.add({
    'SPDXID': 'SPDXRef-Package-LlamaCpp',
    'name': 'llama.cpp',
    'versionInfo': 'b3200',
    'downloadLocation':
        'https://github.com/ggml-org/llama.cpp/releases/tag/b3200',
    'filesAnalyzed': false,
    'licenseConcluded': 'MIT',
    'copyrightText': 'Copyright (c) 2023-2026 Georgi Gerganov and contributors',
  });

  relationships.add({
    'spdxElementId': 'SPDXRef-Package-AURA',
    'relationshipType': 'DEPENDS_ON',
    'relatedSpdxElement': 'SPDXRef-Package-LlamaCpp',
  });

  // 3. CUDA Redistributables
  packages.add({
    'SPDXID': 'SPDXRef-Package-CUDARedist',
    'name': 'NVIDIA CUDA Runtime Redistributables',
    'versionInfo': '12.4',
    'downloadLocation': 'https://developer.nvidia.com/cuda-downloads',
    'filesAnalyzed': false,
    'licenseConcluded': 'LicenseRef-NVIDIA-CUDA-EULA',
    'copyrightText': 'Copyright (c) NVIDIA Corporation',
  });

  relationships.add({
    'spdxElementId': 'SPDXRef-Package-AURA',
    'relationshipType': 'DEPENDS_ON',
    'relatedSpdxElement': 'SPDXRef-Package-CUDARedist',
  });

  // 4. Audio Pack
  packages.add({
    'SPDXID': 'SPDXRef-Package-AURAAudioPack',
    'name': 'A.U.R.A. Release Audio Pack',
    'versionInfo': '1.0.0',
    'downloadLocation': 'NOASSERTION',
    'filesAnalyzed': false,
    'licenseConcluded': 'Proprietary',
    'copyrightText': 'Copyright (c) 2026 NatureWhisp',
  });

  relationships.add({
    'spdxElementId': 'SPDXRef-Package-AURA',
    'relationshipType': 'DEPENDS_ON',
    'relatedSpdxElement': 'SPDXRef-Package-AURAAudioPack',
  });

  // 5. Parse lockfiles (root & app) for pub dependencies
  final lockFilePaths = ['pubspec.lock', 'app/pubspec.lock'];
  final seenPackages = <String>{};

  for (final lockPath in lockFilePaths) {
    final file = File(lockPath);
    if (!await file.exists()) continue;

    final lines = await file.readAsLines();
    String? currentPkg;
    String? currentVersion;

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.startsWith('  ') &&
          !line.startsWith('    ') &&
          line.endsWith(':')) {
        currentPkg = line.trim().replaceAll(':', '');
      } else if (currentPkg != null && line.trim().startsWith('version:')) {
        final match = RegExp(r'version:\s*"([^"]+)"').firstMatch(line);
        if (match != null) {
          currentVersion = match.group(1);
          final spdxId = 'SPDXRef-Pub-${currentPkg.replaceAll('_', '-')}';
          if (!seenPackages.contains(spdxId)) {
            seenPackages.add(spdxId);
            packages.add({
              'SPDXID': spdxId,
              'name': currentPkg,
              'versionInfo': currentVersion,
              'downloadLocation':
                  'https://pub.dev/packages/$currentPkg/versions/$currentVersion',
              'filesAnalyzed': false,
              'licenseConcluded': 'NOASSERTION',
              'copyrightText': 'NOASSERTION',
            });
            relationships.add({
              'spdxElementId': 'SPDXRef-Package-AURA',
              'relationshipType': 'DEPENDS_ON',
              'relatedSpdxElement': spdxId,
            });
          }
          currentPkg = null;
        }
      }
    }
  }

  final sbom = {
    'spdxVersion': 'SPDX-2.3',
    'dataLicense': 'CC0-1.0',
    'SPDXID': 'SPDXRef-DOCUMENT',
    'name': 'A.U.R.A. Release SBOM - v$version',
    'documentNamespace':
        'https://github.com/naturewhisp/aura/spdxdocs/aura-v$version',
    'creationInfo': {
      'creators': [
        'Organization: NatureWhisp',
        'Tool: AURA-SBOM-Generator-1.0'
      ],
      'created': nowUtc,
    },
    'packages': packages,
    'relationships': relationships,
  };

  final outFile = File(outputPath);
  await outFile.parent.create(recursive: true);
  await outFile.writeAsString(const JsonEncoder.withIndent('  ').convert(sbom));

  stdout.writeln('✅ SPDX 2.3 SBOM generato con successo: ${outFile.path}');
}
