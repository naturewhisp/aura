import 'dart:convert';
import 'dart:io';
import 'app_settings.dart';
import 'settings_repository.dart';

/// Implementazione di [SettingsRepository] basata sul file system.
///
/// Il file viene scritto e letto come `<basePath>/settings.json`.
/// Il percorso base deve essere fornito tramite costruttore; il
/// repository non accede mai a [Platform] o variabili d'ambiente.
///
/// ## Policy errori
/// - [load] propaga [FileSystemException] e [FormatException].
/// - [save] propaga [FileSystemException].
/// Il notifier è responsabile di catturare tali eccezioni.
final class FileSettingsRepository implements SettingsRepository {
  /// Percorso della directory che contiene `settings.json`.
  final String basePath;

  /// Crea un'istanza di [FileSettingsRepository] con il percorso base fornito.
  const FileSettingsRepository({required this.basePath});

  /// File `settings.json` nella directory [basePath].
  File get _settingsFile => File('$basePath/settings.json');

  @override
  Future<AppSettings?> load() async {
    final file = _settingsFile;
    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString();
    final decoded = jsonDecode(content);

    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'Il file settings.json deve contenere un oggetto JSON, '
        'trovato: ${decoded.runtimeType}',
      );
    }

    return AppSettings.fromJson(decoded);
  }

  @override
  Future<void> save(AppSettings settings) async {
    final dir = Directory(basePath);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    await _settingsFile.writeAsString(jsonEncode(settings.toJson()));
  }
}
