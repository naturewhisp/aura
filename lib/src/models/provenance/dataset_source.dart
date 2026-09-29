/// Origine del dato registrato nel replay per la pipeline di curatela dataset (Fase 8).
enum DatasetSource {
  /// Sessione di gioco reale condotta da un utente umano.
  humanPlaytest('human_playtest'),

  /// Sessione generata tramite simulatore o agente sintetico (es. PlayerAgent in headless).
  syntheticSimulation('synthetic_simulation'),

  /// Sessione di test e collaudo condotta direttamente dagli sviluppatori.
  developerEvaluation('developer_evaluation'),

  /// Fonte sconosciuta, non specificata o non convalidata (stato fail-closed).
  unknown('unknown');

  /// Valore serializzato su stringa conforme al wire-format JSON.
  final String wireValue;

  const DatasetSource(this.wireValue);

  /// Decodifica il valore wire-format garantendo la politica fail-closed.
  ///
  /// Se il valore è nullo, vuoto o non riconosciuto, restituisce rigorosamente
  /// [DatasetSource.unknown] e non degrada mai implicitamente a [humanPlaytest].
  static DatasetSource fromString(String? val) {
    if (val == null || val.trim().isEmpty) {
      return DatasetSource.unknown;
    }
    return DatasetSource.values.firstWhere(
      (e) => e.wireValue == val.trim(),
      orElse: () => DatasetSource.unknown,
    );
  }
}
