import 'app_settings.dart';

/// Contratto per la persistenza delle impostazioni dell'applicazione.
///
/// Il repository è responsabile esclusivamente del caricamento e
/// del salvataggio dell'aggregato [AppSettings]. Non applica
/// side effect su AudioManager, notifier o stato di gioco.
abstract interface class SettingsRepository {
  /// Carica le impostazioni dal supporto persistente.
  ///
  /// Restituisce `null` se il file non esiste.
  /// Propaga [FileSystemException] in caso di errori I/O,
  /// [FormatException] se il JSON è malformato o i tipi sono errati.
  Future<AppSettings?> load();

  /// Salva le impostazioni nel supporto persistente.
  ///
  /// Crea la directory di destinazione se necessario.
  /// Propaga [FileSystemException] in caso di errori I/O.
  Future<void> save(AppSettings settings);
}
