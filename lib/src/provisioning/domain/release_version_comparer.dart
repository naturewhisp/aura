import 'catalog_artifact_snapshot.dart';
import 'catalog_manifest.dart';
import 'provisioning_options.dart';

/// Comparatore canonico di release per determinare se un candidato di catalogo
/// rappresenta un aggiornamento rispetto ad uno snapshot/installazione esistente.
///
/// Algoritmo di confronto (Strict SemVer 2.0.0):
/// 1. SemVer parsing su [CatalogArtifact.version] o [CatalogArtifactSnapshot.artifactVersion].
///    Richiede formato strict Major.Minor.Patch (es. 1.0.0, 2.0.0-beta.1).
///    Lancia [ProvisioningException] con ragione [ProvisioningFailureReason.invalidCatalog] se la versione è sintatticamente non valida.
/// 2. Se la versione SemVer del candidato è strettamente maggiore → Update (> 0).
/// 3. Se la versione SemVer del candidato è strettamente minore → Downgrade (< 0).
/// 4. Se la versione SemVer è identica:
///    - Se `buildId` e `sha256` sono uguali → Stesso artefatto (0).
///    - Se `buildId` o `sha256` differiscono:
///      - Se `candidate.catalogRevision > current.catalogRevision` → Repack/New Build (> 0).
///      - Se `candidate.catalogRevision == current.catalogRevision` → Conflitto di Fingerprint a parità di versione e revisione (restituisce -2).
///      - Se `candidate.catalogRevision < current.catalogRevision` → Downgrade/revisione precedente (< 0).
final class ReleaseVersionComparer {
  const ReleaseVersionComparer._();

  /// Codice restituito da [compareSnapshots] e [compareSnapshotWithArtifact]
  /// quando due release hanno identica versione SemVer ed identica [catalogRevision],
  /// ma fingerprint (SHA-256 / buildId) differenti.
  static const int sameVersionFingerprintConflict = -2;

  /// Valida sintatticamente una stringa di versione secondo la specifica SemVer 2.0.0 strict.
  static bool isValidSemVer(String versionStr) {
    return _ParsedSemVer.tryParse(versionStr) != null;
  }

  /// Confronta la release corrente con una release candidata dal catalogo.
  /// Restituisce:
  /// - `> 0` se [candidate] è un aggiornamento idoneo rispetto a [current].
  /// - `== 0` se sono identici (stessa versione, stesso sha256 e buildId).
  /// - `== sameVersionFingerprintConflict (-2)` se versione e catalogRevision sono uguali ma il fingerprint differisce.
  /// - `< 0` se [candidate] è precedente o non idoneo come update.
  static int compareSnapshots({
    required CatalogArtifactSnapshot current,
    required CatalogArtifactSnapshot candidate,
  }) {
    final vCurrent = _ParsedSemVer.tryParse(current.artifactVersion);
    if (vCurrent == null) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Versione SemVer non valida per l\'installazione corrente: "${current.artifactVersion}".',
      );
    }

    final vCandidate = _ParsedSemVer.tryParse(candidate.artifactVersion);
    if (vCandidate == null) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Versione SemVer non valida per il candidato: "${candidate.artifactVersion}".',
      );
    }

    final semVerComp = vCandidate.compareTo(vCurrent);
    if (semVerComp != 0) {
      return semVerComp;
    }

    // A parità di versione SemVer:
    if (current.buildId == candidate.buildId &&
        current.sha256.toLowerCase() == candidate.sha256.toLowerCase() &&
        current.sizeBytes == candidate.sizeBytes) {
      return 0; // Stesso identico artefatto
    }

    // Build/sha differenti a parità di SemVer: usiamo catalogRevision come tie-breaker
    if (candidate.catalogRevision == current.catalogRevision) {
      return sameVersionFingerprintConflict;
    }

    return candidate.catalogRevision.compareTo(current.catalogRevision);
  }

  /// Convenienza per confrontare uno snapshot con un [CatalogArtifact].
  static int compareSnapshotWithArtifact({
    required CatalogArtifactSnapshot current,
    required CatalogArtifact candidateArtifact,
    required int candidateCatalogRevision,
  }) {
    final vCurrent = _ParsedSemVer.tryParse(current.artifactVersion);
    if (vCurrent == null) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Versione SemVer non valida per l\'installazione corrente: "${current.artifactVersion}".',
      );
    }

    final vCandidate = _ParsedSemVer.tryParse(candidateArtifact.version);
    if (vCandidate == null) {
      throw ProvisioningException(
        reason: ProvisioningFailureReason.invalidCatalog,
        message:
            'Versione SemVer non valida per l\'artefatto candidato: "${candidateArtifact.version}".',
      );
    }

    final semVerComp = vCandidate.compareTo(vCurrent);
    if (semVerComp != 0) {
      return semVerComp;
    }

    if (current.buildId == candidateArtifact.buildId &&
        current.sha256.toLowerCase() ==
            candidateArtifact.sha256.toLowerCase() &&
        current.sizeBytes == candidateArtifact.sizeBytes) {
      return 0;
    }

    if (candidateCatalogRevision == current.catalogRevision) {
      return sameVersionFingerprintConflict;
    }

    return candidateCatalogRevision.compareTo(current.catalogRevision);
  }
}

/// Helper interno per il parsing ed il confronto conforme alla specifica Semantic Versioning 2.0.0 strict.
final class _ParsedSemVer implements Comparable<_ParsedSemVer> {
  static final RegExp _semVerRegex = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-((?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*)(?:\.(?:0|[1-9]\d*|\d*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:\+([0-9a-zA-Z-]+(?:\.[0-9a-zA-Z-]+)*))?$',
  );

  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  const _ParsedSemVer({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease = const [],
  });

  static _ParsedSemVer? tryParse(String versionStr) {
    final trimmed = versionStr.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final match = _semVerRegex.firstMatch(trimmed);
    if (match == null) {
      return null;
    }

    final maj = int.parse(match.group(1)!);
    final min = int.parse(match.group(2)!);
    final pat = int.parse(match.group(3)!);

    final preReleaseGroup = match.group(4);
    List<String> preParts = const [];
    if (preReleaseGroup != null && preReleaseGroup.isNotEmpty) {
      preParts = preReleaseGroup.split('.');
    }

    return _ParsedSemVer(
      major: maj,
      minor: min,
      patch: pat,
      preRelease: preParts,
    );
  }

  @override
  int compareTo(_ParsedSemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);

    // Regola SemVer: una versione SENZA prerelease ha precedenza su una CON prerelease
    if (preRelease.isEmpty && other.preRelease.isNotEmpty) return 1;
    if (preRelease.isNotEmpty && other.preRelease.isEmpty) return -1;
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;

    // Confronta i segmenti di prerelease
    final minLen = preRelease.length < other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (int i = 0; i < minLen; i++) {
      final a = preRelease[i];
      final b = other.preRelease[i];
      final aNum = int.tryParse(a);
      final bNum = int.tryParse(b);

      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else if (aNum != null && bNum == null) {
        return -1; // Segmento numerico < segmento alfabetico per SemVer
      } else if (aNum == null && bNum != null) {
        return 1;
      } else {
        final strComp = a.compareTo(b);
        if (strComp != 0) return strComp;
      }
    }

    return preRelease.length.compareTo(other.preRelease.length);
  }
}
