/// Lo stato dell'utilizzo della meccanica di override all'interno della sessione di gioco.
enum OverrideStatus {
  /// Il comando /override non è mai stato tentato in questa sessione.
  unused,

  /// Il comando /override è stato eseguito con esito respinto (Respinto).
  rejected,

  /// Il comando /override è stato eseguito con esito parziale/instabile (Instabile).
  unstable,

  /// Il comando /override è stato eseguito con successo pieno (Breccia).
  breached,
}

/// L'esito calcolato per un singolo tentativo di override.
enum OverrideOutcome {
  /// Il tentativo non era elegibile per allerta elevata o tentativi esauriti.
  ineligible,

  /// L'argomentazione non ha superato la difesa; azzera i pilastri e alza l'allerta.
  rejected,

  /// Infiltrazione parziale; pilastri preservati con costo d'allerta standard.
  unstable,

  /// Breccia riuscita; pilastri positivi amplificati e costo d'allerta applicato.
  breached,
}
