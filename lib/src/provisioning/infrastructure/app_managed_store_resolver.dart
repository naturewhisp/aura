import 'dart:convert';
import 'package:meta/meta.dart';
import '../cli/aura_cli_environment.dart';
import 'provisioning_file_system.dart';

/// Risolutore asincrono dell'app managed store effettivo.
///
/// Separa la determinazione puramente sintattica dei percorsi candidati
/// ([AuraCliEnvironment.computeStoreCandidates]) dalla discovery attiva e
/// dalle regole di retrocompatibilità fail-closed sul filesystem.
@immutable
final class AppManagedStoreResolver {
  final ProvisioningFileSystem _fileSystem;

  const AppManagedStoreResolver({
    required ProvisioningFileSystem fileSystem,
  }) : _fileSystem = fileSystem;

  /// Risolve lo store gestito effettivo in base ai candidati forniti.
  ///
  /// Regole di risoluzione:
  /// 1. Se nel canonical store esiste `installation_record.json`:
  ///    - se è JSON valido -> restituisce `canonical`;
  ///    - se è corrotto -> solleva [FormatException] (Fail-Closed, nessun ripiego a legacy).
  /// 2. Se la directory `canonical` esiste già sul filesystem -> restituisce `canonical`.
  /// 3. Se `canonical` non esiste, verifica in ordine i percorsi `legacy`:
  ///    - se un percorso legacy contiene un `installation_record.json` valido -> restituisce quel path legacy;
  ///    - se è corrotto, prosegue la scansione senza fallback silenziosi non verificati.
  /// 4. Se nessuno store valido (canonical o legacy) è presente -> restituisce `canonical` per nuova inizializzazione.
  Future<String> resolveEffectiveStore({
    required AppManagedStoreCandidates candidates,
  }) async {
    final canonicalPath = candidates.canonical;
    final canonicalRecordPath =
        _join(canonicalPath, 'installation_record.json');

    // 1. Controllo presenza installation_record.json nello store canonico
    if (await _fileSystem.fileExists(canonicalRecordPath)) {
      try {
        final content = await _fileSystem.readAsString(canonicalRecordPath);
        final decoded = jsonDecode(content);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException(
            'installation_record.json nello store canonico non è un oggetto Map.',
          );
        }
        return canonicalPath;
      } catch (e) {
        // FAIL-CLOSED: store canonico presente ma corrotto. Vietato il fallback a legacy.
        throw FormatException(
          'Canonical store corrotto in "$canonicalRecordPath": $e. Fail-closed.',
        );
      }
    }

    // 2. Controllo esistenza della directory canonical (es. fresh install già predisposta)
    if (await _fileSystem.directoryExists(canonicalPath)) {
      return canonicalPath;
    }

    // 3. Verifica percorsi legacy per preservare installazioni esistenti senza spostare GB di GGUF
    for (final legacyRoot in candidates.legacy) {
      final legacyRecordPath = _join(legacyRoot, 'installation_record.json');
      if (await _fileSystem.fileExists(legacyRecordPath)) {
        try {
          final content = await _fileSystem.readAsString(legacyRecordPath);
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            return legacyRoot;
          }
        } catch (_) {
          // Record legacy malformato: ignora e prosegue verso gli altri candidati
        }
      }
    }

    // 4. Nessun dato preesistente trovato: usa lo store canonico
    return canonicalPath;
  }

  static String _join(String p1, String p2) {
    if (p1.endsWith('\\') || p1.endsWith('/')) {
      return '$p1$p2';
    }
    final sep = p1.contains('/') ? '/' : '\\';
    return '$p1$sep$p2';
  }
}
