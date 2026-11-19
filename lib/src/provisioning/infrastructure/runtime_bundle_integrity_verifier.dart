import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import '../domain/runtime_manifest.dart';
import 'provisioning_file_system.dart';

/// DTO contenente l'esito della verifica d'integrità fisica dei file della variante di runtime.
@immutable
final class RuntimeVariantIntegrityResult {
  final bool isValid;
  final String variantId;
  final String rootPath;
  final List<String> missingFiles;
  final List<String> corruptedFiles;
  final String? errorMessage;

  const RuntimeVariantIntegrityResult({
    required this.isValid,
    required this.variantId,
    required this.rootPath,
    this.missingFiles = const [],
    this.corruptedFiles = const [],
    this.errorMessage,
  });
}

/// Verificatore dell'integrità fisica e crittografica (SHA-256) dei file di una variante di runtime nativo.
abstract interface class RuntimeBundleIntegrityVerifier {
  Future<RuntimeVariantIntegrityResult> verifyVariant({
    required RuntimeVariantDescriptor variant,
    required String runtimeRootPath,
  });
}

/// Implementazione predefinita del verificatore d'integrità della variante di runtime.
///
/// La variante CUDA supera 1 GB: ricalcolarne lo SHA-256 ad ogni avvio costava
/// circa 10 secondi a cache disco fredda. Quando è configurato
/// [fingerprintCachePath], dopo una verifica completa riuscita vengono salvate
/// le impronte `(dimensione, data di modifica, sha256)` di ogni file; alle
/// verifiche successive un file la cui impronta coincide sia con il disco sia
/// con il manifest non viene riletto. Qualsiasi discrepanza, impronta assente,
/// data non determinabile o cache illeggibile impone la verifica completa
/// (fail-closed).
final class DefaultRuntimeBundleIntegrityVerifier
    implements RuntimeBundleIntegrityVerifier {
  final ProvisioningFileSystem _fileSystem;
  final String? _fingerprintCachePath;
  final Map<String, RuntimeVariantIntegrityResult> _verifiedCache = {};
  Map<String, _FileFingerprint>? _fingerprints;

  DefaultRuntimeBundleIntegrityVerifier({
    required ProvisioningFileSystem fileSystem,
    String? fingerprintCachePath,
  })  : _fileSystem = fileSystem,
        _fingerprintCachePath = fingerprintCachePath;

  @override
  Future<RuntimeVariantIntegrityResult> verifyVariant({
    required RuntimeVariantDescriptor variant,
    required String runtimeRootPath,
  }) async {
    final cacheKey = '$runtimeRootPath#${variant.id}';
    final cached = _verifiedCache[cacheKey];
    if (cached != null && cached.isValid) {
      return cached;
    }

    final fingerprints = await _loadFingerprints();
    final verifiedNow = <String, _FileFingerprint>{};
    final missing = <String>[];
    final corrupted = <String>[];

    for (final entry in variant.files) {
      final normalizedEntryPath = Platform.isWindows
          ? entry.path.replaceAll('/', '\\')
          : entry.path.replaceAll('\\', '/');
      final absoluteFilePath =
          '$runtimeRootPath${Platform.pathSeparator}$normalizedEntryPath';

      if (!await _fileSystem.fileExists(absoluteFilePath)) {
        missing.add(entry.path);
        continue;
      }

      try {
        final size = await _fileSystem.getFileSize(absoluteFilePath);
        if (size != entry.sizeBytes) {
          corrupted.add(
            '${entry.path} (dimensione errata: $size B vs ${entry.sizeBytes} B)',
          );
          continue;
        }

        final modified = await _fileSystem.getLastModified(absoluteFilePath);
        final expectedHash = entry.sha256.toLowerCase();
        final known = fingerprints[absoluteFilePath];
        if (modified != null &&
            known != null &&
            known.matches(
              sizeBytes: size,
              modified: modified,
              sha256: expectedHash,
            )) {
          verifiedNow[absoluteFilePath] = known;
          continue;
        }

        final calculatedHash = await _hashFile(absoluteFilePath);
        if (calculatedHash != expectedHash) {
          corrupted.add(
            '${entry.path} (hash SHA-256 non corrispondente: $calculatedHash vs ${entry.sha256})',
          );
          continue;
        }
        if (modified != null) {
          verifiedNow[absoluteFilePath] = _FileFingerprint(
            sizeBytes: size,
            modifiedUtcMs: modified.toUtc().millisecondsSinceEpoch,
            sha256: calculatedHash,
          );
        }
      } catch (_) {
        corrupted.add('${entry.path} (errore di lettura)');
      }
    }

    final isValid = missing.isEmpty && corrupted.isEmpty;
    String? errorMsg;
    if (!isValid) {
      final parts = <String>[];
      if (missing.isNotEmpty) parts.add('File mancanti: ${missing.join(', ')}');
      if (corrupted.isNotEmpty) {
        parts.add('File corrotti/non corrispondenti: ${corrupted.join(', ')}');
      }
      errorMsg = parts.join(' | ');
    }

    final result = RuntimeVariantIntegrityResult(
      isValid: isValid,
      variantId: variant.id,
      rootPath: runtimeRootPath,
      missingFiles: List.unmodifiable(missing),
      corruptedFiles: List.unmodifiable(corrupted),
      errorMessage: errorMsg,
    );

    if (isValid) {
      _verifiedCache[cacheKey] = result;
      await _storeFingerprints(verifiedNow);
    } else {
      // Una variante non valida non deve lasciare impronte riutilizzabili.
      await _forgetFingerprints(variant, runtimeRootPath);
    }

    return result;
  }

  /// SHA-256 calcolato a chunk, senza caricare il file in memoria.
  ///
  /// Sul filesystem locale il calcolo avviene in un isolate dedicato per non
  /// bloccare il thread UI; le altre implementazioni (es. in memoria nei test)
  /// vengono lette tramite lo stream dell'astrazione.
  Future<String> _hashFile(String path) async {
    if (_fileSystem is LocalProvisioningFileSystem) {
      return Isolate.run(() async {
        final digest = await sha256.bind(File(path).openRead()).first;
        return digest.toString().toLowerCase();
      });
    }
    final digest = await sha256.bind(_fileSystem.openRead(path)).first;
    return digest.toString().toLowerCase();
  }

  Future<Map<String, _FileFingerprint>> _loadFingerprints() async {
    final loaded = _fingerprints;
    if (loaded != null) return loaded;
    final cachePath = _fingerprintCachePath;
    final result = <String, _FileFingerprint>{};
    if (cachePath != null) {
      try {
        if (await _fileSystem.fileExists(cachePath)) {
          final decoded = jsonDecode(await _fileSystem.readAsString(cachePath));
          if (decoded is Map<String, dynamic> &&
              decoded['schemaVersion'] == 1 &&
              decoded['files'] is Map<String, dynamic>) {
            for (final item
                in (decoded['files'] as Map<String, dynamic>).entries) {
              final fingerprint = _FileFingerprint.tryParse(item.value);
              if (fingerprint != null) result[item.key] = fingerprint;
            }
          }
        }
      } catch (_) {
        // Cache illeggibile o corrotta: si ricade sulla verifica completa.
        result.clear();
      }
    }
    return _fingerprints = result;
  }

  Future<void> _storeFingerprints(
    Map<String, _FileFingerprint> verifiedNow,
  ) async {
    if (verifiedNow.isEmpty) return;
    final fingerprints = await _loadFingerprints();
    fingerprints.addAll(verifiedNow);
    await _persist(fingerprints);
  }

  Future<void> _forgetFingerprints(
    RuntimeVariantDescriptor variant,
    String runtimeRootPath,
  ) async {
    final fingerprints = await _loadFingerprints();
    final prefix = '$runtimeRootPath${Platform.pathSeparator}';
    final before = fingerprints.length;
    for (final entry in variant.files) {
      final normalized = Platform.isWindows
          ? entry.path.replaceAll('/', '\\')
          : entry.path.replaceAll('\\', '/');
      fingerprints.remove('$prefix$normalized');
    }
    if (fingerprints.length != before) await _persist(fingerprints);
  }

  Future<void> _persist(Map<String, _FileFingerprint> fingerprints) async {
    final cachePath = _fingerprintCachePath;
    if (cachePath == null) return;
    try {
      final content = jsonEncode({
        'schemaVersion': 1,
        'files': {
          for (final item in fingerprints.entries)
            item.key: item.value.toJson(),
        },
      });
      await _fileSystem.writeStringRecoverably(cachePath, content);
    } catch (_) {
      // Una cache non scritta costa solo una verifica completa al prossimo avvio.
    }
  }
}

/// Impronta di un file già verificato crittograficamente.
@immutable
final class _FileFingerprint {
  final int sizeBytes;
  final int modifiedUtcMs;
  final String sha256;

  const _FileFingerprint({
    required this.sizeBytes,
    required this.modifiedUtcMs,
    required this.sha256,
  });

  bool matches({
    required int sizeBytes,
    required DateTime modified,
    required String sha256,
  }) =>
      this.sizeBytes == sizeBytes &&
      modifiedUtcMs == modified.toUtc().millisecondsSinceEpoch &&
      this.sha256 == sha256;

  static _FileFingerprint? tryParse(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final size = json['sizeBytes'];
    final modified = json['modifiedUtcMs'];
    final hash = json['sha256'];
    if (size is! int || modified is! int || hash is! String) return null;
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)) return null;
    return _FileFingerprint(
      sizeBytes: size,
      modifiedUtcMs: modified,
      sha256: hash,
    );
  }

  Map<String, Object> toJson() => {
        'sizeBytes': sizeBytes,
        'modifiedUtcMs': modifiedUtcMs,
        'sha256': sha256,
      };
}
