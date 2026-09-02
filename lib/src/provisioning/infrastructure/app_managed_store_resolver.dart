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
    final canonicalConfigPath =
        _join(canonicalPath, 'model_configuration.json');

    // 1. Controllo presenza installation_record.json o model_configuration.json nello store canonico
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

    if (await _fileSystem.fileExists(canonicalConfigPath)) {
      try {
        final content = await _fileSystem.readAsString(canonicalConfigPath);
        final decoded = jsonDecode(content);
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException(
            'model_configuration.json nello store canonico non è un oggetto Map.',
          );
        }
        return canonicalPath;
      } catch (e) {
        // FAIL-CLOSED: configurazione canonica presente ma corrotta.
        throw FormatException(
          'Configurazione canonica corrotta in "$canonicalConfigPath": $e. Fail-closed.',
        );
      }
    }

    // 2. Verifica percorsi legacy per preservare installazioni e configurazioni esistenti
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

      final legacyConfigPath = _join(legacyRoot, 'model_configuration.json');
      if (await _fileSystem.fileExists(legacyConfigPath)) {
        try {
          final content = await _fileSystem.readAsString(legacyConfigPath);
          final decoded = jsonDecode(content);
          if (decoded is Map<String, dynamic>) {
            return legacyRoot;
          }
        } catch (_) {
          // Config legacy malformata: ignora e prosegue
        }
      }
    }

    // 3. Nessun dato preesistente valido trovato (fresh install): usa lo store canonico
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
