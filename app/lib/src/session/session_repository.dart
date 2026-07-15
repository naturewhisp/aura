import 'active_session.dart';

/// Contratto astratto per la gestione della persistenza della sessione attiva.
///
/// Questa interfaccia definisce esclusivamente le operazioni di I/O relative
/// all'aggregato [ActiveSession]. Non gestisce replay, impostazioni, o audio.
abstract interface class SessionRepository {
  /// Verifica se esiste un salvataggio della sessione attiva.
  ///
  /// Restituisce `true` se il file di salvataggio esiste, `false` altrimenti.
  /// Può propagare eccezioni I/O.
  Future<bool> exists();

  /// Carica la sessione attiva corrente.
  ///
  /// Restituisce `null` se il file non esiste.
  /// Propaga eccezioni I/O ([FileSystemException]) o di formato ([FormatException]).
  Future<ActiveSession?> load();

  /// Salva lo stato della sessione attiva corrente.
  ///
  /// Crea la directory di destinazione se necessario e sovrascrive il file.
  /// Propaga eccezioni I/O ([FileSystemException]).
  Future<void> save(ActiveSession session);

  /// Elimina la sessione attiva corrente.
  ///
  /// Questa operazione deve essere idempotente: non deve fallire se la
  /// sessione attiva non esiste già.
  /// Propaga eccezioni I/O ([FileSystemException]).
  Future<void> delete();
}
