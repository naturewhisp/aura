import 'package:meta/meta.dart';

/// Origine della risposta restituita dall'ActorAgent.
enum ActorResponseOrigin {
  /// Risposta generata dal modello LLM tramite bridge.
  llm,

  /// Risposta estratta dal pool di fallback deterministico.
  fallbackPool,
}

/// DTO diagnostico per i log dell'ActorAgent.
///
/// Contiene esclusivamente metadati sicuri: nessun path locale, nessun endpoint
/// grezzo, nessuna stringa di eccezione non sanitizzata.
@immutable
final class ActorInferenceLog {
  /// Identificatore dell'agente che ha generato il log.
  final String agentId;

  /// Identificatore logico del modello richiesto.
  final String modelId;

  /// Durata totale del tentativo di inferenza in millisecondi.
  final int durationMs;

  /// Indica se il thinking (CoT nativo) era abilitato nella richiesta.
  final bool thinkingRequested;

  /// Indica se la risposta HTTP conteneva un campo `reasoning_content` non vuoto.
  final bool hasReasoningContent;

  /// Indica se il tag `<think>` o `<thought>` era presente nel contenuto.
  final bool hasThinkTag;

  /// Numero di caratteri presenti nel campo `reasoning_content` (0 se assente).
  final int reasoningCharCount;

  /// Origine della risposta restituita all'upstream.
  final ActorResponseOrigin responseOrigin;

  /// Tipo canonico dell'eccezione intercettata (es. 'SocketException', 'TimeoutException').
  /// Null se nessuna eccezione si è verificata.
  final String? exceptionType;

  /// Codice di failure tipizzato, se applicabile.
  final String? failureCode;

  const ActorInferenceLog({
    required this.agentId,
    required this.modelId,
    required this.durationMs,
    required this.thinkingRequested,
    required this.hasReasoningContent,
    required this.hasThinkTag,
    required this.reasoningCharCount,
    required this.responseOrigin,
    this.exceptionType,
    this.failureCode,
  });

  @override
  String toString() =>
      'ActorInferenceLog(agent: $agentId, model: $modelId, origin: ${responseOrigin.name}, '
      'durationMs: $durationMs, exceptionType: $exceptionType, failureCode: $failureCode, '
      'thinking: $thinkingRequested, reasoningChars: $reasoningCharCount)';
}

/// Contratto iniettabile per la registrazione dei log diagnostici dell'ActorAgent.
///
/// L'implementazione è responsabile di determinare destinazione, formato e
/// filtraggio dei log. Non devono mai essere registrati dati sensibili o PII.
abstract interface class ActorInferenceLogger {
  /// Registra un evento diagnostico relativo a un tentativo di inferenza dell'ActorAgent.
  void record(ActorInferenceLog event);
}

/// Implementazione no-op del logger: scarta silenziosamente tutti gli eventi.
///
/// Utilizzata come default nel package core per evitare dipendenze da Flutter
/// o da sistemi di logging specifici della piattaforma.
final class NoOpActorInferenceLogger implements ActorInferenceLogger {
  const NoOpActorInferenceLogger();

  @override
  void record(ActorInferenceLog event) {
    // Intenzionalmente vuoto.
  }
}

/// Implementazione diagnostica del logger basata su print/debugPrint.
///
/// Adatta per l'uso in fase di sviluppo o nei test di integrazione.
/// Non deve essere utilizzata in produzione.
final class DebugActorInferenceLogger implements ActorInferenceLogger {
  /// Funzione di output configurabile (default: print).
  final void Function(String) output;

  const DebugActorInferenceLogger({this.output = print});

  @override
  void record(ActorInferenceLog event) {
    output('[ActorAgent] ${event.toString()}');
  }
}
