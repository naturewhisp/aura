import 'dart:convert';
import 'dart:io';
import 'active_session.dart';
import 'session_repository.dart';

/// Implementazione su file-system di [SessionRepository].
///
/// Salva la sessione attiva nel file `active_session.json` all'interno
/// della cartella specificata dal costruttore [basePath].
///
/// Non accede direttamente a Platform o variabili di ambiente globally scoped.
final class FileSessionRepository implements SessionRepository {
  /// Percorso della directory base che contiene il file della sessione attiva.
  final String basePath;

  /// Crea un'istanza di [FileSessionRepository] con il percorso base fornito.
  const FileSessionRepository({required this.basePath});

  /// Riferimento al file `active_session.json`.
  File get _file => File('$basePath/active_session.json');

  @override
  Future<bool> exists() async {
    return await _file.exists();
  }

  @override
  Future<ActiveSession?> load() async {
    final file = _file;
    if (!await file.exists()) {
      return null;
    }

    final content = await file.readAsString();
    final decoded = jsonDecode(content);

    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        "Il contenuto del file active_session.json deve essere un oggetto JSON, trovato: ${decoded.runtimeType}",
      );
    }

    return ActiveSession.fromJson(decoded);
  }

  @override
  Future<void> save(ActiveSession session) async {
    final dir = Directory(basePath);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    final content = jsonEncode(session.toJson());
    await _file.writeAsString(content);
  }

  @override
  Future<void> delete() async {
    final file = _file;
    if (await file.exists()) {
      await file.delete();
    }
  }
}
