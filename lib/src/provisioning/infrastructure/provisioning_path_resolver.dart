import 'package:meta/meta.dart';
import '../domain/catalog_manifest.dart';
import '../domain/provisioning_options.dart';

/// Centralizza il calcolo e la sanitizzazione dei path applicativi Windows per il provisioning.
@immutable
final class ProvisioningPathResolver {
  final String appManagedRoot;
  final String bundledRoot;

  static final RegExp _invalidCharsRegex = RegExp(r'[<>:"|?*\x00-\x1F]');
  static final RegExp _reservedWindowsNamesRegex = RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
    caseSensitive: false,
  );
  static final RegExp _absolutePathRegex =
      RegExp(r'^(?:[A-Za-z]:[\\/]|/|\\[\\/])');

  ProvisioningPathResolver({
    required String appManagedRoot,
    required String bundledRoot,
  })  : appManagedRoot = canonicalizeRoot(appManagedRoot),
        bundledRoot = canonicalizeRoot(bundledRoot) {
    _validateRoot('appManagedRoot', this.appManagedRoot);
    _validateRoot('bundledRoot', this.bundledRoot);

    if (_canonicalizeKey(this.appManagedRoot) ==
        _canonicalizeKey(this.bundledRoot)) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'appManagedRoot e bundledRoot non possono essere coincidenti.',
      );
    }
  }

  /// Normalizza una root di percorso rimuovendo separatori duplicati, segmenti `.` e trailing slash ridondanti.
  static String canonicalizeRoot(String root) {
    final trimmed = root.trim().replaceAll('/', r'\');
    if (trimmed.isEmpty) return trimmed;

    final isUnc = trimmed.startsWith(r'\\');
    var prefix = '';
    var rest = trimmed;

    if (isUnc) {
      prefix = r'\\';
      rest = trimmed.substring(2);
    } else {
      final driveMatch = RegExp(r'^[A-Za-z]:').firstMatch(trimmed);
      if (driveMatch != null) {
        prefix = driveMatch.group(0)!;
        rest = trimmed.substring(prefix.length);
      }
    }

    final rawSegments = rest.split(r'\');
    final cleanSegments = <String>[];

    for (final seg in rawSegments) {
      final s = seg.trim();
      if (s.isEmpty || s == '.') {
        continue;
      }
      if (s == '..') {
        throw const ProvisioningException(
          reason: ProvisioningFailureReason.invalidCatalog,
          message: 'Path traversal ("..") non ammesso nel percorso di root.',
        );
      }
      cleanSegments.add(s);
    }

    if (cleanSegments.isEmpty) {
      return '$prefix\\';
    }

    final joined = cleanSegments.join(r'\');
    if (prefix.isNotEmpty) {
      return '$prefix\\$joined';
    }
    return joined;
  }

  static String _canonicalizeKey(String root) =>
      canonicalizeRoot(root).toLowerCase();

  static void _validateRoot(String paramName, String root) {
    final trimmed = root.trim();
    if (trimmed.isEmpty) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Il parametro "$paramName" non può essere vuoto.',
      );
    }
    if (trimmed.contains('\x00') || trimmed.contains('..')) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Il parametro "$paramName" contiene caratteri non ammessi (null byte o traversal).',
      );
    }
    if (!_absolutePathRegex.hasMatch(trimmed)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Il parametro "$paramName" deve essere un percorso assoluto valido: "$root".',
      );
    }
  }

  /// Path del file `installation_record.json`.
  String get installationRecordPath =>
      _join(appManagedRoot, 'installation_record.json');

  /// Path del file `active_state.json`.
  String get activeStatePath => _join(appManagedRoot, 'active_state.json');

  /// Path della directory dei runtime app-managed.
  String get runtimesDirectory => _join(appManagedRoot, 'runtimes');

  /// Path della directory dei modelli app-managed.
  String get modelsDirectory => _join(appManagedRoot, 'models');

  /// Path della directory di staging temporaneo.
  String get stagingDirectory => _join(appManagedRoot, 'staging');

  /// Path della directory di cache HTTP/download.
  String get cacheDirectory => _join(appManagedRoot, 'cache');

  /// Path del file `cached_catalog_envelope.json`.
  String get catalogCacheEnvelopePath =>
      _join(cacheDirectory, 'cached_catalog_envelope.json');

  /// Path della directory dei log.
  String get logsDirectory => _join(appManagedRoot, 'logs');

  /// Path della directory del runtime bundled.
  String get bundledRuntimeDirectory => _join(bundledRoot, 'bundled_runtime');

  /// Calcola il path di installazione relativo per un artefatto.
  String resolveRelativeInstallPath({
    required CatalogArtifactType artifactType,
    required String artifactId,
    required String buildOrVersionId,
  }) {
    final cleanId = sanitizeSegment(artifactId);
    final cleanVersion = sanitizeSegment(buildOrVersionId);

    final folder = switch (artifactType) {
      CatalogArtifactType.runtime => 'runtimes',
      CatalogArtifactType.model => 'models',
    };
    return '$folder/$cleanId/$cleanVersion';
  }

  /// Risolve un path relativo (es. `models/gemma-4-12b-it-qat-q4-0/aaec...`) in un path assoluto sotto `appManagedRoot`.
  /// Rifiuta tassativamente path assoluti, prefissi UNC, lettere di unita e path traversal ("..").
  String resolveAppManagedRelativePath(String relativePath) {
    final trimmed = relativePath.trim();
    if (trimmed.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Il path relativo non puo essere vuoto.',
      );
    }

    if (_absolutePathRegex.hasMatch(trimmed) ||
        trimmed.startsWith('/') ||
        trimmed.startsWith('\\')) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Rifiutato path non relativo o assoluto: "$relativePath".',
      );
    }

    final rawSegments = trimmed.replaceAll('/', '\\').split('\\');
    final cleanSegments = <String>[];
    for (final seg in rawSegments) {
      final s = seg.trim();
      if (s.isEmpty) continue;
      cleanSegments.add(sanitizeSegment(s));
    }

    if (cleanSegments.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Path relativo privo di segmenti validi.',
      );
    }

    final relJoined = cleanSegments.join('\\');
    final resolvedAbsolute = canonicalizeRoot(_join(appManagedRoot, relJoined));

    // Boundary Check: assicura che il percorso risolto si trovi rigorosamente all'interno di appManagedRoot
    final normRoot = _canonicalizeKey(appManagedRoot);
    final normResolved = _canonicalizeKey(resolvedAbsolute);

    if (!normResolved.startsWith(normRoot)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Path traversal o escape da appManagedRoot rilevato: "$relativePath".',
      );
    }

    return resolvedAbsolute;
  }

  /// Risolve il path assoluto confinato di un file di payload (`entryFileName`) all'interno della directory dell'installazione.
  /// Rifiuta tassativamente separatori, segmenti traversal ("..") e garantisce il boundary isolato sotto la directory dell'installazione.
  String resolveEntryFilePath({
    required String relativeInstallPath,
    required String entryFileName,
  }) {
    final cleanEntryName = sanitizeSegment(entryFileName);
    final installDirAbsolute =
        resolveAppManagedRelativePath(relativeInstallPath);
    final resolvedFilePath =
        canonicalizeRoot(_join(installDirAbsolute, cleanEntryName));

    final normDir = _canonicalizeKey(installDirAbsolute);
    final normFile = _canonicalizeKey(resolvedFilePath);

    if (!normFile.startsWith(normDir)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Path traversal o escape dalla directory di installazione tramite entryFileName: "$entryFileName".',
      );
    }

    return resolvedFilePath;
  }

  /// Alias per la risoluzione dei path relativi app-managed.
  String resolveAbsolutePath(String relativePath) =>
      resolveAppManagedRelativePath(relativePath);

  /// Helper pubblico per unire due componenti di path in stile Windows.
  String join(String part1, String part2) => _join(part1, part2);

  /// Calcola il path assoluto di installazione finale sotto la root app-managed.
  String resolveAbsoluteInstallPath({
    required CatalogArtifactType artifactType,
    required String artifactId,
    required String buildOrVersionId,
  }) {
    final relative = resolveRelativeInstallPath(
      artifactType: artifactType,
      artifactId: artifactId,
      buildOrVersionId: buildOrVersionId,
    );
    return _join(appManagedRoot, relative.replaceAll('/', '\\'));
  }

  /// Calcola il path assoluto di installazione finale per un [CatalogArtifact].
  String resolveInstalledArtifactPath(CatalogArtifact artifact) {
    final buildPathSegment = artifact.version == artifact.buildId
        ? artifact.version
        : '${artifact.version}_${artifact.buildId}';
    return resolveAbsoluteInstallPath(
      artifactType: artifact.artifactType,
      artifactId: artifact.artifactId,
      buildOrVersionId: buildPathSegment,
    );
  }

  /// Calcola il path assoluto dell'artefatto bundled sotto [bundledRoot].
  String resolveBundledArtifactPath(CatalogArtifact artifact) {
    final assetId = artifact.bundledAssetId ?? artifact.fileName;
    final cleanAssetId = sanitizeSegment(assetId);
    return _join(bundledRoot, cleanAssetId);
  }

  /// Calcola il path della directory temporanea intermedia per l'installazione atomica.
  String resolveIntermediateInstallPath({
    required CatalogArtifact artifact,
    required String operationId,
  }) {
    final cleanOpId = sanitizeSegment(operationId);
    final targetPath = resolveInstalledArtifactPath(artifact);
    return '$targetPath.installing-$cleanOpId';
  }

  /// Calcola il path assoluto della directory di staging per un'operazione.
  String resolveStagingDirectory(String operationId) {
    final cleanOpId = sanitizeSegment(operationId);
    return _join(stagingDirectory, cleanOpId);
  }

  /// Sanitizza e valida rigorosamente un singolo segmento di path.
  /// Rifiuta separatori, traversal, caratteri invalidi e nomi riservati senza alcuna mutazione silenziosa.
  static String sanitizeSegment(String segment) {
    if (segment.isEmpty) {
      throw const ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Il segmento di path non può essere vuoto.',
      );
    }

    if (segment.contains('/') || segment.contains('\\')) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Il segmento di path "$segment" contiene separatori di percorso.',
      );
    }

    if (segment.contains('..')) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Il segmento di path "$segment" contiene path traversal ("..").',
      );
    }

    if (_invalidCharsRegex.hasMatch(segment)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Il segmento di path "$segment" contiene caratteri non validi Windows.',
      );
    }

    final trimmed = segment.trim();
    if (trimmed != segment) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message: 'Il segmento di path "$segment" ha spazi iniziali o finali.',
      );
    }

    if (trimmed.startsWith('.') || trimmed.endsWith('.')) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Il segmento di path "$segment" inizia o termina con un punto.',
      );
    }

    if (_reservedWindowsNamesRegex.hasMatch(trimmed)) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Utilizzo di un nome dispositivo riservato Windows: "$segment".',
      );
    }

    return trimmed;
  }

  /// Helper interno per unire due componenti di path in stile Windows.
  static String _join(String part1, String part2) {
    final p1 = part1.endsWith(r'\') || part1.endsWith('/')
        ? part1.substring(0, part1.length - 1)
        : part1;
    final p2 = part2.startsWith(r'\') || part2.startsWith('/')
        ? part2.substring(1)
        : part2;
    return '$p1\\$p2';
  }
}
