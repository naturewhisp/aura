import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'window_preferences.dart';

/// Repository per il salvataggio atomico e la lettura sicura delle preferenze di finestra.
final class WindowPreferencesRepository {
  final String storeDirectoryPath;
  final String fileName;

  const WindowPreferencesRepository({
    required this.storeDirectoryPath,
    this.fileName = 'window_preferences.json',
  });

  File get _targetFile => File(p.join(storeDirectoryPath, fileName));

  /// Carica le preferenze salvate su disco. Restituisce le preferenze di default in caso di file assente o corrotto.
  Future<WindowPreferences> load() async {
    try {
      final file = _targetFile;
      if (!await file.exists()) {
        return const WindowPreferences();
      }
      final content = await file.readAsString();
      if (content.trim().isEmpty) {
        return const WindowPreferences();
      }
      final jsonMap = json.decode(content);
      if (jsonMap is! Map<String, dynamic>) {
        return const WindowPreferences();
      }
      return WindowPreferences.fromJson(jsonMap);
    } catch (_) {
      return const WindowPreferences();
    }
  }

  /// Salva atomicamente le preferenze di finestra [preferences] su disco.
  Future<void> save(WindowPreferences preferences) async {
    try {
      final dir = Directory(storeDirectoryPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }

      final target = _targetFile;
      final tempFile = File(p.join(storeDirectoryPath, '$fileName.tmp'));

      final jsonString =
          const JsonEncoder.withIndent('  ').convert(preferences.toJson());
      await tempFile.writeAsString(jsonString);

      if (await target.exists()) {
        await target.delete();
      }
      await tempFile.rename(target.path);
    } catch (_) {
      // Tolleranza ai fallimenti di I/O senza bloccare l'esecuzione
    }
  }
}
