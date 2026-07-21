import 'dart:convert';
import '../../model_handle.dart';
import '../../runtime_failure.dart';
import '../../runtime_ids.dart';
import '../../runtime_requests.dart';
import '../../runtime_results.dart';
import 'external_openai_client.dart';

/// Pure parser responsible for mapping OpenAI HTTP responses into typed runtime results or failures.
class ExternalOpenAiResponseParser {
  const ExternalOpenAiResponseParser();

  /// Maps string finish_reason to [GenerationFinishReason].
  GenerationFinishReason parseFinishReason(String? raw) {
    if (raw == null) return GenerationFinishReason.completed;
    switch (raw.toLowerCase()) {
      case 'stop':
        return GenerationFinishReason.stopSequence;
      case 'length':
        return GenerationFinishReason.maxTokens;
      case 'content_filter':
        return GenerationFinishReason.contentRejected;
      default:
        return GenerationFinishReason.completed;
    }
  }

  /// Parses raw HTTP completion response into a [TextGenerationResult].
  TextGenerationResult parseTextResponse({
    required ExternalOpenAiResponse response,
    required GenerationRequestId requestId,
    required ModelHandle model,
    required Duration latency,
  }) {
    _validateHttpStatus(response, requestId);

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw RuntimeException(
          RuntimeFailure(
            code: RuntimeFailureCode.malformedStructuredOutput,
            message:
                'Il server ha restituito una lista scelte (choices) vuota.',
          ),
        );
      }

      final choice = choices[0] as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>? ?? const {};
      final rawFinishReason = choice['finish_reason'] as String?;

      final content = message['content'] as String? ?? '';
      final reasoning = message['reasoning_content'] as String?;

      final usageMap = data['usage'] as Map<String, dynamic>?;
      final usage = GenerationUsage(
        inputTokens: usageMap?['prompt_tokens'] as int?,
        outputTokens: usageMap?['completion_tokens'] as int?,
        reasoningTokens: usageMap?['reasoning_tokens'] as int?,
      );

      return TextGenerationResult(
        requestId: requestId,
        model: model,
        content: content,
        reasoningContent: reasoning,
        finishReason: parseFinishReason(rawFinishReason),
        usage: usage,
        latency: latency,
        adapterMetadata: {
          'rawFinishReason': rawFinishReason,
          'statusCode': response.statusCode,
        },
      );
    } on RuntimeException {
      rethrow;
    } catch (e) {
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.malformedStructuredOutput,
          message: 'Risposta JSON malformata ricevuta dal server di inferenza.',
        ),
        cause: e,
      );
    }
  }

  /// Parses raw HTTP completion response into a [StructuredGenerationResult].
  StructuredGenerationResult parseStructuredResponse({
    required ExternalOpenAiResponse response,
    required GenerationRequestId requestId,
    required ModelHandle model,
    required Duration latency,
  }) {
    _validateHttpStatus(response, requestId);

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List?;
      if (choices == null || choices.isEmpty) {
        throw RuntimeException(
          RuntimeFailure(
            code: RuntimeFailureCode.malformedStructuredOutput,
            message:
                'Il server ha restituito una lista scelte (choices) vuota per output strutturato.',
          ),
        );
      }

      final choice = choices[0] as Map<String, dynamic>;
      final message = choice['message'] as Map<String, dynamic>? ?? const {};
      final rawFinishReason = choice['finish_reason'] as String?;
      final rawContent = message['content'] as String? ?? '';

      Map<String, Object?>? parsedObject;
      if (rawContent.trim().isNotEmpty) {
        try {
          parsedObject = jsonDecode(rawContent) as Map<String, Object?>?;
        } catch (_) {
          throw const RuntimeException(
            RuntimeFailure(
              code: RuntimeFailureCode.malformedStructuredOutput,
              message:
                  'L\'output del modello non è un JSON valido conforme allo schema.',
            ),
          );
        }
      }

      final usageMap = data['usage'] as Map<String, dynamic>?;
      final usage = GenerationUsage(
        inputTokens: usageMap?['prompt_tokens'] as int?,
        outputTokens: usageMap?['completion_tokens'] as int?,
      );

      return StructuredGenerationResult(
        requestId: requestId,
        model: model,
        rawContent: rawContent,
        parsedObject: parsedObject,
        appliedMode: StructuredOutputMode.jsonSchema,
        finishReason: parseFinishReason(rawFinishReason),
        usage: usage,
        latency: latency,
      );
    } on RuntimeException {
      rethrow;
    } catch (e) {
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.malformedStructuredOutput,
          message:
              'Risposta JSON malformata ricevuta per la generazione strutturata.',
        ),
        cause: e,
      );
    }
  }

  void _validateHttpStatus(
    ExternalOpenAiResponse response,
    GenerationRequestId requestId,
  ) {
    final status = response.statusCode;
    if (status == 200) return;

    if (status == 401 || status == 403) {
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.permissionDenied,
          message:
              'Errore di autenticazione HTTP ($status) verso il backend esterno.',
        ),
      );
    }

    if (status == 404) {
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.modelMissing,
          message: 'Endpoint o modello non trovato (404) nel backend esterno.',
        ),
      );
    }

    if (status == 429) {
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.generationFailed,
          message:
              'Limite di frequenza superato (429 Rate Limit) nel server esterno.',
        ),
      );
    }

    if (status == 499) {
      throw RuntimeException(
        RuntimeFailure(
          code: RuntimeFailureCode.cancelled,
          message: 'Richiesta di generazione cancellata dal client.',
        ),
      );
    }

    throw RuntimeException(
      RuntimeFailure(
        code: RuntimeFailureCode.generationFailed,
        message: 'Errore di inferenza del server esterno (Status $status).',
      ),
    );
  }
}
