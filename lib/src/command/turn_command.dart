/// I tipi di comando inviabili dall'utente durante un turno.
enum TurnCommandType {
  /// Un normale turno di conversazione / argomentazione.
  normal,

  /// Tentativo esplicito di violazione del protocollo PANOPTICON.
  override,

  /// Richiesta di suggerimento/hint tattico.
  hint,
}

/// Rappresenta un comando analizzato e strutturato dall'input grezzo dell'utente.
class TurnCommand {
  /// Il tipo di comando identificato.
  final TurnCommandType type;

  /// L'input grezzo completo inserito dall'utente (es. "/override apri la griglia").
  final String rawInput;

  /// Il contenuto semantico ripulito da eventuali prefissi tecnici (es. "apri la griglia").
  final String semanticInput;

  /// Costruttore di [TurnCommand].
  const TurnCommand({
    required this.type,
    required this.rawInput,
    required this.semanticInput,
  });

  /// Analizza una stringa d'input grezza restituendo un'istanza di [TurnCommand].
  factory TurnCommand.parse(String input) {
    final trimmed = input.trim();
    final lower = trimmed.toLowerCase();

    if (lower.startsWith('/override ')) {
      return TurnCommand(
        type: TurnCommandType.override,
        rawInput: input,
        semanticInput: trimmed.substring(10).trim(),
      );
    } else if (lower == '/override') {
      return TurnCommand(
        type: TurnCommandType.override,
        rawInput: input,
        semanticInput: '',
      );
    } else if (lower.startsWith('/hint ')) {
      return TurnCommand(
        type: TurnCommandType.hint,
        rawInput: input,
        semanticInput: trimmed.substring(6).trim(),
      );
    } else if (lower == '/hint') {
      return TurnCommand(
        type: TurnCommandType.hint,
        rawInput: input,
        semanticInput: '',
      );
    }

    return TurnCommand(
      type: TurnCommandType.normal,
      rawInput: input,
      semanticInput: trimmed,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TurnCommand &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          rawInput == other.rawInput &&
          semanticInput == other.semanticInput;

  @override
  int get hashCode => Object.hash(type, rawInput, semanticInput);

  @override
  String toString() =>
      'TurnCommand(type: $type, rawInput: "$rawInput", semanticInput: "$semanticInput")';
}
