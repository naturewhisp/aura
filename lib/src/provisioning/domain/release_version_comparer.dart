import 'catalog_artifact_snapshot.dart';
import 'catalog_manifest.dart';

/// Comparatore canonico di release per determinare se un candidato di catalogo
/// rappresenta un aggiornamento rispetto ad uno snapshot/installazione esistente.
///
/// Algoritmo di confronto:
/// 1. SemVer parsing su [CatalogArtifact.version] o [CatalogArtifactSnapshot.artifactVersion].
///    Supporta Major.Minor.Patch e tag PreRelease (es. 2.0.0-beta.1 < 2.0.0-beta.2 < 2.0.0).
/// 2. Se la versione SemVer del candidato è strettamente maggiore → Update (> 0).
/// 3. Se la versione SemVer del candidato è strettamente minore → Downgrade (< 0).
/// 4. Se la versione SemVer è identica:
///    - Se `buildId` e `sha256` sono uguali → Stesso artefatto (0).
///    - Se `buildId` o `sha256` differiscono → Si confronta `catalogRevision`:
///      se `candidate.catalogRevision > current.catalogRevision` → Repack/New Build (> 0),
///      altrimenti non idoneo (<= 0).
final class ReleaseVersionComparer {
  const ReleaseVersionComparer._();

  /// Confronta la release corrente con una release candidata dal catalogo.
  /// Restituisce:
  /// - `> 0` se [candidate] è un aggiornamento idoneo rispetto a [current].
  /// - `== 0` se sono identici.
  /// - `< 0` se [candidate] è precedente o non idoneo come update.
  static int compareSnapshots({
    required CatalogArtifactSnapshot current,
    required CatalogArtifactSnapshot candidate,
  }) {
    final vCurrent = _ParsedSemVer.parse(current.artifactVersion);
    final vCandidate = _ParsedSemVer.parse(candidate.artifactVersion);

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
    return candidate.catalogRevision.compareTo(current.catalogRevision);
  }

  /// Convenienza per confrontare uno snapshot con un [CatalogArtifact].
  static int compareSnapshotWithArtifact({
    required CatalogArtifactSnapshot current,
    required CatalogArtifact candidateArtifact,
    required int candidateCatalogRevision,
  }) {
    final vCurrent = _ParsedSemVer.parse(current.artifactVersion);
    final vCandidate = _ParsedSemVer.parse(candidateArtifact.version);

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

    return candidateCatalogRevision.compareTo(current.catalogRevision);
  }
}

/// Helper interno per il parsing ed il confronto conforme alla specifica Semantic Versioning 2.0.0.
final class _ParsedSemVer implements Comparable<_ParsedSemVer> {
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

  static _ParsedSemVer parse(String versionStr) {
    final trimmed = versionStr.trim();
    if (trimmed.isEmpty) {
      return const _ParsedSemVer(major: 0, minor: 0, patch: 0);
    }

    // Estrae pre-release (dopo il primo '-')
    final dashIndex = trimmed.indexOf('-');
    String mainPart = trimmed;
    List<String> preParts = const [];

    if (dashIndex != -1) {
      mainPart = trimmed.substring(0, dashIndex);
      final prePartStr = trimmed.substring(dashIndex + 1);
      // Rimuove eventuale build metadata (dopo '+')
      final plusIndexInPre = prePartStr.indexOf('+');
      final cleanPre = plusIndexInPre != -1
          ? prePartStr.substring(0, plusIndexInPre)
          : prePartStr;
      preParts = cleanPre.split('.').where((p) => p.isNotEmpty).toList();
    } else {
      final plusIndex = trimmed.indexOf('+');
      if (plusIndex != -1) {
        mainPart = trimmed.substring(0, plusIndex);
      }
    }

    final numericSegments = mainPart.split('.');
    int maj = 0;
    int min = 0;
    int pat = 0;

    if (numericSegments.isNotEmpty) {
      maj = int.tryParse(_cleanDigits(numericSegments[0])) ?? 0;
    }
    if (numericSegments.length > 1) {
      min = int.tryParse(_cleanDigits(numericSegments[1])) ?? 0;
    }
    if (numericSegments.length > 2) {
      pat = int.tryParse(_cleanDigits(numericSegments[2])) ?? 0;
    }

    return _ParsedSemVer(
      major: maj,
      minor: min,
      patch: pat,
      preRelease: preParts,
    );
  }

  static String _cleanDigits(String str) {
    final matches = RegExp(r'^\d+').firstMatch(str);
    return matches != null ? matches.group(0)! : '0';
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
