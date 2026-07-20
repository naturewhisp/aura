/// I motivi per cui il comando /override può essere dichiarato ineligibile.
enum OverrideIneligibilityReason {
  /// Il prompt fornito dopo il comando /override è vuoto o privo di testo.
  emptyPrompt,

  /// Il comando /override è già stato eseguito in precedenza in questa sessione.
  alreadyAttempted,

  /// Il livello di allerta della sessione supera la soglia consentita per la difficoltà corrente.
  alertTooHigh,
}
