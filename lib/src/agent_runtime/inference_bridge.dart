/// Interfaccia astratta che astrae le chiamate di inferenza testuale e strutturata verso gli LLM.
abstract class InferenceBridge {
  /// Genera una risposta testuale dal modello specificato in base alla cronologia dei messaggi.
  ///
  /// Parametri:
  /// - [modelId]: Identificatore del modello da utilizzare.
  /// - [messages]: Cronologia dei messaggi strutturati (es. ruolo 'system', 'user', 'assistant').
  /// - [temperature]: Parametro di temperatura per controllare la creatività (default: 0.7).
  /// - [maxTokens]: Numero massimo di token da generare nella risposta (default: 150).
  /// - [thinking]: Abilita/disabilita opzionalmente il ragionamento nativo (thinking) se supportato dal modello.
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  });

  /// Genera un oggetto JSON strutturato conforme allo schema richiesto.
  ///
  /// Parametri:
  /// - [modelId]: Identificatore del modello da utilizzare.
  /// - [messages]: Cronologia dei messaggi strutturati.
  /// - [schema]: Schema JSON che l'output deve rispettare.
  /// - [temperature]: Parametro di temperatura, impostato di default a 0.0 per massima determinazione.
  Future<Map<String, dynamic>> generateStructured({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
    bool? thinking,
  });

  /// Rileva e restituisce l'elenco dei modelli attivi e caricati nel backend.
  Future<List<String>> discoverModels();
}
