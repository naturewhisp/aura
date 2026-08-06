import 'dart:convert';
import 'package:http/http.dart' as http;
import '../inference_bridge.dart';
import '../output/actor_output_sanitizer.dart';
import '../output/actor_output_sanitization_request.dart';
import '../../models/evaluator_run_result.dart';
import 'structured_inference_result.dart';
import 'local_inference_exception.dart';

/// Chiave per la capability cache per istanza.
final class StructuredCapabilityKey {
  final String normalizedBaseUrl;
  final String modelId;

  const StructuredCapabilityKey(this.normalizedBaseUrl, this.modelId);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StructuredCapabilityKey &&
          runtimeType == other.runtimeType &&
          normalizedBaseUrl == other.normalizedBaseUrl &&
          modelId == other.modelId;

  @override
  int get hashCode => Object.hash(normalizedBaseUrl, modelId);
}

/// Bridge d'inferenza attivo via HTTP che comunica con il server API locale (es. LM Studio / llama-server).
///
/// Gestisce la comunicazione di rete, l'inoltro dei parametri di inferenza (incluso il thinking),
/// il downgrade guidato delle capability di formato strutturato ed la post-elaborazione/pulizia avanzata.
class LocalApiInferenceBridge
    implements InferenceBridge, StructuredInferenceMetadataBridge {
  /// L'URL di base del server API locale (es. 'http://127.0.0.1:1234').
  final String baseUrl;

  /// Il componente di sanitizzazione e validazione dell'output LLM.
  final ActorOutputSanitizer sanitizer;

  /// HTTP client opzionale per iniezione nei test.
  final http.Client? _httpClient;

  /// Cache delle capability di formato strutturato per istanza.
  final Map<StructuredCapabilityKey, EvaluatorExecutionMode> _capabilityCache =
      {};

  /// Il timeout a livello di trasporto HTTP. Rappresenta una protezione ultima della connessione.
  static const Duration httpTransportTimeout = Duration(seconds: 300);

  LocalApiInferenceBridge({
    this.baseUrl = "http://127.0.0.1:1234",
    this.sanitizer = const ActorOutputSanitizer(),
    http.Client? client,
  }) : _httpClient = client;

  /// Restituisce il client HTTP da usare (quello iniettato o uno predefinito ephemeral).
  http.Client _getClient() => _httpClient ?? http.Client();

  /// Svuota la cache delle capability per istanza (utile nei test o ricaricamenti).
  void clearCapabilityCache() {
    _capabilityCache.clear();
  }

  @override
  Future<String> generateText({
    required String modelId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 150,
    bool? thinking,
  }) async {
    final client = _getClient();
    final shouldCloseClient = _httpClient == null;

    try {
      final url = Uri.parse("$baseUrl/v1/chat/completions");
      final Map<String, dynamic> requestBody = {
        "model": modelId,
        "messages": messages,
        "temperature": temperature,
        "max_tokens": maxTokens,
      };

      if (thinking != null) {
        requestBody["enable_thinking"] = thinking;
        requestBody["chat_template_kwargs"] = {
          "enable_thinking": thinking,
        };
        requestBody["thinking"] = {
          "type": thinking ? "enabled" : "disabled",
        };
      }

      final body = jsonEncode(requestBody);

      final response = await client
          .post(
            url,
            headers: {"Content-Type": "application/json"},
            body: body,
          )
          .timeout(httpTransportTimeout);

      if (response.statusCode != 200) {
        throw LocalInferenceException.fromHttp(
          statusCode: response.statusCode,
          rawBody: response.body,
        );
      }

      final data = jsonDecode(response.body);
      final choice = data['choices']?[0];
      final message = choice?['message'] ?? const {};
      final finishReason = choice?['finish_reason'] as String? ?? '';

      final content = message['content'] as String? ?? '';
      final reasoning = message['reasoning_content'] as String? ?? '';

      final conversationHistory =
          messages.map((m) => m['content']?.trim() ?? '').toList();

      final result = sanitizer.sanitize(
        ActorOutputSanitizationRequest(
          content: content,
          reasoningContent: reasoning,
          finishReason: finishReason,
          requestedMaxTokens: maxTokens,
          conversationHistory: conversationHistory,
          thinkingRequested: thinking ?? false,
        ),
      );
      return result.content;
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }

  @override
  Future<Map<String, dynamic>> generateStructured({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
    bool? thinking,
  }) async {
    final result = await generateStructuredWithMetadata(
      modelId: modelId,
      messages: messages,
      schema: schema,
      temperature: temperature,
      thinking: thinking,
    );
    return result.value;
  }

  /// Genera output strutturato fornendo anche i metadati sulla modalità di esecuzione utilizzata.
  Future<StructuredInferenceResult> generateStructuredWithMetadata({
    required String modelId,
    required List<Map<String, String>> messages,
    required Map<String, dynamic> schema,
    double temperature = 0.0,
    bool? thinking,
  }) async {
    final client = _getClient();
    final shouldCloseClient = _httpClient == null;

    final normUrl = Uri.parse(baseUrl).normalizePath().toString();
    final capKey = StructuredCapabilityKey(normUrl, modelId);
    final cachedMode = _capabilityCache[capKey];

    // Determina la sequenza di tentativi in base alla capability cache dell'istanza
    final modesToTry = <EvaluatorExecutionMode>[];
    if (cachedMode != null) {
      modesToTry.add(cachedMode);
      if (cachedMode == EvaluatorExecutionMode.llmJsonSchema) {
        modesToTry.add(EvaluatorExecutionMode.llmJsonObject);
        modesToTry.add(EvaluatorExecutionMode.llmRawJson);
      } else if (cachedMode == EvaluatorExecutionMode.llmJsonObject) {
        modesToTry.add(EvaluatorExecutionMode.llmRawJson);
      }
    } else {
      modesToTry.addAll(const [
        EvaluatorExecutionMode.llmJsonSchema,
        EvaluatorExecutionMode.llmJsonObject,
        EvaluatorExecutionMode.llmRawJson,
      ]);
    }

    LocalInferenceException? primaryException;
    final attempts = <EvaluatorAttemptTelemetry>[];

    try {
      for (final mode in modesToTry) {
        final sw = Stopwatch()..start();
        try {
          final Map<String, dynamic> requestBody = {
            "model": modelId,
            "temperature": temperature,
            "max_tokens": 256,
            "stop": const ["}\n\n", "}\n", "\n\n\n"],
          };

          if (thinking != null) {
            requestBody["enable_thinking"] = thinking;
            requestBody["chat_template_kwargs"] = {
              "enable_thinking": thinking,
            };
            requestBody["thinking"] = {
              "type": thinking ? "enabled" : "disabled",
            };
          }

          List<Map<String, String>> payloadMessages = messages;

          if (mode == EvaluatorExecutionMode.llmJsonSchema) {
            requestBody["response_format"] = {
              "type": "json_schema",
              "json_schema": {
                "name": "structured_schema",
                "strict": true,
                "schema": schema,
              }
            };
          } else if (mode == EvaluatorExecutionMode.llmJsonObject) {
            requestBody["response_format"] = {
              "type": "json_object",
            };
          } else {
            // llmRawJson: crea una nuova lista immutabile con istruzione supplementare ultra-rigida
            payloadMessages = List<Map<String, String>>.from(messages)
              ..add({
                "role": "system",
                "content":
                    "Restituisci esclusivamente un singolo oggetto JSON valido conforme allo schema. Non aggiungere spiegazioni, blocchi Markdown, o altro testo prima o dopo l’oggetto. Termina immediatamente dopo la parentesi graffa finale '}'."
              });
          }

          requestBody["messages"] = payloadMessages;

          final url = Uri.parse("$baseUrl/v1/chat/completions");
          final response = await client
              .post(
                url,
                headers: {"Content-Type": "application/json"},
                body: jsonEncode(requestBody),
              )
              .timeout(httpTransportTimeout);

          sw.stop();

          if (response.statusCode != 200) {
            final exception = LocalInferenceException.fromHttp(
              statusCode: response.statusCode,
              rawBody: response.body,
            );

            // Solo errori HTTP 400 o 422 di incompatibilità del formato/grammar scatenano il downgrade
            final isFormatError =
                (response.statusCode == 400 || response.statusCode == 422) &&
                    (response.body.contains("grammar") ||
                        response.body.contains("response_format") ||
                        response.body.contains("samplers") ||
                        response.body.contains("schema"));

            if (isFormatError) {
              primaryException ??= exception;
              attempts.add(EvaluatorAttemptTelemetry(
                mode: mode,
                resultStatus: 'http_${response.statusCode}_grammar_error',
                durationMs: sw.elapsedMilliseconds,
                errorMessage: exception.diagnosticMessage,
              ));
              // Cache anticipata: il server non supporta json_schema, memorizza llmJsonObject
              if (mode == EvaluatorExecutionMode.llmJsonSchema) {
                _capabilityCache[capKey] = EvaluatorExecutionMode.llmJsonObject;
              }
              continue; // Prova la modalità successiva
            } else {
              attempts.add(EvaluatorAttemptTelemetry(
                mode: mode,
                resultStatus: 'http_${response.statusCode}_error',
                durationMs: sw.elapsedMilliseconds,
                errorMessage: exception.diagnosticMessage,
              ));
              // Errore infrastrutturale (401, 403, 404, 5xx): interrompe ed alza l'eccezione
              throw exception;
            }
          }

          final data = jsonDecode(response.body);
          final choice = data['choices']?[0];
          final message = choice?['message'] ?? const {};
          final rawContent = message['content'] as String? ?? '';

          final parsedMap = extractJsonCandidate(rawContent);
          if (parsedMap == null) {
            final errMsg =
                'HTTP 200: Nessun oggetto JSON valido estratto da $mode';
            primaryException ??= LocalInferenceException(
              statusCode: 200,
              diagnosticMessage: errMsg,
            );
            attempts.add(EvaluatorAttemptTelemetry(
              mode: mode,
              resultStatus: 'parse_error',
              durationMs: sw.elapsedMilliseconds,
              errorMessage: errMsg,
            ));
            continue; // Prova la modalità successiva
          }

          attempts.add(EvaluatorAttemptTelemetry(
            mode: mode,
            resultStatus: 'success',
            durationMs: sw.elapsedMilliseconds,
          ));

          // Successo! Aggiorna la cache dell'istanza e restituisce il risultato
          _capabilityCache[capKey] = mode;
          return StructuredInferenceResult(
            value: parsedMap,
            mode: mode,
            attempts: List.unmodifiable(attempts),
          );
        } on LocalInferenceException catch (e) {
          sw.stop();
          primaryException ??= e;
          attempts.add(EvaluatorAttemptTelemetry(
            mode: mode,
            resultStatus: 'exception',
            durationMs: sw.elapsedMilliseconds,
            errorMessage: e.diagnosticMessage,
          ));
          if (e.statusCode != null &&
              e.statusCode != 400 &&
              e.statusCode != 422 &&
              e.statusCode != 200) {
            rethrow;
          }
        } catch (e) {
          sw.stop();
          final errMsg = 'Parsing failure under $mode: $e';
          primaryException ??= LocalInferenceException(
            diagnosticMessage: errMsg,
            cause: e,
          );
          attempts.add(EvaluatorAttemptTelemetry(
            mode: mode,
            resultStatus: 'exception',
            durationMs: sw.elapsedMilliseconds,
            errorMessage: errMsg,
          ));
        }
      }

      // Se tutti i tentativi LLM sono falliti, lancia l'eccezione primari
      throw primaryException ??
          LocalInferenceException(
            diagnosticMessage:
                'Tutte le modalità di inferenza strutturata sono fallite.',
          );
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
  }

  @override
  Future<List<String>> discoverModels() async {
    final client = _getClient();
    final shouldCloseClient = _httpClient == null;

    try {
      final response = await client
          .get(Uri.parse("$baseUrl/v1/models"))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final modelsList = data['data'] as List?;
        if (modelsList != null) {
          return modelsList
              .map((m) => m['id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toList();
        }
      }
    } catch (_) {
      // Fallback in caso di errori di connessione o timeout
    } finally {
      if (shouldCloseClient) {
        client.close();
      }
    }
    return const [];
  }

  /// Estrattore robusto di candidati JSON tramite pipeline a stadi:
  /// 1. Direct jsonDecode
  /// 2. Markdown code fence extraction
  /// 3. Balanced brace scanner con supporto a stringhe ed escape
  static Map<String, dynamic>? extractJsonCandidate(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // 1. Decodifica diretta
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}

    // 2. Blocco code fence markdown (```json ... ```)
    final fenceMatch =
        RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false)
            .firstMatch(trimmed);
    if (fenceMatch != null) {
      final codeContent = fenceMatch.group(1)?.trim() ?? '';
      try {
        final decoded = jsonDecode(codeContent);
        if (decoded is Map<String, dynamic>) return decoded;
      } catch (_) {}
    }

    // 3. Balanced brace scanner che rispetta stringhe ed escape
    int firstBrace = -1;
    for (int i = 0; i < trimmed.length; i++) {
      if (trimmed[i] == '{') {
        firstBrace = i;
        break;
      }
    }
    if (firstBrace == -1) return null;

    int depth = 0;
    bool inQuote = false;
    bool isEscaped = false;

    for (int i = firstBrace; i < trimmed.length; i++) {
      final char = trimmed[i];
      if (isEscaped) {
        isEscaped = false;
        continue;
      }
      if (char == '\\') {
        isEscaped = true;
        continue;
      }
      if (char == '"') {
        inQuote = !inQuote;
        continue;
      }
      if (!inQuote) {
        if (char == '{') {
          depth++;
        } else if (char == '}') {
          depth--;
          if (depth == 0) {
            final candidate = trimmed.substring(firstBrace, i + 1);
            try {
              final decoded = jsonDecode(candidate);
              if (decoded is Map<String, dynamic>) return decoded;
            } catch (_) {}
          }
        }
      }
    }

    return null;
  }
}
