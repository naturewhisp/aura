import 'package:meta/meta.dart';
import 'runtime_dependency_models.dart';

/// Eccezione lanciata per manifest di runtime non conformi o malformati.
@immutable
final class RuntimeManifestException implements Exception {
  final String message;

  const RuntimeManifestException(this.message);

  @override
  String toString() => 'RuntimeManifestException: $message';
}

/// Singolo file tracciato nel manifest del runtime nativo.
@immutable
final class RuntimeFileEntry {
  final String path;
  final int sizeBytes;
  final String sha256;

  const RuntimeFileEntry({
    required this.path,
    required this.sizeBytes,
    required this.sha256,
  });

  factory RuntimeFileEntry.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path is! String || path.trim().isEmpty) {
      throw const RuntimeManifestException(
          'Campo "path" mancante o non valido.');
    }
    final cleanPath = path.trim().replaceAll(r'\', '/');

    // Previene path traversal e percorsi assoluti
    if (cleanPath.startsWith('/') ||
        cleanPath.contains(':') ||
        cleanPath.split('/').contains('..')) {
      throw RuntimeManifestException(
        'Percorso non sicuro o assoluto rilevato nel file entry: "$cleanPath".',
      );
    }

    final sizeBytes = json['sizeBytes'];
    if (sizeBytes is! int || sizeBytes < 0) {
      throw const RuntimeManifestException('Campo "sizeBytes" non valido.');
    }
    final sha256 = json['sha256'];
    if (sha256 is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256)) {
      throw const RuntimeManifestException(
        'Campo "sha256" mancante o non valido (richiesta stringa hex di 64 caratteri).',
      );
    }

    return RuntimeFileEntry(
      path: cleanPath,
      sizeBytes: sizeBytes,
      sha256: sha256.trim().toLowerCase(),
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'sizeBytes': sizeBytes,
        'sha256': sha256,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeFileEntry &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          sizeBytes == other.sizeBytes &&
          sha256 == other.sha256;

  @override
  int get hashCode => Object.hash(path, sizeBytes, sha256);
}

/// Descrittore di una variante eseguibile di runtime (`win-x64-cuda`, `win-x64-vulkan`, `win-x64-cpu-avx2`).
@immutable
final class RuntimeVariantDescriptor {
  final String id;
  final RuntimeAcceleration acceleration;
  final String architecture;
  final List<String> requiredCpuFeatures;
  final String executable;
  final String workingDirectory;
  final List<String> vendorDirectories;
  final List<RuntimeFileEntry> files;

  const RuntimeVariantDescriptor({
    required this.id,
    required this.acceleration,
    required this.architecture,
    required this.requiredCpuFeatures,
    required this.executable,
    required this.workingDirectory,
    required this.vendorDirectories,
    required this.files,
  });

