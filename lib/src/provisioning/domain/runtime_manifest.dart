import 'package:meta/meta.dart';
import 'runtime_dependency_models.dart';

/// DTO che rappresenta una singola voce file nel `manifest.json` del runtime bundle.
@immutable
final class RuntimeFileEntry {
  final String path;
  final String sha256;

  const RuntimeFileEntry({
    required this.path,
    required this.sha256,
  });

  factory RuntimeFileEntry.fromJson(Map<String, dynamic> json) {
    final p = json['path'] as String?;
    final hash = json['sha256'] as String?;
    if (p == null || p.trim().isEmpty || hash == null || hash.trim().isEmpty) {
      throw const FormatException(
        'Voci "path" e "sha256" obbligatorie in RuntimeFileEntry.',
      );
    }
    return RuntimeFileEntry(
      path: p.trim(),
      sha256: hash.trim().toLowerCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'sha256': sha256,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeFileEntry &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          sha256 == other.sha256;

  @override
  int get hashCode => Object.hash(path, sha256);
}

/// DTO immutabile che descrive il `manifest.json` di un bundle runtime versionato (`llama-server`).
@immutable
final class RuntimeManifest {
  final String runtimeId;
  final String llamaCppCommit;
  final String buildType;
  final RuntimeAcceleration backend;
  final String cudaVersion;
  final String architecture;
  final List<RuntimeFileEntry> files;

  const RuntimeManifest({
    required this.runtimeId,
    required this.llamaCppCommit,
    required this.buildType,
    required this.backend,
    required this.cudaVersion,
    required this.architecture,
    required this.files,
  });

  factory RuntimeManifest.fromJson(Map<String, dynamic> json) {
    final rId = json['runtimeId'] as String?;
    if (rId == null || rId.trim().isEmpty) {
      throw const FormatException(
          'Campo "runtimeId" obbligatorio in RuntimeManifest.');
    }

    final backendStr = (json['backend'] as String? ?? 'cpu').toLowerCase();
    final backendEnum = switch (backendStr) {
      'cuda' => RuntimeAcceleration.cuda,
      'vulkan' => RuntimeAcceleration.vulkan,
      _ => RuntimeAcceleration.cpu,
    };

    final rawFiles = json['files'] as List<dynamic>? ?? [];
    final filesList = rawFiles
        .map((f) => RuntimeFileEntry.fromJson(f as Map<String, dynamic>))
        .toList();

    return RuntimeManifest(
      runtimeId: rId.trim(),
      llamaCppCommit: json['llamaCppCommit'] as String? ?? 'unknown',
      buildType: json['buildType'] as String? ?? 'Release',
      backend: backendEnum,
      cudaVersion: json['cudaVersion'] as String? ?? 'n/a',
      architecture: json['architecture'] as String? ?? 'x86_64',
      files: List.unmodifiable(filesList),
    );
  }

  Map<String, dynamic> toJson() => {
        'runtimeId': runtimeId,
        'llamaCppCommit': llamaCppCommit,
        'buildType': buildType,
        'backend': backend.name,
        'cudaVersion': cudaVersion,
        'architecture': architecture,
        'files': files.map((f) => f.toJson()).toList(),
      };
}