  factory RuntimeVariantDescriptor.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const RuntimeManifestException(
        'Campo "id" della variante mancante o non valido.',
      );
    }

    final accelStr = json['acceleration'];
    final accel = RuntimeAcceleration.values.firstWhere(
      (a) => a.name == accelStr,
      orElse: () =>
          throw RuntimeManifestException('Accelerazione non valida: $accelStr'),
    );

    final executable = json['executable'];
    if (executable is! String || executable.trim().isEmpty) {
      throw const RuntimeManifestException(
        'Campo "executable" mancante o non valido.',
      );
    }
    final cleanExec = executable.trim().replaceAll(r'\', '/');
    if (cleanExec.startsWith('/') ||
        cleanExec.contains(':') ||
        cleanExec.split('/').contains('..')) {
      throw RuntimeManifestException(
        'Executable path non sicuro o assoluto nella variante $id: "$cleanExec".',
      );
    }

    final workingDir = json['workingDirectory'];
    if (workingDir is! String || workingDir.trim().isEmpty) {
      throw const RuntimeManifestException(
        'Campo "workingDirectory" mancante o non valido.',
      );
    }
    final cleanWorkDir = workingDir.trim().replaceAll(r'\', '/');
    if (cleanWorkDir.startsWith('/') ||
        cleanWorkDir.contains(':') ||
        cleanWorkDir.split('/').contains('..')) {
      throw RuntimeManifestException(
        'Working directory non sicura nella variante $id: "$cleanWorkDir".',
      );
    }

    final rawVendors = json['vendorDirectories'];
    final vendorDirectories = <String>[];
    if (rawVendors is List) {
      for (final v in rawVendors) {
        if (v is String && v.trim().isNotEmpty) {
          final cleanV = v.trim().replaceAll(r'\', '/');
          if (cleanV.startsWith('/') ||
              cleanV.contains(':') ||
              cleanV.split('/').contains('..')) {
            throw RuntimeManifestException(
              'Vendor directory non sicura nella variante $id: "$cleanV".',
            );
          }
          vendorDirectories.add(cleanV);
        }
      }
    }

    final rawFeatures = json['requiredCpuFeatures'];
    final requiredCpuFeatures = rawFeatures is List
        ? rawFeatures.cast<String>().map((e) => e.trim()).toList()
        : <String>[];

    final rawFiles = json['files'];
    if (rawFiles is! List || rawFiles.isEmpty) {
      throw RuntimeManifestException(
        'La variante $id deve contenere una lista di "files" non vuota.',
      );
    }

    final files = <RuntimeFileEntry>[];
    final seenPaths = <String>{};
    for (final f in rawFiles) {
      final entry = RuntimeFileEntry.fromJson(f as Map<String, dynamic>);
      if (seenPaths.contains(entry.path)) {
        throw RuntimeManifestException(
          'File duplicato "${entry.path}" nella variante $id.',
        );
      }
      seenPaths.add(entry.path);
      files.add(entry);
    }

    return RuntimeVariantDescriptor(
      id: id.trim(),
      acceleration: accel,
      architecture: (json['architecture'] as String? ?? 'x64').trim(),
      requiredCpuFeatures: List.unmodifiable(requiredCpuFeatures),
      executable: cleanExec,
      workingDirectory: cleanWorkDir,
      vendorDirectories: List.unmodifiable(vendorDirectories),
      files: List.unmodifiable(files),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'acceleration': acceleration.name,
        'architecture': architecture,
        'requiredCpuFeatures': requiredCpuFeatures,
        'executable': executable,
        'workingDirectory': workingDirectory,
        'vendorDirectories': vendorDirectories,
        'files': files.map((f) => f.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RuntimeVariantDescriptor &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          acceleration == other.acceleration &&
          architecture == other.architecture &&
          executable == other.executable &&
          workingDirectory == other.workingDirectory;

  @override
  int get hashCode => Object.hash(
        id,
        acceleration,
        architecture,
        executable,
        workingDirectory,
      );
}

/// Contenitore immutabile per il manifest multi-variante del runtime `runtime-manifest.json`.
@immutable
final class RuntimeManifest {
  final int schemaVersion;
  final String runtimeSetId;
  final String llamaCppVersion;
  final String sourceCommit;
  final List<RuntimeVariantDescriptor> variants;

  const RuntimeManifest({
    required this.schemaVersion,
    required this.runtimeSetId,
    required this.llamaCppVersion,
    required this.sourceCommit,
    required this.variants,
  });

  factory RuntimeManifest.fromJson(Map<String, dynamic> json) {
    final schemaVersion = json['schemaVersion'];
    if (schemaVersion is! int || schemaVersion != 1) {
      throw const RuntimeManifestException(
        'Versione di schema manifest non supportata (richiesta: 1).',
      );
    }

    final runtimeSetId = json['runtimeSetId'];
    if (runtimeSetId is! String || runtimeSetId.trim().isEmpty) {
      throw const RuntimeManifestException(
        'Campo "runtimeSetId" mancante o vuoto.',
      );
    }

    final llamaCppVersion = json['llamaCppVersion'] as String? ?? 'unknown';
    final sourceCommit = json['sourceCommit'] as String? ?? 'unknown';

    final rawVariants = json['variants'];
    if (rawVariants is! List || rawVariants.isEmpty) {
      throw const RuntimeManifestException(
        'Campo "variants" deve essere una lista non vuota.',
      );
    }

    final variants = <RuntimeVariantDescriptor>[];
    final seenIds = <String>{};
    for (final v in rawVariants) {
      final variant = RuntimeVariantDescriptor.fromJson(
        v as Map<String, dynamic>,
      );
      if (seenIds.contains(variant.id)) {
        throw RuntimeManifestException(
            'ID variante duplicato: "${variant.id}".');
      }
      seenIds.add(variant.id);
      variants.add(variant);
    }

    return RuntimeManifest(
      schemaVersion: schemaVersion,
      runtimeSetId: runtimeSetId.trim(),
      llamaCppVersion: llamaCppVersion.trim(),
      sourceCommit: sourceCommit.trim(),
      variants: List.unmodifiable(variants),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'runtimeSetId': runtimeSetId,
        'llamaCppVersion': llamaCppVersion,
        'sourceCommit': sourceCommit,
        'variants': variants.map((v) => v.toJson()).toList(),
      };

  RuntimeVariantDescriptor? findVariantById(String id) {
    for (final v in variants) {
      if (v.id == id) return v;
    }
    return null;
  }

  RuntimeVariantDescriptor? findVariantByAcceleration(
    RuntimeAcceleration accel,
  ) {
    for (final v in variants) {
      if (v.acceleration == accel) return v;
    }
    return null;
  }
}
